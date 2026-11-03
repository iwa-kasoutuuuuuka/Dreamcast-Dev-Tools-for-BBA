<#
.SYNOPSIS
  Automatic debug loop over the BBA: build -> wait for dcload-ip -> upload and run -> save the
  console log -> on a crash, turn PC / PR / stack trace into source lines -> with -Watch, rebuild
  and run again whenever a source file changes.

.DESCRIPTION
  Boot dcload-ip once (GDmenu -> the "DCLOAD-IP BBA" entry). After that this script does the rest:
    1. runs the build command (DreamSDK shell) if one is given
    2. waits until the Dreamcast answers ping (dcload-ip answers ping only while it is idle,
       so a reply means "ready for the next program")
    3. runs dc-tool-ip -x <elf> with the console and /pc/ file server, saving the output to
       logs\auto_<date>_<time>.txt
    4. when dc-tool-ip ends, scans the log for KOS crash output (Unhandled exception, stack trace,
       ASSERTION FAILURE, kernel panic) and runs sh-elf-addr2line on every address it finds.
       The result is shown and saved next to the log as *.crash.txt
    5. with -Watch: waits for a source change, rebuilds and goes back to 2. A change while the
       program is still running also triggers a rebuild; the new ELF is sent as soon as dcload-ip
       is back (the program called exit(), or you reset and picked dcload-ip in GDmenu again).

  Settings can come from a preset (profiles\<name>.ps1, a hashtable with Elf, Build, BuildDir,
  Watch, WatchFilter, Iso, CdDir, Prepare). Command line parameters override the preset.

.EXAMPLE
  .\dc_auto.ps1 -Preset hello_bba -Watch
  .\dc_auto.ps1 -Preset bleem2 -Watch
  .\dc_auto.ps1 -Elf H:\work\game\game.elf -Build 'make' -BuildDir H:\work\game -Watch
  .\dc_auto.ps1 -Analyze .\logs\auto_20261103_120000.txt -Elf H:\DC\bleem2\bleem2.elf
#>
param(
    [string]$Preset,
    [string]$Elf,
    [string]$Build,
    [string]$BuildDir,
    [switch]$Watch,
    [string[]]$WatchPath,
    [string[]]$WatchFilter,
    [string]$Iso,
    [string]$CdDir,
    [string]$Ip,
    [switch]$Fast,
    [switch]$Gdb,
    [switch]$NoBuild,
    [int]$WaitTimeout = 0,
    [switch]$WaitReboot,     # first upload only after the Dreamcast was seen rebooting (a program is stuck now)
    [string]$Analyze
)
. "$PSScriptRoot\_common.ps1"

# ---------------------------------------------------------------- settings
$cfg = @{ WatchFilter = @('*.c', '*.h', '*.s', '*.S', '*.cpp', 'Makefile', '*.mk') }
if ($Preset) {
    $pfile = if (Test-Path $Preset) { $Preset } else { Join-Path $DevkitRoot "profiles\$Preset.ps1" }
    if (-not (Test-Path $pfile)) { throw "Preset not found: $pfile" }
    # Dot-sourced so the preset's scriptblocks can use its variables and _common.ps1. Variable names
    # are case-insensitive, so a preset variable like $cdDir would overwrite the -CdDir parameter:
    # save the parameters first and put them back afterwards.
    $savedParams = @{}
    foreach ($n in $MyInvocation.MyCommand.Parameters.Keys) {
        $var = Get-Variable -Name $n -Scope Script -ErrorAction SilentlyContinue
        if ($var) { $savedParams[$n] = $var.Value }
    }
    $p = . $pfile
    foreach ($n in $savedParams.Keys) { Set-Variable -Name $n -Value $savedParams[$n] -Scope Script }
    foreach ($k in $p.Keys) { $cfg[$k] = $p[$k] }
}
foreach ($k in 'Elf', 'Build', 'BuildDir', 'Iso', 'CdDir') {
    $v = Get-Variable -Name $k -ValueOnly
    if ($v) { $cfg[$k] = $v }
}
if ($WatchPath)   { $cfg.Watch = $WatchPath }
if ($WatchFilter) { $cfg.WatchFilter = $WatchFilter }
if (-not $cfg.Elf) { throw 'No ELF. Pass -Elf or -Preset.' }
if ($cfg.Iso -and $cfg.CdDir) { throw 'Use either Iso or CdDir, not both.' }
if (-not $cfg.BuildDir -and $cfg.Build) { $cfg.BuildDir = Split-Path -Parent $cfg.Elf }
if ($Watch -and -not $cfg.Watch) { $cfg.Watch = @($(if ($cfg.BuildDir) { $cfg.BuildDir } else { Split-Path -Parent $cfg.Elf })) }

$addr2line = Join-Path $DcRoot 'sh-elf\bin\sh-elf-addr2line.exe'

# ---------------------------------------------------------------- crash analysis
function Get-CrashReport([string]$logFile, [string]$elfFile) {
    $lines = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
    $notes = New-Object System.Collections.Generic.List[string]
    $addrs = New-Object System.Collections.Generic.List[string]
    $inTrace = $false
    foreach ($l in $lines) {
        if ($l -match 'Unhandled exception: PC ([0-9a-fA-F]{8}), code (\d+), evt ([0-9a-fA-F]{4})') {
            $notes.Add($l.Trim()); $addrs.Add($matches[1])
        }
        elseif ($l -match '^\s*SR [0-9a-fA-F]{8} PR ([0-9a-fA-F]{8})') { $notes.Add($l.Trim()); $addrs.Add($matches[1]) }
        elseif ($l -match 'Encountered (.+?)\.') { $notes.Add("Encountered $($matches[1])") }
        elseif ($l -match 'ASSERTION FAILURE|Assertion ".*" failed|kernel panic|abort\(\)|Stack overflow') { $notes.Add($l.Trim()) }
        elseif ($l -match 'prog\.elf((\s+[0-9a-fA-F]{8})+)') { foreach ($a in ($matches[1].Trim() -split '\s+')) { $addrs.Add($a) } }

        if ($l -match 'Stack Trace \(innermost first\)') { $inTrace = $true; continue }
        if ($l -match 'End Stack Trace') { $inTrace = $false; continue }
        if ($inTrace -and $l -match '^\s*([0-9a-fA-F]{8})\s*$') { $addrs.Add($matches[1]) }
    }
    if ($notes.Count -eq 0 -and $addrs.Count -eq 0) { return $null }

    $uniq = @($addrs | ForEach-Object { $_.ToLower() } | Select-Object -Unique)
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("=== Dreamcast crash report ($(Split-Path -Leaf $logFile)) ===")
    foreach ($n in $notes) { $out.Add("  $n") }
    if ($uniq.Count -gt 0 -and (Test-Path $addr2line) -and (Test-Path $elfFile)) {
        $out.Add('')
        $out.Add("addr2line -f -C -i -e $elfFile")
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        foreach ($a in $uniq) {
            $res = @(& $addr2line -f -C -i -e $elfFile "0x$a" 2>&1 | ForEach-Object { "$_" })
            # output is pairs: function, file:line (more pairs for inlined frames)
            $desc = for ($i = 0; $i + 1 -lt $res.Count; $i += 2) { "$($res[$i]) at $($res[$i + 1])" }
            $out.Add(("  {0}  {1}" -f $a, ($desc -join '  <- inlined in ')))
        }
        $ErrorActionPreference = $old
    }
    return $out
}

if ($Analyze) {
    $r = Get-CrashReport (Resolve-Path $Analyze).Path $cfg.Elf
    if ($r) { $r } else { 'No crash output found in the log.' }
    return
}

# ---------------------------------------------------------------- helpers
$dcIp = Get-DcIp $Ip
$dctool = if ($env:DC_TOOL_IP) { $env:DC_TOOL_IP } else { Assert-Tool 'DcToolIp' }   # env override: tests
$pinger = New-Object System.Net.NetworkInformation.Ping

function Test-Dcload { try { return $pinger.Send($dcIp, 400).Status -eq 'Success' } catch { return $false } }

function Get-SourceStamp {
    if (-not $cfg.Watch) { return '' }
    $files = foreach ($w in $cfg.Watch) {
        if (Test-Path $w -PathType Leaf) { Get-Item $w }
        elseif (Test-Path $w) { Get-ChildItem -Path $w -Recurse -File -Include $cfg.WatchFilter -ErrorAction SilentlyContinue }
    }
    $m = ($files | Measure-Object -Property LastWriteTimeUtc -Maximum)
    return "$($m.Count)|$(if ($m.Maximum) { $m.Maximum.Ticks })"
}

function Invoke-Build {
    if ($NoBuild -or -not $cfg.Build) { return $true }
    Write-Host "`n[build] $($cfg.Build)   ($($cfg.BuildDir))" -ForegroundColor Cyan
    try {
        # a scriptblock (preset) runs in PowerShell, a string runs in the DreamSDK shell
        if ($cfg.Build -is [scriptblock]) { & $cfg.Build } else { Invoke-DreamSdkBash $cfg.Build $cfg.BuildDir }
        Write-Host '[build] OK' -ForegroundColor Green; return $true
    }
    catch { Write-Host "[build] FAILED: $_" -ForegroundColor Red; return $false }
}

# A ping reply alone does NOT mean dcload-ip is idle: dcload also answers ping while a program
# runs, whenever the program does /pc/ or console I/O through it. Uploading then overwrites the
# running program. So upload only when
#   - no other dc-tool-ip is running on this PC (someone else's session owns the Dreamcast), and
#   - our previous dc-tool-ip has ended (the program exited / crashed back to dcload), or the
#     Dreamcast was seen rebooting (no ping for 2+ s, then ping again: reset -> GDmenu -> dcload).
function Wait-Dcload($old) {
    $t0 = Get-Date; $downSince = $null; $sawReboot = $false; $said = ''
    while ($true) {
        $oldAlive = ($old -and -not $old.HasExited) -or ($WaitReboot -and -not $script:rebootSeen)
        $others = @(Get-Process dc-tool-ip -ErrorAction SilentlyContinue | Where-Object { -not $old -or $_.Id -ne $old.Id })
        $up = Test-Dcload
        if (-not $up) { if (-not $downSince) { $downSince = Get-Date } }
        else {
            if ($downSince -and ((Get-Date) - $downSince).TotalSeconds -ge 2) { $sawReboot = $true }
            $downSince = $null
        }
        if ($up -and $others.Count -eq 0 -and (-not $oldAlive -or $sawReboot)) {
            if ($sawReboot) { $script:rebootSeen = $true }
            if ($old -and -not $old.HasExited) { Stop-Process -Id $old.Id -Force -ErrorAction SilentlyContinue }
            if ($said) { Write-Host "[wait] dcload-ip is ready ($dcIp)" -ForegroundColor Green }
            Start-Sleep -Milliseconds 300
            return $true
        }
        $msg = if ($others.Count -gt 0) { "Another dc-tool-ip is running (PID $($others.Id -join ', ')). Waiting for it to end..." }
               elseif ($oldAlive) { 'A program is still running. Exit it, or reset and pick DCLOAD-IP in GDmenu...' }
               else { "No reply from $dcIp. Boot dcload-ip on the Dreamcast (GDmenu -> DCLOAD-IP BBA)..." }
        if ($msg -ne $said) { Write-Host "[wait] $msg" -ForegroundColor Yellow; $said = $msg }
        if ($WaitTimeout -gt 0 -and ((Get-Date) - $t0).TotalSeconds -gt $WaitTimeout) { return $false }
        Start-Sleep -Milliseconds 600
    }
}

function Q([string]$s) { if ($s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s } }

# Runs one upload. Returns 'exit' when dc-tool-ip ended, 'changed' when sources changed meanwhile.
function Invoke-Run([string]$stamp) {
    $elfPath = (Resolve-Path $cfg.Elf).Path
    $dcArgs = @('-q', '-t', $dcIp)
    if ($Fast) { $dcArgs += '-f' }
    if ($Gdb)  { $dcArgs += '-g' }
    if ($script:isoPath) { $dcArgs += @('-i', $script:isoPath) }
    $dcArgs += $DcToolExtraArgs
    $dcArgs += @('-x', $elfPath)

    $logDir = Join-Path $DevkitRoot 'logs'
    New-Item -ItemType Directory -Force $logDir | Out-Null
    $log = Join-Path $logDir ('auto_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    $errLog = "$log.stderr"
    $root = Split-Path -Parent $elfPath
    Write-Host "`n[run] dc-tool-ip $($dcArgs -join ' ')" -ForegroundColor Cyan
    Write-Host "[run] log: $log   (/pc/ = $($root.Substring(0,3)), ELF folder = /pc$(ConvertTo-PcPath $root))"

    $proc = Start-Process -FilePath $dctool -ArgumentList (($dcArgs | ForEach-Object { Q $_ }) -join ' ') `
        -WorkingDirectory $root -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $errLog
    $null = $proc.Handle      # PowerShell 5.1 only keeps ExitCode if the handle was opened
    $script:current = $proc

    # tail the log while dc-tool-ip runs
    while (-not (Test-Path $log)) { Start-Sleep -Milliseconds 50 }
    $fs = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
    $rd = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
    $result = 'exit'
    $nextCheck = (Get-Date).AddSeconds(1)
    try {
        while ($true) {
            $chunk = $rd.ReadToEnd()
            if ($chunk) { [Console]::Write($chunk) }
            if ($proc.HasExited) { $chunk = $rd.ReadToEnd(); if ($chunk) { [Console]::Write($chunk) }; break }
            if ($Watch -and (Get-Date) -gt $nextCheck) {
                $nextCheck = (Get-Date).AddSeconds(1)
                if ((Get-SourceStamp) -ne $stamp) { $result = 'changed'; break }
            }
            Start-Sleep -Milliseconds 100
        }
    } finally { $rd.Dispose() }
    if (Test-Path $errLog) {
        $err = Get-Content $errLog -Raw
        if ($err) { Write-Host $err -ForegroundColor DarkYellow; Add-Content -LiteralPath $log -Value "`n# stderr:`n$err" }
        Remove-Item $errLog -ErrorAction SilentlyContinue
    }

    if ($result -eq 'exit') {
        Write-Host "`n[run] dc-tool-ip ended (exit code $($proc.ExitCode))" -ForegroundColor Cyan
        $report = Get-CrashReport $log $elfPath
        if ($report) {
            $crashFile = [System.IO.Path]::ChangeExtension($log, '.crash.txt')
            $report | Set-Content -LiteralPath $crashFile -Encoding utf8
            $report | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            Write-Host "[run] crash report: $crashFile"
        }
    }
    return $result
}

# ---------------------------------------------------------------- main loop
if ($cfg.Prepare) { & $cfg.Prepare }
$script:isoPath = $null
if ($cfg.Iso) { $script:isoPath = (Resolve-Path $cfg.Iso).Path }
elseif ($cfg.CdDir) {
    $mk = Assert-Tool 'MkIsoFs'
    New-Item -ItemType Directory -Force (Join-Path $DevkitRoot 'build') | Out-Null
    $script:isoPath = Join-Path $DevkitRoot 'build\cdredir.iso'
    Write-Host "[cd] building $script:isoPath from $($cfg.CdDir)"
    Invoke-Native $mk @('-C', '0,0', '-V', 'CDREDIR', '-joliet', '-rock', '-l', '-o', $script:isoPath, (Resolve-Path $cfg.CdDir).Path) -Quiet
}
if ($Watch) { Write-Host "[watch] $($cfg.Watch -join ', ')  ($($cfg.WatchFilter -join ' '))   Ctrl+C to stop" }

$script:current = $null
try {
    $stamp = Get-SourceStamp
    $built = Invoke-Build
    while ($true) {
        if ($built) {
            if (-not (Wait-Dcload $script:current)) { throw "dcload-ip was not ready within $WaitTimeout s" }
            $r = Invoke-Run $stamp
        } else { $r = 'exit' }
        if (-not $Watch) { break }

        if ($r -eq 'exit') {
            Write-Host "[watch] waiting for a source change..." -ForegroundColor DarkGray
            while ((Get-SourceStamp) -eq $stamp) { Start-Sleep -Milliseconds 700 }
        } else {
            Write-Host "`n[watch] source changed while the program runs. Rebuilding; the new ELF goes up when dcload-ip is back" -ForegroundColor Yellow
            Write-Host '        (exit the program, or reset and pick DCLOAD-IP in GDmenu).' -ForegroundColor Yellow
        }
        Start-Sleep -Milliseconds 400     # let the editor finish writing
        $stamp = Get-SourceStamp
        $built = Invoke-Build
    }
} finally {
    if ($script:current -and -not $script:current.HasExited) { Stop-Process -Id $script:current.Id -Force -ErrorAction SilentlyContinue }
}
