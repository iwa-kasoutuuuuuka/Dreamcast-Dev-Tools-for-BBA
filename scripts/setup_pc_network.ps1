<#
.SYNOPSIS
  One-time PC setup for a Dreamcast cabled straight to this PC (no router). Run as administrator.

  1. gives the wired adapter the fixed address 192.168.10.1/24 (no gateway, so Wi-Fi keeps the
     internet connection)
  2. lets dc-tool-ip.exe receive from the Dreamcast subnet only (192.168.10.0/24) on every
     firewall profile (a cable without a router is an "unidentified network" = Public profile)

  The Dreamcast side is the dcload-ip disc built with -Ip 192.168.10.2.

.PARAMETER Adapter  Adapter name (Get-NetAdapter). Default: the wired adapter whose link is up,
                    so power on the Dreamcast with dcload-ip running first.
.PARAMETER Undo     Put the adapter back to DHCP and remove the firewall rule.

.EXAMPLE
  .\setup_pc_network.ps1
  .\setup_pc_network.ps1 -Adapter "Ethernet 2"
  .\setup_pc_network.ps1 -Undo
#>
param([string]$Adapter, [string]$PcIp = '192.168.10.1', [int]$Prefix = 24, [switch]$Undo)
. "$PSScriptRoot\_common.ps1"

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an administrator PowerShell.'
}

$wired = Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq '802.3' }
if ($Adapter) { $nic = Get-NetAdapter -Name $Adapter }
else {
    $up = @($wired | Where-Object Status -eq 'Up')
    if ($up.Count -ne 1) {
        $wired | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize | Out-Host
        throw "Found $($up.Count) wired adapters with link. Turn on the Dreamcast (dcload-ip screen) or pass -Adapter <name>."
    }
    $nic = $up[0]
}
$ruleName = 'Dreamcast dc-tool-ip (BBA)'
Write-Host "Adapter: $($nic.Name) ($($nic.InterfaceDescription))"

if ($Undo) {
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object PrefixOrigin -eq 'Manual' | Remove-NetIPAddress -Confirm:$false
    Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Enabled
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    Write-Host 'Back to DHCP, firewall rule removed.'
    return
}

# 1. fixed IP
Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $PcIp -PrefixLength $Prefix | Out-Null
Write-Host "IP: $PcIp/$Prefix (no gateway)"

# 2. firewall: dc-tool-ip only, Dreamcast subnet only
$exe = Assert-Tool 'DcToolIp'
Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
$subnet = ($PcIp -replace '\.\d+$', '.0') + "/$Prefix"
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Program $exe `
    -RemoteAddress $subnet -Profile Any | Out-Null
Write-Host "Firewall: allow $exe from $subnet"

Start-Sleep 2
$dc = Get-DcIp ''
if (Test-Connection -ComputerName $dc -Count 2 -Quiet) { Write-Host "Dreamcast $dc answers ping. Ready." -ForegroundColor Green }
else { Write-Host "No ping reply from $dc yet (is dcload-ip on screen?)." -ForegroundColor Yellow }
