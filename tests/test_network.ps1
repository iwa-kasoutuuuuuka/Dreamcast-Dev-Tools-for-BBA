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

# Get-SubnetUsers with a stand-in Get-NetIPAddress (a function wins over the cmdlet): Dreamcast 1 on a USB-LAN
# adapter that is unplugged (its fixed address is still listed), on-board LAN with no address, Wi-Fi at home
function Get-NetIPAddress {
    @([pscustomobject]@{ InterfaceIndex = 10; InterfaceAlias = 'usb';      IPAddress = '192.168.10.1';    PrefixLength = 24 },
      [pscustomobject]@{ InterfaceIndex = 5;  InterfaceAlias = 'onboard';  IPAddress = '169.254.218.100'; PrefixLength = 16 },
      [pscustomobject]@{ InterfaceIndex = 11; InterfaceAlias = 'wifi';     IPAddress = '192.168.128.129'; PrefixLength = 24 },
      [pscustomobject]@{ InterfaceIndex = 1;  InterfaceAlias = 'loopback'; IPAddress = '127.0.0.1';       PrefixLength = 8 })
}
T 'second subnet free'      (Get-SubnetUsers '192.168.11.0/24' 5).Count 0
T 'first subnet is taken'   ((Get-SubnetUsers '192.168.10.0/24' 5) | ForEach-Object InterfaceAlias) 'usb'
T 'own adapter not a clash' (Get-SubnetUsers '192.168.10.0/24' 10).Count 0
T 'wider net covers it'     ((Get-SubnetUsers '192.168.0.0/16' 5) | ForEach-Object InterfaceAlias) 'usb wifi'
T 'link-local ignored'      (Get-SubnetUsers '169.254.0.0/16' 10).Count 0
Remove-Item function:Get-NetIPAddress
Write-Host "network: $script:ok passed, $script:bad failed"
if ($script:bad) { throw 'network tests failed' }
