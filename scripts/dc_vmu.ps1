<#
.SYNOPSIS
  Real VMU <-> PC over the BBA, and save editing with VMU Workbench (third_party\vmu-workbench).

.DESCRIPTION
  -Dump     reads the whole VMU (128 KB, every block, mini-games and copy-protected files too) into
            logs\vmu\<slot>_<date>.bin and lists its files.
  -Restore  writes an image back to the VMU. It first dumps the VMU as it is now (logs\vmu\<slot>_<date>_before.bin),
            then writes and verifies every block. Asks for confirmation unless -Yes.
  -ExportPs1 / -ImportPs1  bleem2's PS1 memory card (file BLEEMMC, compressed) <-> a plain 128 KB card
            (.mcr / .mcd; .gme on import) for MemcardRex and similar tools. -Image defaults to the newest dump;
            -ImportPs1 writes a new image (<image>_ps1.bin) and leaves the dump as it is.
  -List     files on an image (and the PS1 saves inside BLEEMMC).
  -Gui      starts the VMU Workbench editor (http://localhost:8765/) for hex / icon / named-field editing.

  Dump and restore run emu\vmutransfer from VMU Workbench through dc_auto.ps1 (build -> wait for
  dcload-ip -> upload -> the program does the job, writes logs\vmu\vmu_result.txt and returns to dcload).
  Needs Node.js for the editing commands.

.EXAMPLE
  .\dc_vmu.ps1 -Dump
  .\dc_vmu.ps1 -ExportPs1 card.mcr                 # newest dump -> card.mcr, edit it in MemcardRex
  .\dc_vmu.ps1 -ImportPs1 card.mcr                 # -> logs\vmu\a1_..._ps1.bin
  .\dc_vmu.ps1 -Restore .\logs\vmu\a1_20261103_213000_ps1.bin
#>
param(
    [switch]$Dump,
    [string]$Restore,
    [string]$ExportPs1,
    [string]$ImportPs1,
    [switch]$List,
    [switch]$Gui,
    [string]$Image,                  # image for -ExportPs1 / -ImportPs1 / -List (default: newest dump)
    [string]$Name = 'BLEEMMC',       # VMU file that holds the PS1 card
    [ValidatePattern('^[a-dA-D][12]$')] [string]$Slot = 'a1',
    [string]$Ip,
    [int]$WaitTimeout = 0,
    [switch]$NoNotify,               # passed to dc_auto.ps1: no toast notifications
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$root = Split-Path $PSScriptRoot -Parent
$wb = Join-Path $root 'third_party\vmu-workbench'
$cli = Join-Path $wb 'cli.js'
$vmuDir = Join-Path $root 'logs\vmu'
New-Item -ItemType Directory -Force $vmuDir | Out-Null
$env:DCVMU_HISTORY_DIR = Join-Path $vmuDir 'history'     # VMU Workbench backs up an image before each change
$Slot = $Slot.ToLower()

function Invoke-Wb([string[]]$a) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js (node) is needed for this command: https://nodejs.org/' }
    & node $cli @a
    if ($LASTEXITCODE -ne 0) { throw "vmu-workbench $($a[0]) failed" }
}
function Get-NewestDump {
    # the newest plain dump of this slot. *_before.bin (the card as it was before a -Restore) is only
    # used when there is no plain dump: editing it and restoring it again would undo the restore
    $all = @(Get-ChildItem $vmuDir -Filter "$($Slot)_*.bin" -File | Where-Object { $_.Name -match '^[a-d][12]_\d{8}_\d{6}(_before)?\.bin$' } |
             Sort-Object LastWriteTime -Descending)
    $f = @($all | Where-Object { $_.Name -notlike '*_before.bin' }) + $all | Select-Object -First 1
    if (-not $f) { throw "no dump of $($Slot.ToUpper()) in $vmuDir yet: run .\dc_vmu.ps1 -Dump first, or pass -Image" }
    if ($f.Name -like '*_before.bin') { Write-Host "[vmu] using $($f.Name) (the card before the last -Restore; no newer dump)" -ForegroundColor Yellow }
    return $f.FullName
}

# Runs vmutransfer once with the given command ("dump a1" / "dump restore a1"); returns the result lines.
function Invoke-Transfer([string]$command) {
    $romDir = Join-Path $wb 'emu\vmutransfer'
    $pcDir = '/pc' + (ConvertTo-PcPath $vmuDir)
    if ((Split-Path -Qualifier $vmuDir) -ne (Split-Path -Qualifier $romDir)) { throw 'logs\ and third_party\ must be on the same drive (/pc/ is the drive of the ELF)' }
    # a vmu_dump.bin left by an earlier run that failed may be the only copy of a card: keep it
    $left = Join-Path $vmuDir 'vmu_dump.bin'
    if ((Test-Path $left) -and (Get-Item $left).Length -eq 131072) {
        $keep = Join-Path $vmuDir ("{0}_{1}_unsaved.bin" -f $Slot, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Move-Item -LiteralPath $left -Destination $keep
        Write-Host "[vmu] an earlier dump had not been saved: kept as $keep" -ForegroundColor Yellow
    }
    foreach ($f in 'vmu_dump.bin', 'vmu_result.txt') { Remove-Item -LiteralPath (Join-Path $vmuDir $f) -ErrorAction SilentlyContinue }
    Set-Content -LiteralPath (Join-Path $vmuDir 'vmu_cmd') -Value $command -Encoding ascii -NoNewline
    $a = @{ Elf = (Join-Path $romDir 'vmutransfer.elf'); BuildDir = $romDir; Build = "make VMU_PC_DIR=$pcDir"; WaitTimeout = $WaitTimeout }
    if ($Ip) { $a.Ip = $Ip }
    if ($NoNotify) { $a.NoNotify = $true }
    & (Join-Path $PSScriptRoot 'dc_auto.ps1') @a
    Remove-Item -LiteralPath (Join-Path $vmuDir 'vmu_cmd') -ErrorAction SilentlyContinue
    $res = Join-Path $vmuDir 'vmu_result.txt'
    if (-not (Test-Path $res)) { throw 'vmutransfer did not report a result (see the log above)' }
    $lines = @(Get-Content $res)
    if ($lines -notcontains 'END OK') { throw "vmutransfer failed: $($lines -join ' / ')" }
    return $lines
}
function Save-Dump([string]$suffix) {
    $tmp = Join-Path $vmuDir 'vmu_dump.bin'
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -ne 131072) { throw 'the dump did not arrive (vmu_dump.bin missing or not 128 KB)' }
    $out = Join-Path $vmuDir ("{0}_{1}{2}.bin" -f $Slot, (Get-Date -Format 'yyyyMMdd_HHmmss'), $suffix)
    Move-Item -LiteralPath $tmp -Destination $out -Force
    return $out
}
function Show-Image([string]$img) {
    Write-Host "`n[vmu] $img" -ForegroundColor Cyan
    Invoke-Wb @('list', $img)
    $ErrorActionPreference = 'Continue'   # with 'Stop', any line on stderr from node throws in PowerShell 5.1
    $files = & node $cli list $img 2>$null
    if ($files -match "^$Name\s") { Write-Host "[vmu] PS1 memory card in $Name :"; & node $cli ps1-list $img $Name }
}

if ($Dump) {
    Invoke-Transfer "dump $Slot" | Out-Null
    $out = Save-Dump ''
    Write-Host "[vmu] dumped $($Slot.ToUpper()) -> $out" -ForegroundColor Green
    Show-Image $out
}
elseif ($Restore) {
    $img = (Resolve-Path $Restore).Path
    if ((Get-Item $img).Length -ne 131072) { throw "$img is not a 128 KB VMU image" }
    Invoke-Wb @('check', $img)
    if (-not $Yes) {
        Write-Host "This overwrites the whole VMU in $($Slot.ToUpper()) with $img." -ForegroundColor Yellow
        Write-Host 'The VMU is dumped first (logs\vmu\*_before.bin), so it can be put back.' -ForegroundColor Yellow
        if ((Read-Host 'Type yes to write') -ne 'yes') { Write-Host '[vmu] cancelled'; return }
    }
    Copy-Item -LiteralPath $img -Destination (Join-Path $vmuDir 'vmu_restore.bin') -Force
    try { $r = Invoke-Transfer "dump restore $Slot" }
    finally {
        Remove-Item -LiteralPath (Join-Path $vmuDir 'vmu_restore.bin') -ErrorAction SilentlyContinue
        # save the card as it was before writing even when the write failed: it may be the only good copy
        if (Test-Path (Join-Path $vmuDir 'vmu_dump.bin')) {
            $before = Save-Dump '_before'
            Write-Host "[vmu] VMU before writing -> $before" -ForegroundColor Green
        }
    }
    Write-Host "[vmu] written and verified: $(($r | Where-Object { $_ -like 'restore*' }) -join ' ')" -ForegroundColor Green
}
elseif ($ExportPs1) {
    $img = if ($Image) { (Resolve-Path $Image).Path } else { Get-NewestDump }
    Invoke-Wb @('ps1-export', $img, $Name, $ExportPs1)
}
elseif ($ImportPs1) {
    $img = if ($Image) { (Resolve-Path $Image).Path } else { Get-NewestDump }
    $out = [System.IO.Path]::ChangeExtension($img, $null).TrimEnd('.') + '_ps1.bin'
    Copy-Item -LiteralPath $img -Destination $out -Force
    # a failed import (e.g. the card does not fit) must not leave a *_ps1.bin that looks like the new card
    try { Invoke-Wb @('ps1-import', $out, $Name, $ImportPs1) }
    catch { Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue; throw }
    Invoke-Wb @('check', $out)
    Write-Host "[vmu] new image: $out   (write it to the VMU: .\dc_vmu.ps1 -Restore `"$out`")" -ForegroundColor Green
}
elseif ($List) {
    Show-Image $(if ($Image) { (Resolve-Path $Image).Path } else { Get-NewestDump })
}
elseif ($Gui) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js (node) is needed: https://nodejs.org/' }
    Write-Host "[vmu] VMU Workbench: http://localhost:8765/   (open an image from $vmuDir; Ctrl+C to stop)" -ForegroundColor Cyan
    Start-Process 'http://localhost:8765/'
    & node (Join-Path $wb 'serve.js')
}
else {
    Get-Help $PSCommandPath -Detailed
}
