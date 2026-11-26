#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Hardens Windows Defender Firewall against inbound traffic from the VMware NAT
    Control Node subnet (VMnet8), preventing a compromised haytham-ctl VM from reaching
    Windows host services (SMB, RDP, WinRM, RPC, NetBIOS, or arbitrary host ports).

.DESCRIPTION
    Auto-detects the VMware VMnet8 network adapter and its IPv4 subnet CIDR, then
    creates explicit inbound block rules scoped to that subnet (both on the VMnet8
    interface and across all profiles for high-risk Windows management ports).
    VMware's NAT service continues to forward outbound VM traffic to the LAN/Internet.

.PARAMETER AdapterName
    VMware NAT virtual adapter name. Defaults to "VMware Network Adapter VMnet8".

.PARAMETER Remove
    Removes all firewall rules created by this script (clean rollback).

.EXAMPLE
    .\scripts\hardening\harden-windows-firewall.ps1
    .\scripts\hardening\harden-windows-firewall.ps1 -Remove
#>

[CmdletBinding()]
param(
    [string]$AdapterName = "VMware Network Adapter VMnet8",
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RulePrefix = "Haytham-Block-VMnet8"

function Remove-HaythamRules {
    $existing = Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Remove-NetFirewallRule
        Write-Host "[OK] Removed existing firewall rules matching '$RulePrefix*'." -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] No existing '$RulePrefix*' firewall rules found." -ForegroundColor Cyan
    }
}

if ($Remove) {
    Remove-HaythamRules
    exit 0
}

function Get-SubnetCidr {
    param(
        [Parameter(Mandatory)] [string]$IPAddress,
        [Parameter(Mandatory)] [int]$PrefixLength
    )
    $ipBytes = ([System.Net.IPAddress]::Parse($IPAddress)).GetAddressBytes()
    $netBytes = New-Object byte[] 4
    $remaining = $PrefixLength
    for ($i = 0; $i -lt 4; $i++) {
        $bits = [Math]::Min([Math]::Max($remaining, 0), 8)
        $mask = if ($bits -eq 0) { 0 } else { 256 - [int][Math]::Pow(2, 8 - $bits) }
        $netBytes[$i] = [byte]($ipBytes[$i] -band $mask)
        $remaining -= 8
    }
    $netIp = ([System.Net.IPAddress]::new($netBytes)).IPAddressToString
    return "$netIp/$PrefixLength"
}

$ipConfig = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $ipConfig) {
    Write-Error "Adapter '$AdapterName' not found or has no IPv4 address. Verify VMware NAT (VMnet8) is enabled and retry."
    exit 1
}

$subnetCidr = Get-SubnetCidr -IPAddress $ipConfig.IPAddress -PrefixLength $ipConfig.PrefixLength
Write-Host "[INFO] Detected $AdapterName -> Host IP: $($ipConfig.IPAddress), Subnet: $subnetCidr" -ForegroundColor Cyan

# Idempotent reset of prior Haytham rules
Remove-HaythamRules

# 1. Catch-all inbound block on the VMnet8 interface (TCP & UDP)
New-NetFirewallRule `
    -DisplayName "$RulePrefix-AllInbound-Interface" `
    -Description "Block all inbound connections initiated from VMware VMnet8 control-node VM to Windows host." `
    -Direction Inbound `
    -Action Block `
    -InterfaceAlias $AdapterName `
    -RemoteAddress $subnetCidr `
    -Profile Any `
    -Enabled True | Out-Null

# 2. Explicit cross-interface block on high-risk Windows services from VMnet8 subnet
#    (defense-in-depth in case VMware NAT routes to the Windows LAN IP)
$HighRiskTcpPorts = @("135", "139", "445", "3389", "5985", "5986")
$HighRiskUdpPorts = @("137", "138")

New-NetFirewallRule `
    -DisplayName "$RulePrefix-HighRisk-TCP" `
    -Description "Block SMB, RDP, WinRM, RPC, and NetBIOS TCP from VMware VMnet8 subnet on all profiles." `
    -Direction Inbound `
    -Action Block `
    -Protocol TCP `
    -LocalPort $HighRiskTcpPorts `
    -RemoteAddress $subnetCidr `
    -Profile Any `
    -Enabled True | Out-Null

New-NetFirewallRule `
    -DisplayName "$RulePrefix-HighRisk-UDP" `
    -Description "Block NetBIOS UDP from VMware VMnet8 subnet on all profiles." `
    -Direction Inbound `
    -Action Block `
    -Protocol UDP `
    -LocalPort $HighRiskUdpPorts `
    -RemoteAddress $subnetCidr `
    -Profile Any `
    -Enabled True | Out-Null

# 3. Block ICMP echo requests from VMnet8 subnet to Windows host
New-NetFirewallRule `
    -DisplayName "$RulePrefix-ICMPv4" `
    -Description "Block ICMPv4 probes from VMware VMnet8 subnet to Windows host." `
    -Direction Inbound `
    -Action Block `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -RemoteAddress $subnetCidr `
    -Profile Any `
    -Enabled True | Out-Null

Write-Host ""
Write-Host "[OK] Applied Windows Firewall isolation rules for $AdapterName ($subnetCidr):" -ForegroundColor Green
Get-NetFirewallRule -DisplayName "$RulePrefix*" |
    Format-Table DisplayName, Direction, Action, Enabled, Profile -AutoSize

Write-Host "[REMINDER] Also verify in VMware Workstation/Player VM settings:" -ForegroundColor Yellow
Write-Host "  - Network Adapter   : NAT (VMnet8)"
Write-Host "  - Shared Folders    : Disabled"
Write-Host "  - Drag & Drop       : Disabled"
Write-Host "  - Copy & Paste      : Disabled (or Host->Guest only)"
Write-Host "  - USB Auto-Connect  : Disabled"
