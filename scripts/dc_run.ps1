<#
.SYNOPSIS
  Uploads an ELF to the Dreamcast over the BBA (dcload-ip) and runs it, with the
  dc-tool console (printf output) and the /pc/ host file server attached.

.PARAMETER Elf      Program to run (.elf is best: dc-tool loads each section at its address).
.PARAMETER Ip       Dreamcast IP (default: $DcIp in config\bba.config.ps1).
.PARAMETER Iso      ISO image served as the Dreamcast's /cd/ (cdfs redirection, no burning needed).
.PARAMETER CdDir    Folder to turn into a temporary ISO and serve as /cd/ (e.g. a game's disc folder).
.PARAMETER Fast     Pass -f (no FIFO delays, faster upload, may drop packets).
.PARAMETER Gdb      Also start the GDB server on port 2159 (use dc_gdb.ps1 to start GDB as well).
.PARAMETER Log      Write the console output to this file. Default: logs\dc_<date>_<time>.txt in the devkit.
.PARAMETER NoLog    Do not save the console output.
.PARAMETER PcRoot   Directory whose DRIVE becomes /pc/ (default: the ELF's folder). dc-tool-ip on Windows
                    serves /pc/<path> as <current drive>:\<path>, so /pc/ = the root of that drive.

.EXAMPLE
  .\dc_run.ps1 ..\sample\hello_bba\hello_bba.elf
  .\dc_run.ps1 H:\PS2_EVEBustPlus\dc_port\eve_dc.elf -CdDir H:\PS2_EVEBustPlus\dc_port\cd_disc1 -Log run.log
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Elf,
    [string]$Ip,
    [string]$Iso,
    [string]$CdDir,
    [switch]$Fast,
    [switch]$Gdb,
    [string]$Log,
    [switch]$NoLog,
    [string]$PcRoot
)
. "$PSScriptRoot\_common.ps1"

$dctool = Assert-Tool 'DcToolIp'
$ip = Get-DcIp $Ip
$Elf = (Resolve-Path $Elf).Path

if ($CdDir) {
    if ($Iso) { throw 'Use either -Iso or -CdDir, not both.' }
    $mk = Assert-Tool 'MkIsoFs'
    $build = Join-Path $DevkitRoot 'build'
    New-Item -ItemType Directory -Force $build | Out-Null
    $Iso = Join-Path $build 'cdredir.iso'
    Write-Host "Building $Iso from $CdDir ..."
    Invoke-Native $mk @('-C', '0,0', '-V', 'CDREDIR', '-joliet', '-rock', '-l', '-o', $Iso, (Resolve-Path $CdDir).Path) -Quiet
}

$dcArgs = @('-t', $ip)
if ($Fast) { $dcArgs += '-f' }
if ($Gdb)  { $dcArgs += '-g' }
if ($Iso)  { $dcArgs += @('-i', (Resolve-Path $Iso).Path) }
$dcArgs += $DcToolExtraArgs
$dcArgs += @('-x', $Elf)

$root = if ($PcRoot) { (Resolve-Path $PcRoot).Path } else { Split-Path -Parent $Elf }
Write-Host "dc-tool-ip $($dcArgs -join ' ')"
Write-Host "/pc/ = $($root.Substring(0,3))   (e.g. this ELF's folder is /pc$(ConvertTo-PcPath (Split-Path -Parent $Elf)))"
Write-Host 'Ctrl+C stops dc-tool-ip (the Dreamcast keeps running; reset it or use dc_reset.ps1 once dcload is back).'
Write-Host ''

if (-not $NoLog -and -not $Log) {
    $logDir = Join-Path $DevkitRoot 'logs'
    New-Item -ItemType Directory -Force $logDir | Out-Null
    $Log = Join-Path $logDir ('dc_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
}
if ($Log -and -not $NoLog) {
    $Log = [System.IO.Path]::GetFullPath($Log)
    Write-Host "Console log: $Log"
}

Push-Location $root
try {
    if ($Log -and -not $NoLog) {
        # One writer for the whole run (opening the file per line slows a chatty program down,
        # because dc-tool-ip waits for the pipe). AutoFlush keeps the log complete after a crash.
        $writer = New-Object System.IO.StreamWriter($Log, $false, (New-Object System.Text.UTF8Encoding($false)))
        $writer.AutoFlush = $true
        try {
            $writer.WriteLine("# dc-tool-ip $($dcArgs -join ' ')  ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))")
            & $dctool @dcArgs | ForEach-Object { $_; $writer.WriteLine($_) }
        } finally { $writer.Dispose() }
    } else {
        & $dctool @dcArgs
    }
} finally { Pop-Location }
