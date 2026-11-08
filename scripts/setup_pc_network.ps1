<#
.SYNOPSIS
  One-time PC setup for a Dreamcast cabled straight to this PC (no router). Run as administrator.

  1. gives the wired adapter the fixed address 192.168.10.1/24 (no gateway, so Wi-Fi keeps the
     internet connection)
  2. lets dc-tool-ip.exe receive from the Dreamcast subnet only (192.168.10.0/24) on every
     firewall profile (a cable without a router is an "unidentified network" = Public profile)

  The Dreamcast side is the dcload-ip disc built with -Ip 192.168.10.2.

  A second Dreamcast on its own adapter (e.g. a USB-LAN adapter): run this again for that adapter
  with another subnet. Each subnet gets its own firewall rule, so the first one stays.
    .\setup_pc_network.ps1 -Adapter "Ethernet 3" -PcIp 192.168.11.1 -DcIp 192.168.11.2
  and build its dcload-ip disc with make_dcload_disc.ps1 -Ip 192.168.11.2.
  Two adapters must not share a subnet (Windows would send through only one of them): this script
  stops if another adapter already has an address in the subnet.

.PARAMETER Adapter  Adapter name (Get-NetAdapter). Default: the wired adapter whose link is up,
                    so power on the Dreamcast with dcload-ip running first.
.PARAMETER PcIp     This PC's address on that adapter (default 192.168.10.1).
.PARAMETER DcIp     Dreamcast address to ping at the end (default: $DcIp in config\bba.config.ps1
                    when it is in the subnet).
.PARAMETER Undo     Put the adapter back to DHCP and remove the firewall rule of its subnet
                    (rules of other adapters' subnets stay).

.EXAMPLE
  .\setup_pc_network.ps1
  .\setup_pc_network.ps1 -Adapter "Ethernet 2"
  .\setup_pc_network.ps1 -Adapter "Ethernet 3" -PcIp 192.168.11.1 -DcIp 192.168.11.2
  .\setup_pc_network.ps1 -Undo
  .\setup_pc_network.ps1 -Adapter "Ethernet 3" -Undo
#>
param([string]$Adapter, [string]$PcIp = '192.168.10.1', [ValidateRange(8, 30)] [int]$Prefix = 24,
      [string]$DcIp, [switch]$Undo)

$ruleBase = 'Dreamcast dc-tool-ip (BBA)'     # rules made before 2026-11-08 have exactly this name

function ConvertTo-IpNumber([string]$ip) {
    $b = ([Net.IPAddress]::Parse($ip)).GetAddressBytes()
    [Array]::Reverse($b)
    return [int64][BitConverter]::ToUInt32($b, 0)
}
function Get-Mask([int]$prefix) { return [int64]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefix)) }
# "192.168.11.0/24" for 192.168.11.1 /24
function Get-Subnet([string]$ip, [int]$prefix) {
    $n = (ConvertTo-IpNumber $ip) -band (Get-Mask $prefix)
    $b = [BitConverter]::GetBytes([uint32]$n)
    [Array]::Reverse($b)
    return "$(New-Object Net.IPAddress (, $b))/$prefix"
}
function Test-InSubnet([string]$ip, [string]$subnet) {
    $net, $p = $subnet -split '/'
    return ((ConvertTo-IpNumber $ip) -band (Get-Mask ([int]$p))) -eq (ConvertTo-IpNumber $net)
}
function Get-RuleName([string]$subnet) { return "$ruleBase $subnet" }
# Windows may show a rule's address as 192.168.10.0/24 or 192.168.10.0/255.255.255.0
function Get-SubnetForms([string]$subnet) {
    $net, $p = $subnet -split '/'
    $b = [BitConverter]::GetBytes([uint32](Get-Mask ([int]$p)))
    [Array]::Reverse($b)
    return @($subnet, "$net/$(New-Object Net.IPAddress (, $b))")
}
# addresses of other adapters that overlap $subnet (link-local 169.254.x.x does not count).
# Get-NetIPAddress also lists a fixed address of an unplugged adapter, so a Dreamcast that is off still counts.
function Get-SubnetUsers([string]$subnet, [int]$exceptIndex) {
    $ip = ($subnet -split '/')[0]
    return @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.InterfaceIndex -ne $exceptIndex -and $_.IPAddress -notlike '169.254.*' -and
                            ((Test-InSubnet $_.IPAddress $subnet) -or (Test-InSubnet $ip (Get-Subnet $_.IPAddress $_.PrefixLength))) })
}

if ($MyInvocation.InvocationName -eq '.') { return }   # dot-sourced by the tests: functions only

. "$PSScriptRoot\_common.ps1"

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an administrator PowerShell.'
}

# the rule for this subnet, and an old rule (one fixed name) when it is for the same subnet
function Remove-DcRule([string]$subnet) {
    Remove-NetFirewallRule -DisplayName (Get-RuleName $subnet) -ErrorAction SilentlyContinue
    $old = Get-NetFirewallRule -DisplayName $ruleBase -ErrorAction SilentlyContinue
    if (-not $old) { return }
    $forms = Get-SubnetForms $subnet
    if (@($old | Get-NetFirewallAddressFilter | Where-Object { @($_.RemoteAddress | Where-Object { $forms -contains $_ }).Count }).Count) {
        Remove-NetFirewallRule -DisplayName $ruleBase
    }
}

$wired = Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq '802.3' }
if ($Adapter) { $nic = Get-NetAdapter -Name $Adapter }
else {
    $up = @($wired | Where-Object Status -eq 'Up')
    if ($up.Count -ne 1) {
        $wired | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize | Out-Host
        throw "Found $($up.Count) wired adapters with link. Pass -Adapter <name> (with two Dreamcasts, run this once per adapter)."
    }
    $nic = $up[0]
}
Write-Host "Adapter: $($nic.Name) ($($nic.InterfaceDescription))"

if ($Undo) {
    $manual = @(Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object PrefixOrigin -eq 'Manual')
    # no fixed address (already undone): fall back to -PcIp/-Prefix, the default 192.168.10.0/24 included
    $subnets = if ($manual.Count) { @($manual | ForEach-Object { Get-Subnet $_.IPAddress $_.PrefixLength }) }
               else { @(Get-Subnet $PcIp $Prefix) }
    foreach ($s in $subnets | Select-Object -Unique) {
        # the rule also lets in the Dreamcast of any other adapter in that subnet: keep it then
        $users = Get-SubnetUsers $s $nic.ifIndex
        if ($users.Count) { Write-Host "Firewall rule for $s kept: $(($users | ForEach-Object { "$($_.InterfaceAlias) $($_.IPAddress)" }) -join ', ') uses it." -ForegroundColor Yellow }
        else { Remove-DcRule $s; Write-Host "Firewall rule for $s removed." }
    }
    $manual | Remove-NetIPAddress -Confirm:$false
    Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Enabled
    Write-Host 'Back to DHCP.'
    return
}

$subnet = Get-Subnet $PcIp $Prefix

# two adapters in one subnet: Windows picks one route and the other Dreamcast gets nothing
$hostPart = (ConvertTo-IpNumber $PcIp) -band -bnot (Get-Mask $Prefix) -band 0xFFFFFFFFL
if ($hostPart -eq 0 -or $hostPart -eq ([math]::Pow(2, 32 - $Prefix) - 1)) { throw "-PcIp $PcIp is the network or broadcast address of $subnet (use e.g. $(($subnet -split '/')[0] -replace '\.0$', '.1'))." }
if ($DcIp -and -not (Test-InSubnet $DcIp $subnet)) { throw "-DcIp $DcIp is not in $subnet (the subnet of -PcIp $PcIp)." }
if ($DcIp -eq $PcIp) { throw "-DcIp and -PcIp are the same address ($PcIp)." }
$clash = Get-SubnetUsers $subnet $nic.ifIndex
if ($clash.Count) {
    $clash | Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize | Out-Host
    throw "$subnet is already used by another adapter (above). Give this adapter another subnet, e.g. -PcIp 192.168.11.1."
}

# 1. fixed IP
Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $PcIp -PrefixLength $Prefix | Out-Null
Write-Host "IP: $PcIp/$Prefix (no gateway)"

# 2. firewall: dc-tool-ip only, this Dreamcast subnet only (one rule per subnet)
$exe = Assert-Tool 'DcToolIp'
Remove-DcRule $subnet
New-NetFirewallRule -DisplayName (Get-RuleName $subnet) -Direction Inbound -Action Allow -Program $exe `
    -RemoteAddress $subnet -Profile Any | Out-Null
Write-Host "Firewall: allow $exe from $subnet"
$others = @(Get-NetFirewallRule -DisplayName "$ruleBase*" -ErrorAction SilentlyContinue |
            Where-Object DisplayName -ne (Get-RuleName $subnet))
if ($others.Count) { Write-Host "Other Dreamcast rules kept: $(($others.DisplayName) -join ', ')" }

Start-Sleep 2
if (-not $DcIp) {
    $cfg = try { Get-DcIp '' } catch { $null }
    if ($cfg -and (Test-InSubnet $cfg $subnet)) { $DcIp = $cfg }
}
if (-not $DcIp) { Write-Host "Ready. Pass -DcIp to check the Dreamcast on this adapter (its dcload-ip address in $subnet)." -ForegroundColor Yellow }
elseif (Test-Connection -ComputerName $DcIp -Count 2 -Quiet) { Write-Host "Dreamcast $DcIp answers ping. Ready." -ForegroundColor Green }
else { Write-Host "No ping reply from $DcIp yet (is dcload-ip on screen?)." -ForegroundColor Yellow }
