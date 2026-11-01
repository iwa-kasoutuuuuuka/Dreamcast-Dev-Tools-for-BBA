<#
.SYNOPSIS  Builds hello_bba.elf with the DreamSDK toolchain and prepares its host\ folder.
.EXAMPLE   .\build.ps1          # release build
           .\build.ps1 -Debug   # -g -O0 + GDB stub (for dc_gdb.ps1 / VS Code)
#>
param([switch]$Debug)
. "$PSScriptRoot\..\..\scripts\_common.ps1"

# host\ = folder the program reads/writes through /pc/ (screenshots, logs, assets, ...)
$hostDir = Join-Path $PSScriptRoot 'host'
& "$PSScriptRoot\..\..\scripts\dc_prepare_host.ps1" $hostDir | Out-Null

$rel = ConvertTo-PcPath $hostDir
# Stop MSYS2 from rewriting "/pc/..." into "C:/DreamSDK/pc/..." when kos-cc (a Windows exe) is called.
$env:MSYS2_ARG_CONV_EXCL = '-DHOST_DIR_RAW='
$dbg = if ($Debug) { 'DEBUG=1' } else { '' }
Invoke-DreamSdkBash "make clean >/dev/null; make HOST_DIR_REL='$rel' $dbg" $PSScriptRoot
Write-Host "Built $(Join-Path $PSScriptRoot 'hello_bba.elf')  (host folder /pc$rel)"
