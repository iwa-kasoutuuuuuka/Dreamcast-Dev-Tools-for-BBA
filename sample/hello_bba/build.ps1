<#
.SYNOPSIS  Builds hello_bba.elf with the DreamSDK toolchain.
.EXAMPLE   .\build.ps1          # release build
           .\build.ps1 -Debug   # -g -O0 + GDB stub (for dc_gdb.ps1)
#>
param([switch]$Debug)
. "$PSScriptRoot\..\..\scripts\_common.ps1"

# /pc/ path of this folder (dc-tool-ip serves the root of its current drive as /pc/)
$rel = ConvertTo-PcPath $PSScriptRoot
# Stop MSYS2 from rewriting "/pc/..." into "C:/DreamSDK/pc/..." when kos-cc (a Windows exe) is called.
$env:MSYS2_ARG_CONV_EXCL = '-DHOST_DIR_RAW='
$dbg = if ($Debug) { 'DEBUG=1' } else { '' }
Invoke-DreamSdkBash "make clean >/dev/null; make HOST_DIR_REL='$rel' $dbg" $PSScriptRoot
Write-Host "Built $(Join-Path $PSScriptRoot 'hello_bba.elf')  (files under /pc$rel)"
