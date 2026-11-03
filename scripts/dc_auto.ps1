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
  Watch, WatchFilter, Iso, CdDir, Prepare, ReloadReq, PostRun, RegressSetup, RegressOutput,
  RegressCleanup). Command line parameters override the preset.
    ReloadReq       file created after a -Watch rebuild (or a -Regress time limit) to ask the running
                    program to return to dcload (the program has to poll it, as bleem2 does)
    PostRun         { param($log) ... } run after every run, e.g. turn the log into stats
    RegressSetup    { param($test) ... } prepares one regression test (boot disc, pad script)
    RegressOutput   folder where the program writes SHOT*.bmp
    RegressCleanup  { ... } after the regression run

  -Regress <tests.ps1>: the file returns hashtables (Name, Timeout, Tolerance, MaxDiff and whatever
  RegressSetup reads). Each test runs once; its SHOT*.bmp go to logs\regress\<date>\<name>\ and are
  compared with logs\regress\baseline\<name>\ (the first run becomes the baseline). report.html
  shows baseline / now / difference; the exit code is 1 when a test failed, crashed or timed out.

.EXAMPLE
  .\dc_auto.ps1 -Preset hello_bba -Watch
  .\dc_auto.ps1 -Preset bleem2 -Watch
  .\dc_auto.ps1 -Elf H:\work\game\game.elf -Build 'make' -BuildDir H:\work\game -Watch
  .\dc_auto.ps1 -Analyze .\logs\auto_20261103_120000.txt -Elf H:\DC\bleem2\bleem2.elf
  .\dc_auto.ps1 -Preset bleem2 -Regress .\profiles\bleem2_regress.ps1
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
    [string]$Analyze,
    [string]$Regress,        # test list (.ps1): run each test, collect screenshots, compare with the baseline
    [switch]$UpdateBaseline  # with -Regress: take this run's screenshots as the new baseline
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
    $logPath = (Resolve-Path $Analyze).Path
    # a crashed run keeps a copy of its ELF next to the log: addresses only match that build
    $keptElf = [System.IO.Path]::ChangeExtension($logPath, '.elf')
    $elfForLog = $cfg.Elf
    if (Test-Path $keptElf) { $elfForLog = $keptElf; Write-Host "[analyze] using the ELF kept with the log: $keptElf" }
    elseif ($elfForLog -and (Test-Path $elfForLog) -and (Get-Item $elfForLog).LastWriteTime -gt (Get-Item $logPath).LastWriteTime) {
        Write-Host "[analyze] warning: $elfForLog was rebuilt after this log; function names / lines may be wrong" -ForegroundColor Yellow
    }
    $r = Get-CrashReport $logPath $elfForLog
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

# ---------------------------------------------------------------- reset monitor
# A ping reply alone does NOT mean dcload-ip is idle: dcload also answers ping while a program
# runs, whenever the program does /pc/ or console I/O through it. Uploading then overwrites the
# running program. So upload only when
#   - no other dc-tool-ip is running on this PC (someone else's session owns the Dreamcast), and
#   - our previous dc-tool-ip has ended (the program exited / crashed back to dcload), or the
#     Dreamcast was seen rebooting (no ping for 5+ s, then ping again: reset -> GDmenu -> dcload).
#     A running program answers ping only while it is inside a dcload call, so a program that makes
#     no dcload call for a few seconds looks like a reset. bleem2 polls its reload request once a
#     second to stay visible; the 5 s also covers programs that print now and then.
# The reset check runs in a background runspace for the whole session, so a reset while a build
# runs is not missed.
$script:startTime = Get-Date
$script:mon = [hashtable]::Synchronized(@{ Ip = $dcIp; GapEnd = [datetime]::MinValue; Stop = $false })
function Start-ResetMonitor {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('mon', $script:mon)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        $p = New-Object System.Net.NetworkInformation.Ping; $down = $null
        while (-not $mon.Stop) {
            $ok = $false
            try { $ok = $p.Send($mon.Ip, 400).Status -eq 'Success' } catch { }
            if (-not $ok) { if (-not $down) { $down = Get-Date } }
            else {
                if ($down -and ((Get-Date) - $down).TotalSeconds -ge 5) { $mon.GapEnd = Get-Date }
                $down = $null
            }
            Start-Sleep -Milliseconds 500
        }
    })
    $script:monPs = $ps
    $null = $ps.BeginInvoke()
}
function Stop-ResetMonitor {
    $script:mon.Stop = $true
    if ($script:monPs) { try { $script:monPs.Stop(); $script:monPs.Dispose() } catch { } }
}

function Wait-Dcload($old) {
    $t0 = Get-Date; $said = ''
    $since = if ($old) { $old.StartTime } else { $script:startTime }
    while ($true) {
        $sawReboot = $script:mon.GapEnd -gt $since
        $oldAlive = ($old -and -not $old.HasExited) -or ($WaitReboot -and -not $old)
        $others = @(Get-Process dc-tool-ip -ErrorAction SilentlyContinue | Where-Object { -not $old -or $_.Id -ne $old.Id })
        $up = Test-Dcload
        if ($up -and $others.Count -eq 0 -and (-not $oldAlive -or $sawReboot)) {
            if ($old -and -not $old.HasExited) {
                Write-Host '[wait] the Dreamcast was reset: closing the old dc-tool-ip' -ForegroundColor Yellow
                Stop-Process -Id $old.Id -Force -ErrorAction SilentlyContinue
                $old.WaitForExit(3000) | Out-Null
            }
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

# Runs one upload and returns the run (Proc, Log, Elf, Result, Done). Result is 'exit' when
# dc-tool-ip ended, 'changed' when sources changed meanwhile (-Watch), 'timeout' when TimeoutSec
# passed (the program is asked to exit through ReloadReq first, then dc-tool-ip is closed).
function Invoke-Run([string]$stamp, [int]$TimeoutSec = 0) {
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
    if ($cfg.ReloadReq) { Remove-Item -LiteralPath $cfg.ReloadReq -ErrorAction SilentlyContinue }
    $root = Split-Path -Parent $elfPath
    Write-Host "`n[run] dc-tool-ip $($dcArgs -join ' ')" -ForegroundColor Cyan
    Write-Host "[run] log: $log   (/pc/ = $($root.Substring(0,3)), ELF folder = /pc$(ConvertTo-PcPath $root))"

    $proc = Start-Process -FilePath $dctool -ArgumentList (($dcArgs | ForEach-Object { Q $_ }) -join ' ') `
        -WorkingDirectory $root -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.stderr"
    $null = $proc.Handle      # PowerShell 5.1 only keeps ExitCode if the handle was opened
    $script:current = $proc
    $run = @{ Proc = $proc; Log = $log; Elf = $elfPath; Result = 'exit'; Done = $false }
    $script:lastRun = $run

    # tail the log while dc-tool-ip runs
    while (-not (Test-Path $log)) { Start-Sleep -Milliseconds 50 }
    $fs = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
    $rd = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
    $nextCheck = (Get-Date).AddSeconds(1)
    $t0 = Get-Date; $asked = $null
    try {
        while ($true) {
            $chunk = $rd.ReadToEnd()
            if ($chunk) { [Console]::Write($chunk) }
            if ($proc.HasExited) { $chunk = $rd.ReadToEnd(); if ($chunk) { [Console]::Write($chunk) }; break }
            if ($Watch -and (Get-Date) -gt $nextCheck) {
                $nextCheck = (Get-Date).AddSeconds(1)
                if ((Get-SourceStamp) -ne $stamp) { $run.Result = 'changed'; break }
            }
            if ($TimeoutSec -gt 0 -and ((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) {
                if (-not $asked -and $cfg.ReloadReq) {
                    Write-Host "`n[run] time limit ($TimeoutSec s): asking the program to exit" -ForegroundColor Yellow
                    New-Item -ItemType File -Force -Path $cfg.ReloadReq | Out-Null
                    $asked = Get-Date
                } elseif (-not $asked -or ((Get-Date) - $asked).TotalSeconds -gt 20) {
                    Write-Host "`n[run] time limit ($TimeoutSec s): closing dc-tool-ip" -ForegroundColor Yellow
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    $proc.WaitForExit(3000) | Out-Null
                    $run.Result = 'timeout'; break
                }
            }
            Start-Sleep -Milliseconds 100
        }
    } finally { $rd.Dispose() }
    if ($asked) {
        if ($run.Result -eq 'exit') { $run.Result = 'timeout' }
        Remove-Item -LiteralPath $cfg.ReloadReq -ErrorAction SilentlyContinue
    }
    if ($run.Result -ne 'changed') { Complete-Run $run }
    return $run
}

# After dc-tool-ip ended: stderr into the log, crash report, the preset's PostRun (stats etc.).
# For a run left behind by -Watch this happens once its dc-tool-ip has ended.
function Complete-Run($run) {
    if (-not $run -or $run.Done -or -not $run.Proc.HasExited) { return }
    $run.Done = $true
    $log = $run.Log
    $errLog = "$log.stderr"
    if (Test-Path $errLog) {
        $err = Get-Content $errLog -Raw
        if ($err) { Write-Host $err -ForegroundColor DarkYellow; Add-Content -LiteralPath $log -Value "`n# stderr:`n$err" }
        Remove-Item $errLog -ErrorAction SilentlyContinue
    }
    Write-Host "`n[run] dc-tool-ip ended (exit code $($run.Proc.ExitCode))  $(Split-Path -Leaf $log)" -ForegroundColor Cyan
    $report = Get-CrashReport $log $run.Elf
    if ($report) {
        $crashFile = [System.IO.Path]::ChangeExtension($log, '.crash.txt')
        $report | Set-Content -LiteralPath $crashFile -Encoding utf8
        # keep the crashed build: -Analyze on this log later still resolves the right lines
        Copy-Item -LiteralPath $run.Elf -Destination ([System.IO.Path]::ChangeExtension($log, '.elf')) -ErrorAction SilentlyContinue
        $report | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "[run] crash report: $crashFile"
        $run.Crash = $crashFile
    }
    if ($cfg.PostRun) {
        try { & $cfg.PostRun $log | Out-Host } catch { Write-Host "[post] failed: $_" -ForegroundColor DarkYellow }
    }
}

# ---------------------------------------------------------------- screenshot compare (regression)
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class DcImgDiff {
    // share of pixels (0..1) where any channel differs by more than tol; 1 when the sizes differ.
    // When diffPath is set, writes an image with the changed pixels in red over a dimmed copy.
    public static double Compare(string a, string b, int tol, string diffPath) {
        using (var A = new Bitmap(a)) using (var B = new Bitmap(b)) {
            if (A.Width != B.Width || A.Height != B.Height) return 1.0;
            int w = A.Width, h = A.Height;
            var r = new Rectangle(0, 0, w, h);
            var da = A.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            var db = B.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = da.Stride;
            var pa = new byte[stride * h]; var pb = new byte[db.Stride * h];
            Marshal.Copy(da.Scan0, pa, 0, pa.Length); Marshal.Copy(db.Scan0, pb, 0, pb.Length);
            A.UnlockBits(da); B.UnlockBits(db);
            long bad = 0;
            var pd = diffPath != null ? new byte[stride * h] : null;
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                int i = y * stride + x * 3, j = y * db.Stride + x * 3;
                bool d = Math.Abs(pa[i] - pb[j]) > tol || Math.Abs(pa[i+1] - pb[j+1]) > tol || Math.Abs(pa[i+2] - pb[j+2]) > tol;
                if (d) bad++;
                if (pd != null) {
                    if (d) { pd[i] = 0; pd[i+1] = 0; pd[i+2] = 255; }
                    else { pd[i] = (byte)(pb[j] / 3); pd[i+1] = (byte)(pb[j+1] / 3); pd[i+2] = (byte)(pb[j+2] / 3); }
                }
            }
            if (pd != null) {
                using (var D = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
                    var dd = D.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
                    Marshal.Copy(pd, 0, dd.Scan0, pd.Length); D.UnlockBits(dd);
                    D.Save(diffPath, ImageFormat.Png);
                }
            }
            return (double)bad / ((double)w * h);
        }
    }
}
'@

# ---------------------------------------------------------------- main
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

$script:current = $null
$script:lastRun = $null
Start-ResetMonitor
try {
    # ------------------------------------------------------------ regression run
    if ($Regress) {
        if (-not $cfg.RegressSetup -or -not $cfg.RegressOutput) { throw 'This preset has no RegressSetup / RegressOutput.' }
        $tests = @(. (Resolve-Path $Regress).Path)
        $regRoot = Join-Path $DevkitRoot 'logs\regress'
        $baseRoot = Join-Path $regRoot 'baseline'
        $runDir = Join-Path $regRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
        New-Item -ItemType Directory -Force $runDir, $baseRoot | Out-Null
        Write-Host "[regress] $($tests.Count) test(s) from $Regress -> $runDir" -ForegroundColor Cyan
        if (-not (Invoke-Build)) { throw 'build failed' }
        $results = @()
        foreach ($t in $tests) {
            Write-Host "`n[regress] === $($t.Name) ===" -ForegroundColor Cyan
            Get-ChildItem $cfg.RegressOutput -Filter 'SHOT*.bmp' -ErrorAction SilentlyContinue | Remove-Item -Force
            & $cfg.RegressSetup $t | Out-Host
            if (-not (Wait-Dcload $script:current)) { throw "dcload-ip was not ready within $WaitTimeout s" }
            $timeout = if ($t.Timeout) { [int]$t.Timeout } else { 180 }
            $run = Invoke-Run '' -TimeoutSec $timeout
            $out = Join-Path $runDir $t.Name
            New-Item -ItemType Directory -Force $out | Out-Null
            Copy-Item -LiteralPath $run.Log -Destination (Join-Path $out 'console.txt')
            $shots = @(Get-ChildItem $cfg.RegressOutput -Filter 'SHOT*.bmp' -ErrorAction SilentlyContinue | Sort-Object Name)
            foreach ($s in $shots) { Move-Item -LiteralPath $s.FullName -Destination $out -Force }
            $base = Join-Path $baseRoot $t.Name
            $rows = @(); $status = 'PASS'
            if ($run.Crash) { $status = 'CRASH' } elseif ($run.Result -eq 'timeout') { $status = 'TIMEOUT' } elseif ($shots.Count -eq 0) { $status = 'NOSHOT' }
            $tol = if ($t.Tolerance) { [int]$t.Tolerance } else { 24 }
            $maxDiff = if ($t.MaxDiff) { [double]$t.MaxDiff } else { 0.005 }
            foreach ($s in $shots) {
                $cur = Join-Path $out $s.Name
                $ref = Join-Path $base $s.Name
                if ($UpdateBaseline -or -not (Test-Path $ref)) {
                    New-Item -ItemType Directory -Force $base | Out-Null
                    Copy-Item -LiteralPath $cur -Destination $ref -Force
                    $rows += @{ Shot = $s.Name; Diff = $null; Note = 'new baseline' }
                    if ($status -eq 'PASS') { $status = 'NEW' }
                    continue
                }
                $diffPng = Join-Path $out ($s.BaseName + '_diff.png')
                $d = [DcImgDiff]::Compare($ref, $cur, $tol, $diffPng)
                $bad = $d -gt $maxDiff
                if ($bad -and ($status -eq 'PASS' -or $status -eq 'NEW')) { $status = 'FAIL' }
                $rows += @{ Shot = $s.Name; Diff = $d; Note = $(if ($bad) { 'DIFFERENT' } else { 'ok' }); DiffPng = (Split-Path -Leaf $diffPng); Ref = $ref }
            }
            $color = @{ PASS = 'Green'; NEW = 'Cyan'; FAIL = 'Red'; CRASH = 'Red'; TIMEOUT = 'Red'; NOSHOT = 'Red' }[$status]
            Write-Host ("[regress] {0}: {1} ({2} shot(s))" -f $t.Name, $status, $shots.Count) -ForegroundColor $color
            foreach ($r in $rows) { Write-Host ("            {0}  {1}  {2}" -f $r.Shot, $(if ($null -ne $r.Diff) { '{0:P2}' -f $r.Diff } else { '-' }), $r.Note) }
            $results += @{ Name = $t.Name; Status = $status; Rows = $rows; Out = $out; Log = $run.Log; Crash = $run.Crash }
        }
        if ($cfg.RegressCleanup) { & $cfg.RegressCleanup | Out-Host }

        # report.html: one row per screenshot, baseline / now / difference side by side
        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
        $h = New-Object System.Text.StringBuilder
        [void]$h.Append('<!doctype html><meta charset="utf-8"><title>Regression ' + (Split-Path -Leaf $runDir) + '</title>')
        [void]$h.Append('<style>body{font:14px sans-serif;margin:16px}td,th{border:1px solid #999;padding:4px;vertical-align:top}table{border-collapse:collapse}img{image-rendering:pixelated;max-width:320px}.PASS,.NEW{color:#070}.FAIL,.CRASH,.TIMEOUT,.NOSHOT{color:#c00;font-weight:bold}</style>')
        [void]$h.Append('<h1>Regression ' + (Split-Path -Leaf $runDir) + '</h1><table><tr><th>test</th><th>result</th><th>shot</th><th>baseline</th><th>now</th><th>difference</th></tr>')
        foreach ($r in $results) {
            $name = & $enc $r.Name
            $note = if ($r.Crash) { '<br>' + (& $enc ((Get-Content $r.Crash) -join "`n")) -replace "`n", '<br>' } else { '' }
            if ($r.Rows.Count -eq 0) { [void]$h.Append("<tr><td>$name</td><td class=`"$($r.Status)`">$($r.Status)$note</td><td colspan=4>no screenshots</td></tr>") }
            foreach ($row in $r.Rows) {
                $baseImg = '../baseline/' + $r.Name + '/' + $row.Shot
                $curImg = $r.Name + '/' + $row.Shot
                $diffCell = if ($row.DiffPng) { "<img src=`"$($r.Name)/$($row.DiffPng)`"><br>" + ('{0:P2}' -f $row.Diff) + " $($row.Note)" } else { & $enc $row.Note }
                [void]$h.Append("<tr><td>$name</td><td class=`"$($r.Status)`">$($r.Status)$note</td><td>$(& $enc $row.Shot)</td><td><img src=`"$baseImg`"></td><td><img src=`"$curImg`"></td><td>$diffCell</td></tr>")
            }
        }
        [void]$h.Append('</table>')
        $report = Join-Path $runDir 'report.html'
        Set-Content -LiteralPath $report -Value $h.ToString() -Encoding utf8
        Write-Host "`n[regress] report: $report" -ForegroundColor Cyan
        $failed = @($results | Where-Object { $_.Status -notin 'PASS', 'NEW' })
        Write-Host ("[regress] {0} passed, {1} failed" -f ($results.Count - $failed.Count), $failed.Count) -ForegroundColor $(if ($failed.Count) { 'Red' } else { 'Green' })
        $script:exitCode = if ($failed.Count) { 1 } else { 0 }
    } else {

    # ------------------------------------------------------------ normal / -Watch loop
    if ($Watch) { Write-Host "[watch] $($cfg.Watch -join ', ')  ($($cfg.WatchFilter -join ' '))   Ctrl+C to stop" }
    $stamp = Get-SourceStamp
    $built = Invoke-Build
    while ($true) {
        if ($built) {
            if (-not (Wait-Dcload $script:current)) { throw "dcload-ip was not ready within $WaitTimeout s" }
            Complete-Run $script:lastRun          # a run left behind by -Watch (it has ended now)
            $r = (Invoke-Run $stamp).Result
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
        # the program still runs: ask it to return to dcload (presets with ReloadReq, e.g. bleem2)
        if ($built -and $r -eq 'changed' -and $cfg.ReloadReq -and $script:current -and -not $script:current.HasExited) {
            New-Item -ItemType File -Force -Path $cfg.ReloadReq | Out-Null
            Write-Host "[watch] asked the program to return to dcload ($($cfg.ReloadReq))" -ForegroundColor Yellow
        }
    }
    }
} finally {
    if ($script:current -and -not $script:current.HasExited) { Stop-Process -Id $script:current.Id -Force -ErrorAction SilentlyContinue }
    Stop-ResetMonitor
}
if ($script:exitCode) { exit $script:exitCode }
