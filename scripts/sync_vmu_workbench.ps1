<#
.SYNOPSIS
  Copies VMU Workbench (github.com/iwa-kasoutuuuuuka/vmu-workbench, MIT) into third_party\vmu-workbench.

.DESCRIPTION
  dc_vmu.ps1 uses its CLI (save list, PS1 memory card .mcr export/import, editing) and its
  vmutransfer program (whole VMU <-> PC over dcload); AI agents use its MCP server (mcp\server.js)
  and its skill vmu-save-analysis (copied to .agent\skills and .claude\skills). Only the files git
  has committed (HEAD of the source clone) are copied, so unfinished work there is left out; its tests, CI and
  agent settings are skipped too. VENDORED.txt records the commit.

.EXAMPLE
  .\sync_vmu_workbench.ps1 -From H:\DC\tools\vmu-workbench
#>
param(
    [Parameter(Mandatory)] [string]$From
)
$ErrorActionPreference = 'Stop'
$src = (Resolve-Path $From).Path
$dst = Join-Path (Split-Path $PSScriptRoot -Parent) 'third_party\vmu-workbench'
$skip = '^(\.github|\.claude|\.agent|test)/|^(\.mcp\.json|CLAUDE\.md|\.gitattributes|mcp/antigravity\.mcp\.json)$'

$files = @(git -C $src ls-tree -r --name-only HEAD) | Where-Object { $_ -notmatch $skip }
if (-not $files) { throw "no committed files in $src" }
# export the commit, not the working tree (git archive -> tar; tar ships with Windows 10+)
$tmp = Join-Path ([IO.Path]::GetTempPath()) "vmu-workbench-$PID"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force (Join-Path $tmp 'x') | Out-Null
git -C $src archive --format=tar -o (Join-Path $tmp 'src.tar') HEAD
if ($LASTEXITCODE) { throw 'git archive failed' }
& (Join-Path $env:SystemRoot 'System32\tar.exe') -xf (Join-Path $tmp 'src.tar') -C (Join-Path $tmp 'x')   # Windows' tar: an MSYS tar on PATH can't read C:\ paths
if ($LASTEXITCODE) { throw 'tar failed' }
# keep .emu\ (the MCP tools write edited saves to .emu\work\, and it holds the Flycast copy): replace the rest
if (Test-Path $dst) { Get-ChildItem -LiteralPath $dst -Force | Where-Object Name -ne '.emu' | Remove-Item -Recurse -Force }
foreach ($f in $files) {
    $to = Join-Path $dst $f
    New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $tmp "x\$f") -Destination $to
}
# its save-analysis skill goes to this repository's agent folders (Claude Code and Antigravity read the same text)
$skill = Join-Path $tmp 'x\.agent\skills\vmu-save-analysis\SKILL.md'
if (Test-Path $skill) {
    foreach ($agentDir in '.agent', '.claude') {
        $to = Join-Path (Split-Path $PSScriptRoot -Parent) "$agentDir\skills\vmu-save-analysis"
        New-Item -ItemType Directory -Force $to | Out-Null
        Copy-Item -LiteralPath $skill -Destination (Join-Path $to 'SKILL.md') -Force
    }
}
Remove-Item -Recurse -Force $tmp
$commit = git -C $src rev-parse --short HEAD
$dirty = if (git -C $src status --porcelain) { ' (uncommitted changes there were not copied)' } else { '' }
@(
    'VMU Workbench, copied by scripts\sync_vmu_workbench.ps1 (do not edit here; change the original and sync again).'
    'Source: https://github.com/iwa-kasoutuuuuuka/vmu-workbench  (MIT, see LICENSE)'
    "Commit: $commit$dirty   Date: $(Get-Date -Format 'yyyy-MM-dd')"
) | Set-Content -Encoding ascii (Join-Path $dst 'VENDORED.txt')
Write-Host "[sync] $($files.Count) files -> $dst  (commit $commit$dirty)" -ForegroundColor Green
