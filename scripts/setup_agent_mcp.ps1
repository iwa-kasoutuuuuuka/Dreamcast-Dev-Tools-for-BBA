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

  -Check changes nothing. For each config file it reports whether the file exists, whether it has
  a dc-vmu entry and whether that entry's command and server.js exist; whether Antigravity has
  cached the server's tools in ~/.gemini/antigravity/mcp/dc-vmu\ (it has loaded it at least once;
  the cache can be stale); then it starts the server once with that command, sends MCP initialize
  and tools/list over stdio, reports the tool count and stops the server.
  Exit code 0 when everything is OK, 1 otherwise.

  Claude Code needs nothing: .mcp.json in this repository already lists dc-vmu.
  Skills and rules are in .agent\ (Antigravity) and .claude\skills\ (Claude Code).
#>
param(
    [switch]$Remove,
    [switch]$WhatIf,
    [switch]$Check,
    [string[]]$ConfigPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = (Join-Path $root 'third_party\vmu-workbench\mcp\server.js') -replace '\\', '/'
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $Check) {
    if (-not $node) { throw 'Node.js (node) was not found: https://nodejs.org/' }
    if (-not $Remove -and -not (Test-Path $server)) { throw "$server is missing: run scripts\sync_vmu_workbench.ps1 first" }
}

$ConfigPath = @($ConfigPath | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # "a,b" arrives as one string under -File
$defaultPaths = -not $ConfigPath
if (-not $ConfigPath) {
    $gem = Join-Path $env:USERPROFILE '.gemini'
    $ConfigPath = @(Join-Path $gem 'config\mcp_config.json')                       # Antigravity
    if (Test-Path (Join-Path $gem 'antigravity-ide')) {                             # Antigravity IDE (older app)
        $ConfigPath += Join-Path $gem 'antigravity-ide\mcp_config.json'
    }
}

if ($Check) {
    # read-only: nothing below writes a file
    $script:bad = 0
    function Say([string]$tag, [string]$msg) {
        $color = @{ OK = 'Green'; NG = 'Red'; WARN = 'Yellow'; INFO = 'Gray' }[$tag]
        Write-Host ('[check] {0,-4} {1}' -f $tag, $msg) -ForegroundColor $color
        if ($tag -eq 'NG') { $script:bad++ }
    }
    if (-not $node) { Say NG 'Node.js (node) was not found: https://nodejs.org/'; exit 1 }
    Say INFO "node: $node"
    if (Test-Path $server) { Say OK "this repository's server: $server" }
    else { Say NG "$server is missing: run scripts\sync_vmu_workbench.ps1 first" }
    if ($defaultPaths -and $ConfigPath.Count -eq 1) { Say INFO 'Antigravity IDE (~/.gemini/antigravity-ide) is not installed: skipped' }

    # prints "missing", "badjson <msg>", "noentry" or "entry <json>"
    $readJs = @'
const fs = require('fs');
const file = process.argv[1];
if (!fs.existsSync(file)) { console.log('missing'); process.exit(0); }
let cfg;
try { const t = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').trim(); cfg = t ? JSON.parse(t) : {}; }
catch (x) { console.log('badjson ' + x.message); process.exit(0); }
const e = cfg && cfg.mcpServers && cfg.mcpServers['dc-vmu'];
console.log(e ? 'entry ' + JSON.stringify(e) : 'noentry');
'@
    # starts <cmd> <args...>, MCP initialize + notifications/initialized + tools/list over stdio,
    # prints "OK <tool count> <server name> <version>" or "ERR <reason>", then kills the server
    $probeJs = @'
const { spawn, spawnSync } = require('child_process');
const [ms, cmd, ...args] = process.argv.slice(1);
let child, out = '', err = '', info = {}, done = false;
const tail = () => { const l = err.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
                    return l.find((s) => /Error/.test(s)) || l.slice(-2).join(' | '); };
const finish = (line, code) => {
  if (done) return; done = true;
  console.log(line);
  try {
    if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
    else child.kill();
  } catch (x) {}
  process.exit(code);
};
const send = (o) => child.stdin.write(JSON.stringify(o) + '\n');
try {
  child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'], shell: /\.(cmd|bat)$/i.test(cmd),
                             cwd: require('os').homedir(), windowsHide: true });
} catch (x) { console.log('ERR could not start: ' + x.message); process.exit(1); }
child.on('error', (x) => finish('ERR could not start: ' + x.message, 1));
child.on('exit', (c) => finish('ERR server exited (code ' + c + ') ' + tail(), 1));
child.stdin.on('error', () => {});
child.stderr.on('data', (d) => { err += d; });
child.stdout.on('data', (d) => {
  out += d;
  let i;
  while ((i = out.indexOf('\n')) >= 0) {
    const line = out.slice(0, i).trim(); out = out.slice(i + 1);
    let m;
    try { m = JSON.parse(line); } catch (x) { continue; }
    if (m.id === 1) {
      if (m.error) return finish('ERR initialize: ' + JSON.stringify(m.error), 1);
      info = (m.result && m.result.serverInfo) || {};
      send({ jsonrpc: '2.0', method: 'notifications/initialized' });
      send({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} });
    } else if (m.id === 2) {
      if (m.error) return finish('ERR tools/list: ' + JSON.stringify(m.error), 1);
      const tools = (m.result && m.result.tools) || [];
      return finish('OK ' + tools.length + ' ' + (info.name || '?') + ' ' + (info.version || '?') +
                    (m.result && m.result.nextCursor ? ' (more pages not counted)' : ''), 0);
    }
  }
});
setTimeout(() => finish('ERR no answer within ' + ms + ' ms ' + tail(), 1), Number(ms));
send({ jsonrpc: '2.0', id: 1, method: 'initialize',
       params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'setup_agent_mcp-check', version: '1' } } });
'@

    $probed = @{}       # "cmd|args" -> tool count (or $null when it failed)
    foreach ($cfgFile in $ConfigPath) {
        Write-Host "[check] --- $cfgFile"
        $r = (& $node -e $readJs $cfgFile) -join "`n"
        if ($LASTEXITCODE) { Say NG "node could not read it ($r)"; continue }
        if ($r -eq 'missing') { Say NG 'file does not exist (run scripts\setup_agent_mcp.ps1)'; continue }
        if ($r -like 'badjson *') { Say NG "not valid JSON: $($r.Substring(8))"; continue }
        if ($r -eq 'noentry') { Say NG 'no "dc-vmu" entry in mcpServers (run scripts\setup_agent_mcp.ps1)'; continue }
        $entry = $r.Substring(6) | ConvertFrom-Json
        Say OK 'has a "dc-vmu" entry'
        if ($entry.disabled -eq $true) { Say WARN 'the entry has "disabled": true' }

        $cmd = [string]$entry.command
        $cmdArgs = @($entry.args | ForEach-Object { [string]$_ })
        $cmdOk = $false
        if (-not $cmd) { Say NG 'the entry has no "command"' }
        elseif (Test-Path -LiteralPath $cmd -PathType Leaf) { Say OK "command exists: $cmd"; $cmdOk = $true }
        elseif ($found = Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue) {
            Say OK "command found on PATH: $cmd -> $(@($found)[0].Source)"; $cmdOk = $true
        } else { Say NG "command not found: $cmd" }

        $srvArg = $cmdArgs | Where-Object { $_ -match 'server\.js$' } | Select-Object -First 1
        if (-not $srvArg) { Say NG "no server.js in args: $($cmdArgs -join ' ')" }
        elseif (-not (Test-Path -LiteralPath $srvArg -PathType Leaf)) { Say NG "server.js not found: $srvArg" }
        else {
            Say OK "server.js exists: $srvArg"
            $a = (Resolve-Path -LiteralPath $srvArg).ProviderPath
            if ((Test-Path $server) -and $a -ne (Resolve-Path -LiteralPath $server).ProviderPath) {
                Say WARN "it is not this repository's copy ($server)"
            }
        }

        if (-not $cmdOk) { continue }
        $key = $cmd + '|' + ($cmdArgs -join '|')
        if (-not $probed.ContainsKey($key)) {
            $p = (& $node -e $probeJs 20000 $cmd @cmdArgs) -join ' '
            if ($p -match '^OK (\d+) (.*)$') { $probed[$key] = [int]$Matches[1]; Say OK "server answered: $($Matches[1]) tools ($($Matches[2]))" }
            else { $probed[$key] = $null; Say NG "server test failed: $p" }
        } elseif ($null -ne $probed[$key]) { Say OK "server answered: $($probed[$key]) tools (same command as above)" }
        else { Say NG 'server test failed (same command as above)' }
    }

    Write-Host '[check] --- Antigravity tool cache'
    $cache = Join-Path $env:USERPROFILE '.gemini\antigravity\mcp\dc-vmu'
    if (Test-Path -LiteralPath $cache -PathType Container) {
        $n = @(Get-ChildItem -LiteralPath $cache -Filter '*.json' -File).Count
        $when = (Get-ChildItem -LiteralPath $cache -File | Measure-Object LastWriteTime -Maximum).Maximum
        Say OK "$cache has $n tool files (Antigravity loaded dc-vmu at least once; newest file $when)"
        $live = @($probed.Values | Where-Object { $null -ne $_ } | Sort-Object -Unique)
        if ($live.Count -and ($live | Where-Object { $_ -ne $n })) {
            Say WARN "the server now has $($live -join '/') tools but the cache has ${n}: the cache is stale, restart Antigravity"
        }
    } else {
        Say NG "$cache does not exist: Antigravity has not loaded dc-vmu yet (restart Antigravity)"
    }

    if ($script:bad) { Write-Host "[check] $($script:bad) problem(s) found" -ForegroundColor Red; exit 1 }
    Write-Host '[check] all OK' -ForegroundColor Green
    exit 0
}

# node does the JSON work: read (BOM tolerated), set or delete mcpServers["dc-vmu"], print the result
$js = @'
const fs = require('fs');
const [file, mode, cmd, srv] = process.argv.slice(1);
let cfg = {};
if (fs.existsSync(file)) {
  const t = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').trim();
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
