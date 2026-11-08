<#
  Address math of setup_pc_network.ps1 (one firewall rule per Dreamcast subnet).
  Only loads the functions: changes no network or firewall setting, needs no administrator.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\setup_pc_network.ps1')

$script:ok = 0; $script:bad = 0
function T([string]$name, $got, $want) {
    if ("$got" -eq "$want") { $script:ok++ } else { $script:bad++; Write-Host "FAIL $name : got [$got] want [$want]" -ForegroundColor Red }
}
T 'subnet /24'      (Get-Subnet '192.168.10.1' 24) '192.168.10.0/24'
T 'second adapter'  (Get-Subnet '192.168.11.1' 24) '192.168.11.0/24'
T 'subnet /16'      (Get-Subnet '10.1.200.7' 16) '10.1.0.0/16'
T 'subnet /25'      (Get-Subnet '192.168.10.200' 25) '192.168.10.128/25'
T 'high addresses'  (Get-Subnet '255.255.255.254' 30) '255.255.255.252/30'
T 'in subnet'       (Test-InSubnet '192.168.10.2' '192.168.10.0/24') $true
T 'other subnet'    (Test-InSubnet '192.168.11.2' '192.168.10.0/24') $false
T 'in /25'          (Test-InSubnet '192.168.10.130' '192.168.10.128/25') $true
T 'outside /25'     (Test-InSubnet '192.168.10.2' '192.168.10.128/25') $false
T 'rule per subnet' (Get-RuleName '192.168.11.0/24') 'Dreamcast dc-tool-ip (BBA) 192.168.11.0/24'
# an old rule shows its address as 192.168.10.0/255.255.255.0 in Get-NetFirewallAddressFilter
T 'address forms'   ((Get-SubnetForms '192.168.10.0/24') -join ',') '192.168.10.0/24,192.168.10.0/255.255.255.0'
T 'other forms'     ((Get-SubnetForms '192.168.11.0/24') -contains '192.168.10.0/255.255.255.0') $false
Write-Host "network: $script:ok passed, $script:bad failed"
if ($script:bad) { throw 'network tests failed' }
