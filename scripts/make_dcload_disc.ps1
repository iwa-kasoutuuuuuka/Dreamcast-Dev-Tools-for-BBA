<#
.SYNOPSIS
  Builds a bootable dcload-ip CD image (CDI) for the Dreamcast Broadband Adapter.

.DESCRIPTION
  Default: uses the dcload-ip binary that ships with DreamSDK (DHCP mode, IP 0.0.0.0).
  -Ip 192.168.1.200 rebuilds dcload-ip with a fixed IP in build\dcload-ip (DreamSDK
  itself is not touched). Use a fixed IP when there is no DHCP server, e.g. when the
  Dreamcast is cabled straight to the PC.

  Output: out\dcload-ip.cdi (Data/Data, burn with DiscJuggler/ImgBurn or put on an ODE)
          out\dcload-ip_AD.cdi with -AudioData (Audio/Data layout, accepted by more drives)

.EXAMPLE
  .\make_dcload_disc.ps1
  .\make_dcload_disc.ps1 -Ip 192.168.10.2 -AudioData
#>
param(
    [string]$Ip,
    [switch]$AudioData
)
. "$PSScriptRoot\_common.ps1"

$build = Join-Path $DevkitRoot 'build'
$out   = Join-Path $DevkitRoot 'out'
New-Item -ItemType Directory -Force $build, $out | Out-Null

foreach ($t in 'Scramble', 'MakeIp', 'MkIsoFs', 'Cdi4dc') { Assert-Tool $t | Out-Null }

# 1. Get an unscrambled dcload-ip 1st_read.bin
if ($Ip) {
    if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Not an IPv4 address: $Ip" }
    $src = Join-Path $build 'dcload-ip'
    Write-Host "[1/4] Rebuilding dcload-ip with fixed IP $Ip in $src"
    if (Test-Path $src) { Remove-Item -Recurse -Force $src }
    Copy-Item -Recurse $DcloadSrc $src
    $cfg = Join-Path $src 'Makefile.cfg'
    (Get-Content $cfg) -replace '^DREAMCAST_IP\s*=.*$', "DREAMCAST_IP`t= $Ip" | Set-Content -Encoding ascii $cfg
    Invoke-DreamSdkBash 'make -C target-src clean >/dev/null 2>&1; make -C target-src' $src
    $bin = Join-Path $src 'target-src\1st_read\1st_read.bin'
} else {
    Write-Host '[1/4] Using the prebuilt dcload-ip from DreamSDK (DHCP mode)'
    $bin = Join-Path $DcloadSrc 'target-src\1st_read\1st_read.bin'
}
if (-not (Test-Path $bin)) { throw "dcload-ip binary not found: $bin" }

# 2. Disc folder: scrambled 1ST_READ.BIN
$disc = Join-Path $build 'disc'
if (Test-Path $disc) { Remove-Item -Recurse -Force $disc }
New-Item -ItemType Directory -Force $disc | Out-Null
Write-Host '[2/4] Scrambling 1ST_READ.BIN'
Invoke-Native $Tools.Scramble @($bin, (Join-Path $disc '1ST_READ.BIN'))

# 3. IP.BIN (boot sector) from dcload-ip's own ip.txt
Write-Host '[3/4] Building IP.BIN'
$ipBin = Join-Path $build 'IP.BIN'
Invoke-Native $Tools.MakeIp @('-f', (Join-Path $DcloadSrc 'make-cd\ip.txt'), $ipBin) -Quiet

# 4. ISO -> CDI
Write-Host '[4/4] Building CDI'
function New-Cdi([string]$msinfo, [string]$name, [string[]]$cdiArgs) {
    $iso = Join-Path $build "$name.iso"
    Invoke-Native $Tools.MkIsoFs @('-C', $msinfo, '-V', 'DCLOAD_IP', '-G', $ipBin, '-joliet', '-rock', '-l', '-o', $iso, $disc) -Quiet
    $cdi = Join-Path $out "$name.cdi"
    Invoke-Native $Tools.Cdi4dc (@($iso, $cdi) + $cdiArgs) -Quiet
    Remove-Item $iso
    Write-Host "    -> $cdi"
}
New-Cdi '0,0' 'dcload-ip' @('-d')
if ($AudioData) { New-Cdi '0,11702' 'dcload-ip_AD' @() }

$mode = if ($Ip) { "fixed IP $Ip" } else { 'DHCP' }
Write-Host "Done. dcload-ip ($mode). Burn the CDI or copy it to your ODE, then boot the Dreamcast with the BBA attached."
