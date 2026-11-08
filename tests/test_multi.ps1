<#
  Several Dreamcasts at once, on the PC only: a stand-in dc-tool-ip (built here from C#) that prints what
  dcload prints and "runs" a few seconds. Loopback addresses 127.0.0.x play the Dreamcasts (they answer ping).
  Checks:
    - 16 dc_auto with different IPs run at the same time (none waits for another's dc-tool-ip)
    - two dc_auto with the same IP run one after the other
    - a preset with Exclusive runs on one Dreamcast at a time, and its Prepare runs only then
    - builds of the same folder run one at a time
    - dc_gui.ps1: two units run, Ctrl+C stops one, the other keeps running
  Takes about a minute. Writes only to build\tests\multi and logs\units\MT*, GT*.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$work = Join-Path $root 'build\tests\multi'
New-Item -ItemType Directory -Force $work | Out-Null
$fake = Join-Path $work 'fake-dc-tool-ip.exe'
if (-not (Test-Path $fake)) {
    Add-Type -OutputAssembly $fake -OutputType ConsoleApplication -TypeDefinition @'
using System; using System.Threading;
public static class FakeDcTool {
    public static int Main(string[] args) {
        string t = "?";
        for (int i = 0; i + 1 < args.Length; i++) if (args[i] == "-t") t = args[i + 1];
        int sec = 4; int.TryParse(Environment.GetEnvironmentVariable("FAKE_RUN_SEC") ?? "4", out sec);
        Console.WriteLine("Transferred 4 bytes at 1000.0 bytes / sec");
        Console.WriteLine("Sending execute command (0xac010000, console=1, cdfsredir=0)...executing");
        Console.WriteLine("START " + DateTime.Now.ToString("o"));
        Console.Out.Flush();
        Thread.Sleep(sec * 1000);
        Console.WriteLine("END " + DateTime.Now.ToString("o"));
        return 0;
    }
}
'@
}
Set-Content (Join-Path $work 'prog.elf') 'x'
Set-Content (Join-Path $work 'plain.ps1') "@{ Elf = Join-Path `$PSScriptRoot 'prog.elf' }"
Set-Content (Join-Path $work 'excl.ps1') "@{ Elf = Join-Path `$PSScriptRoot 'prog.elf'; Exclusive = 'multitest'; Prepare = { Add-Content (Join-Path `$PSScriptRoot 'prepare.txt') (Get-Date -Format o) } }"
Set-Content (Join-Path $work 'bld.ps1') ("@{ Elf = Join-Path `$PSScriptRoot 'prog.elf'; BuildDir = `$PSScriptRoot; " +
    "Build = { Add-Content (Join-Path `$PSScriptRoot 'build.txt') ('begin ' + (Get-Date -Format o)); Start-Sleep 2; Add-Content (Join-Path `$PSScriptRoot 'build.txt') ('end ' + (Get-Date -Format o)) } }")
$env:DC_TOOL_IP = $fake

$script:ok = 0; $script:bad = 0
function T([string]$name, [bool]$cond, [string]$info = '') {
    if ($cond) { $script:ok++ } else { $script:bad++; Write-Host "FAIL $name $info" -ForegroundColor Red }
}
# starts one dc_auto per IP at once; returns per unit @{ Start; End } from the stand-in's output
function Invoke-Units([string]$preset, [string[]]$ips, [int]$sec) {
    $env:FAKE_RUN_SEC = "$sec"
    foreach ($f in 'prepare.txt', 'build.txt') { Remove-Item (Join-Path $work $f) -ErrorAction SilentlyContinue }
    $procs = for ($i = 0; $i -lt $ips.Count; $i++) {
        $u = "MT$($i + 1)"
        Remove-Item -Recurse -Force (Join-Path $root "logs\units\$u") -ErrorAction SilentlyContinue
        Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $work "out_$u.txt") -RedirectStandardError (Join-Path $work "err_$u.txt") -ArgumentList (
            "-NoProfile -ExecutionPolicy Bypass -File `"$root\scripts\dc_auto.ps1`" -Preset `"$work\$preset`" -Ip $($ips[$i]) -Unit $u -NoNotify -WaitTimeout 90")
    }
    foreach ($p in $procs) { if (-not $p.WaitForExit(150000)) { Stop-Process -Id $p.Id -Force } }
    for ($i = 0; $i -lt $ips.Count; $i++) {
        $lines = @(Get-ChildItem (Join-Path $root "logs\units\MT$($i + 1)") -Filter 'auto_*.txt' -ErrorAction SilentlyContinue | Get-Content)
        $s = $lines | Where-Object { $_ -like 'START *' } | Select-Object -First 1
        $e = $lines | Where-Object { $_ -like 'END *' } | Select-Object -First 1
        @{ Start = $(if ($s) { [datetime]($s -replace '^START ') }); End = $(if ($e) { [datetime]($e -replace '^END ') }) }
    }
}

Write-Host '[multi] 16 Dreamcasts, different IPs...'
$r = @(Invoke-Units 'plain.ps1' @(1..16 | ForEach-Object { "127.0.0.$_" }) 8)
T '16 units all ran' (@($r | Where-Object { $_.End }).Count -eq 16)
$latestStart = ($r | ForEach-Object Start | Measure-Object -Maximum).Maximum
$firstEnd = ($r | ForEach-Object End | Measure-Object -Minimum).Minimum
T '16 units overlap (no one waited for another)' ($latestStart -lt $firstEnd) "latest start $latestStart, first end $firstEnd"

Write-Host '[multi] same IP twice...'
$r = @(Invoke-Units 'plain.ps1' @('127.0.0.1', '127.0.0.1') 3)
$a, $b = $r | Sort-Object { $_.Start }
T 'same IP: both ran' ($a.End -and $b.End)
T 'same IP: one after the other' ($b.Start -ge $a.End) "$($a.Start)-$($a.End) / $($b.Start)-$($b.End)"

Write-Host '[multi] Exclusive preset on two Dreamcasts...'
$r = @(Invoke-Units 'excl.ps1' @('127.0.0.1', '127.0.0.2') 3)
$a, $b = $r | Sort-Object { $_.Start }
T 'exclusive: both ran' ($a.End -and $b.End)
T 'exclusive: one at a time' ($b.Start -ge $a.End)
$prep = @(Get-Content (Join-Path $work 'prepare.txt') | ForEach-Object { [datetime]$_ } | Sort-Object)
T 'exclusive: Prepare of the second ran after the first ended' ($prep.Count -eq 2 -and $prep[1] -ge $a.End)

Write-Host '[multi] same build folder on three Dreamcasts...'
$r = @(Invoke-Units 'bld.ps1' @('127.0.0.1', '127.0.0.2', '127.0.0.3') 2)
T 'build: all ran' (@($r | Where-Object { $_.End }).Count -eq 3)
$ev = @(Get-Content (Join-Path $work 'build.txt'))
$nested = $false; $depth = 0
foreach ($l in $ev) { if ($l -like 'begin *') { $depth++; if ($depth -gt 1) { $nested = $true } } else { $depth-- } }
T 'build: one at a time' ($ev.Count -eq 6 -and -not $nested) ($ev -join ' ')

Write-Host '[multi] dc_gui.ps1: Ctrl+C stops one unit only...'
$env:FAKE_RUN_SEC = '60'; $env:DC_TEST_ELF = Join-Path $work 'prog.elf'
$g = @(& powershell -NoProfile -ExecutionPolicy Bypass -STA -File "$root\scripts\dc_gui.ps1" -SelfTest jobs 2>&1 | ForEach-Object { "$_" })
T 'gui: Ctrl+C stopped GT1, GT2 kept running' (@($g | Where-Object { $_ -match 'GT1 stopped by Ctrl\+C: True\s+GT2 still running: True' }).Count -eq 1) ($g -join ' | ')
T 'gui: GT1 cleaned up (status idle)' (@($g | Where-Object { $_ -match 'GT1 status: state=idle' }).Count -eq 1)
T 'gui: nothing left running' (@($g | Where-Object { $_ -match 'jobs left: 0\s+stand-in dc-tool-ip left: 0' }).Count -eq 1)

foreach ($u in @(1..16 | ForEach-Object { "MT$_" }) + 'GT1', 'GT2') { Remove-Item -Recurse -Force (Join-Path $root "logs\units\$u") -ErrorAction SilentlyContinue }
Write-Host "multi: $script:ok passed, $script:bad failed"
if ($script:bad) { throw 'multi tests failed' }
