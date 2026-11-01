<#
.SYNOPSIS
  Creates the folders the dcdev helpers write to (dcload cannot create folders):
    <HostDir>\screenshots  logs  assets  prof  vmu\a1 .. vmu\d2
  and prints the /pc/ path to pass to dcdev_init().

.EXAMPLE
  .\dc_prepare_host.ps1 C:\work\mygame\host
#>
param([Parameter(Mandatory = $true, Position = 0)][string]$HostDir)
. "$PSScriptRoot\_common.ps1"

$subs = @('screenshots', 'logs', 'assets', 'prof')
foreach ($p in 'a', 'b', 'c', 'd') { foreach ($u in 1, 2) { $subs += "vmu\$p$u" } }
foreach ($s in $subs) { New-Item -ItemType Directory -Force (Join-Path $HostDir $s) | Out-Null }

$pc = '/pc' + (ConvertTo-PcPath $HostDir)
Write-Host "Prepared $HostDir"
Write-Host "dcdev_init(`"$pc`");   // dc-tool-ip must run with its current directory on drive $($HostDir.Substring(0,2))"
