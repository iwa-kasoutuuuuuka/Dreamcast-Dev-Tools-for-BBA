<#
.SYNOPSIS
  Registers the VMU Workbench MCP server (dc-vmu) for Antigravity.

.DESCRIPTION
  Antigravity reads MCP servers from ~/.gemini/config/mcp_config.json; the older Antigravity IDE
  reads ~/.gemini/antigravity-ide/mcp_config.json. This adds (or updates) only the "dc-vmu" entry,
  with absolute paths to node and to third_party\vmu-workbench\mcp\server.js in this repository,
  in the first file and also in the second when that app is installed. Every other entry is kept
  as it is (the merge is done by node, so values such as an empty "env": {} survive).
  Each changed file is first copied to mcp_config.json.bak_<date>. Restart Antigravity afterwards.
  -Remove takes the entry out again. -WhatIf only prints what would be written.

  Claude Code needs nothing: .mcp.json in this repository already lists dc-vmu.
  Skills, rules and workflows are in .agent\ (Antigravity) and .claude\skills\ (Claude Code).
#>
param(
    [switch]$Remove,
    [switch]$WhatIf,
    [string[]]$ConfigPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = (Join-Path $root 'third_party\vmu-workbench\mcp\server.js') -replace '\\', '/'
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'Node.js (node) was not found: https://nodejs.org/' }
if (-not $Remove -and -not (Test-Path $server)) { throw "$server is missing: run scripts\sync_vmu_workbench.ps1 first" }

$ConfigPath = @($ConfigPath | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # "a,b" arrives as one string under -File
if (-not $ConfigPath) {
    $gem = Join-Path $env:USERPROFILE '.gemini'
    $ConfigPath = @(Join-Path $gem 'config\mcp_config.json')                       # Antigravity
    if (Test-Path (Join-Path $gem 'antigravity-ide')) {                             # Antigravity IDE (older app)
        $ConfigPath += Join-Path $gem 'antigravity-ide\mcp_config.json'
    }
}

# node does the JSON work: read (BOM tolerated), set or delete mcpServers["dc-vmu"], print the result
$js = @'
const fs = require('fs');
const [file, mode, cmd, srv] = process.argv.slice(1);
let cfg = {};
if (fs.existsSync(file)) {
  const t = fs.readFileSync(file, 'utf8').replace(/^﻿/, '').trim();
  if (t) cfg = JSON.parse(t);
}
if (typeof cfg.mcpServers !== 'object' || cfg.mcpServers === null) cfg.mcpServers = {};
if (mode === 'remove') delete cfg.mcpServers['dc-vmu'];
else cfg.mcpServers['dc-vmu'] = { command: cmd, args: [srv] };
process.stdout.write(JSON.stringify(cfg, null, 2) + '\n');
'@
$mode = if ($Remove) { 'remove' } else { 'add' }
foreach ($cfgFile in $ConfigPath) {
    $json = (& $node -e $js $cfgFile $mode ($node -replace '\\', '/') $server) -join "`n"
    if ($LASTEXITCODE) { throw "could not read $cfgFile as JSON (left unchanged)" }
    if ($WhatIf) { Write-Host "[mcp] would write $cfgFile :"; $json; continue }
    New-Item -ItemType Directory -Force (Split-Path $cfgFile -Parent) | Out-Null
    if (Test-Path $cfgFile) {
        $bak = "$cfgFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -LiteralPath $cfgFile -Destination $bak
        Write-Host "[mcp] previous settings -> $bak"
    }
    [System.IO.File]::WriteAllText($cfgFile, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[mcp] $(if ($Remove) { 'removed dc-vmu from' } else { 'registered dc-vmu in' }) $cfgFile" -ForegroundColor Green
}
if (-not $WhatIf) { Write-Host '[mcp] Restart Antigravity to use it.' -ForegroundColor Green }
