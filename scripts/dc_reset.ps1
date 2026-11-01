<#
.SYNOPSIS
  Checks the Dreamcast is reachable, and optionally resets it.

  -Reset only works while dcload-ip is in control (its menu is on screen, or the
  program returned to dcload via exit()). A crashed program needs the power button.

.EXAMPLE
  .\dc_reset.ps1          # ping only
  .\dc_reset.ps1 -Reset   # send dc-tool-ip -r
#>
param([string]$Ip, [switch]$Reset)
. "$PSScriptRoot\_common.ps1"

$ip = Get-DcIp $Ip
$ok = Test-Connection -ComputerName $ip -Count 2 -Quiet
if ($ok) { Write-Host "Dreamcast $ip answers ping (dcload-ip or a networked KOS program is running)." }
else     { Write-Host "No ping reply from $ip. Check the cable, the IP on the dcload-ip screen, and that the PC is on the same subnet." }

if ($Reset) {
    $dctool = Assert-Tool 'DcToolIp'
    & $dctool -t $ip -r
}
