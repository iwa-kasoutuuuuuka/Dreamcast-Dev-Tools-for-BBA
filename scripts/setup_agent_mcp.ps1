<#
.SYNOPSIS
  Registers the VMU Workbench MCP server (dc-vmu) for Antigravity.

.DESCRIPTION
  Antigravity reads MCP servers from the user settings file ~/.gemini/antigravity/mcp_config.json.
  This adds (or updates) only the "dc-vmu" entry, with absolute paths to node and to
  third_party\vmu-workbench\mcp\server.js in this repository, and keeps every other entry.
  The previous file is saved as mcp_config.json.bak_<date>. Restart Antigravity afterwards.
  -Remove takes the entry out again. -WhatIf only prints the new file.

  Claude Code needs nothing: .mcp.json in this repository already lists dc-vmu.
  Skills, rules and workflows are in .agent\ (Antigravity) and .claude\skills\ (Claude Code).
#>
param(
    [switch]$Remove,
    [switch]$WhatIf,
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.gemini\antigravity\mcp_config.json')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = (Join-Path $root 'third_party\vmu-workbench\mcp\server.js') -replace '\\', '/'
if (-not $Remove -and -not (Test-Path $server)) { throw "$server is missing: run scripts\sync_vmu_workbench.ps1 first" }
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $Remove -and -not $node) { throw 'Node.js (node) was not found: https://nodejs.org/' }

$cfg = if (Test-Path $ConfigPath) { Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $cfg) { $cfg = [pscustomobject]@{} }
if (-not ($cfg.PSObject.Properties.Name -contains 'mcpServers')) { $cfg | Add-Member mcpServers ([pscustomobject]@{}) }
$servers = $cfg.mcpServers
if ($servers.PSObject.Properties.Name -contains 'dc-vmu') { $servers.PSObject.Properties.Remove('dc-vmu') }
if (-not $Remove) {
    $servers | Add-Member 'dc-vmu' ([pscustomobject]@{ command = ($node -replace '\\', '/'); args = @($server) })
}
$json = $cfg | ConvertTo-Json -Depth 10
if ($WhatIf) { Write-Host "[mcp] would write $ConfigPath :"; $json; return }

New-Item -ItemType Directory -Force (Split-Path $ConfigPath -Parent) | Out-Null
if (Test-Path $ConfigPath) {
    $bak = "$ConfigPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -LiteralPath $ConfigPath -Destination $bak
    Write-Host "[mcp] previous settings -> $bak"
}
[System.IO.File]::WriteAllText($ConfigPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[mcp] $(if ($Remove) { 'removed' } else { 'registered' }) dc-vmu in $ConfigPath. Restart Antigravity to use it." -ForegroundColor Green
