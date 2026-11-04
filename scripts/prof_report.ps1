<#
.SYNOPSIS
  Summarises prof\prof.csv written by the dcdev profiler (dcdev_prof_*):
  average / worst time per section and how often the frame went over budget.
  -Html also writes prof_report.html (a bar chart per section) next to the CSV.

.EXAMPLE
  .\prof_report.ps1 ..\sample\hello_bba\host\prof\prof.csv
  .\prof_report.ps1 ..\sample\hello_bba\host\prof\prof.csv -Html -BudgetUs 16683
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Csv,
    [int]$BudgetUs = 16683,     # one 60 Hz frame
    [switch]$Html
)
$ErrorActionPreference = 'Stop'

$rows = Import-Csv $Csv
if (-not $rows) { throw "No data in $Csv" }

$summary = $rows | Group-Object section | ForEach-Object {
    $avg = ($_.Group | Measure-Object -Property avg_us -Average).Average
    $max = ($_.Group | ForEach-Object { [int]$_.max_us } | Measure-Object -Maximum).Maximum
    [pscustomobject]@{
        Section      = $_.Name
        'Avg us'     = [int]$avg
        'Worst us'   = $max
        'Avg % frame'= [math]::Round(100 * $avg / $BudgetUs, 1)
        Samples      = $_.Count
    }
} | Sort-Object 'Avg us' -Descending

$frames = @($rows | Where-Object section -eq 'frame')   # @(): one interval would have no .Count
$over = @($frames | Where-Object { [int]$_.max_us -gt $BudgetUs * 1.05 }).Count
Write-Host "Profile: $Csv  ($($frames.Count) intervals, budget $BudgetUs us)"
$summary | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Intervals with a frame over budget (+5%): $over / $($frames.Count)"

if ($Html) {
    $out = Join-Path (Split-Path -Parent (Resolve-Path $Csv)) 'prof_report.html'
    $sections = $summary.Section
    $series = foreach ($s in $sections) {
        $pts = $rows | Where-Object section -eq $s
        $vals = ($pts | ForEach-Object { [int]$_.avg_us }) -join ','
        "{name:'$s',vals:[$vals]}"
    }
    $page = @"
<!doctype html><html><head><meta charset="utf-8"><title>Dreamcast profile</title>
<style>body{font:14px sans-serif;margin:16px;background:#fff;color:#222}
@media (prefers-color-scheme:dark){body{background:#1b1b1b;color:#ddd}}
canvas{width:100%;max-width:960px;height:320px;border:1px solid #8884}
table{border-collapse:collapse}td,th{padding:2px 10px;text-align:right}th:first-child,td:first-child{text-align:left}</style>
</head><body><h2>Dreamcast profile</h2><p>$Csv &mdash; average microseconds per interval, budget $BudgetUs us</p>
<canvas id="c" width="960" height="320"></canvas><div id="legend"></div>
<table><tr><th>Section</th><th>Avg us</th><th>Worst us</th><th>Avg % frame</th></tr>
$(($summary | ForEach-Object { "<tr><td>$($_.Section)</td><td>$($_.'Avg us')</td><td>$($_.'Worst us')</td><td>$($_.'Avg % frame')</td></tr>" }) -join "`n")
</table>
<script>
const S=[$($series -join ',')],B=$BudgetUs,c=document.getElementById('c'),g=c.getContext('2d');
const cols=['#3b82f6','#ef4444','#10b981','#f59e0b','#8b5cf6','#06b6d4','#ec4899','#84cc16'];
let mx=B;S.forEach(s=>s.vals.forEach(v=>mx=Math.max(mx,v)));mx*=1.1;
const n=Math.max(...S.map(s=>s.vals.length)),W=c.width,H=c.height,y=v=>H-v/mx*H;
g.strokeStyle='#888';g.setLineDash([4,4]);g.beginPath();g.moveTo(0,y(B));g.lineTo(W,y(B));g.stroke();g.setLineDash([]);
S.forEach((s,i)=>{g.strokeStyle=cols[i%cols.length];g.beginPath();s.vals.forEach((v,j)=>{const x=n>1?j/(n-1)*W:0;j?g.lineTo(x,y(v)):g.moveTo(x,y(v))});g.stroke();
document.getElementById('legend').innerHTML+='<span style="color:'+cols[i%cols.length]+'">&#9632; '+s.name+'</span> &nbsp; ';});
</script></body></html>
"@
    $page | Out-File -Encoding utf8 $out
    Write-Host "Chart: $out"
}
