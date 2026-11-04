<#
.SYNOPSIS
  Turns bleem2's heartbeat lines in a dc_auto log into a CSV and an HTML chart (the bleem2 preset
  runs this after every run as PostRun). Also usable by hand:
    .\profiles\bleem2_stats.ps1 .\logs\auto_20261103_150224.txt

  Reads, every 30 frames:
    HB f=<frame> ... fps=<n> emu=<n>ms ...
      frame: emu=..ms conv=..ms pvr=..ms spu=..ms/30f dma=..ms/30f skip=..ms/30f jit=..ms/30f lookup=..ms/30f ... vmu=..ms
  Writes <log>.stats.csv and <log>.stats.html next to the log. Under dcload the numbers include
  the /pc/ and console traffic (each dcload call stops interrupts), so compare BBA runs with BBA runs.
#>
param([Parameter(Mandatory)][string]$Log)

$rows = New-Object System.Collections.Generic.List[object]
$cur = $null
foreach ($l in [System.IO.File]::ReadLines((Resolve-Path $Log).Path)) {
    if ($l -match '^HB f=(\d+) .*?fps=(\d+) emu=(\d+)ms') {
        $cur = [ordered]@{ frame = [int]$matches[1]; fps = [int]$matches[2]; emu = [int]$matches[3]
                           conv = ''; pvr = ''; spu = ''; dma = ''; skip = ''; jit = ''; lookup = ''; vmu = '' }
        $rows.Add($cur)
    } elseif ($cur -and $l -match '^\s+frame: (.*)') {
        foreach ($m in [regex]::Matches($matches[1], '(\w+)=(\d+)ms')) {
            $k = $m.Groups[1].Value
            if ($cur.Contains($k) -and $k -ne 'emu') { $cur[$k] = [int]$m.Groups[2].Value }
        }
        $cur = $null
    }
}
if ($rows.Count -eq 0) { return }

$csv = [System.IO.Path]::ChangeExtension($Log, '.stats.csv')
$objs = @($rows | ForEach-Object { [pscustomobject]$_ })
$objs | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8

# small SVG line chart: fps (left axis 0..60) and dma / skip ms per 30 frames (right axis)
$W = 900; $H = 260; $pad = 40
$maxF = ($objs | Measure-Object -Property frame -Maximum).Maximum; if ($maxF -lt 1) { $maxF = 1 }
$msVals = @($rows | ForEach-Object { $_.dma, $_.skip } | Where-Object { "$_" -ne '' } | ForEach-Object { [int]$_ })
$maxMs = if ($msVals.Count) { [math]::Max(50, ($msVals | Measure-Object -Maximum).Maximum) } else { 50 }
function Line($key, $max, $color) {
    $pts = foreach ($r in $rows) {
        if ("$($r[$key])" -eq '') { continue }    # compare as text: 0 -eq '' is true in PowerShell
        $x = $pad + ($W - 2 * $pad) * $r.frame / $maxF
        $y = $H - $pad - ($H - 2 * $pad) * [math]::Min(1, [double]$r[$key] / $max)
        '{0:F1},{1:F1}' -f $x, $y
    }
    "<polyline fill='none' stroke='$color' stroke-width='1.5' points='$($pts -join ' ')'/>"
}
$avgFps = [math]::Round(($objs | Measure-Object -Property fps -Average).Average, 1)
$minFps = ($objs | Measure-Object -Property fps -Minimum).Minimum
$svg = "<svg width='$W' height='$H' xmlns='http://www.w3.org/2000/svg' style='background:#fff;border:1px solid #ccc'>" +
       "<line x1='$pad' y1='$($H-$pad)' x2='$($W-$pad)' y2='$($H-$pad)' stroke='#888'/>" +
       "<text x='4' y='$($pad)' font-size='11'>60 fps</text><text x='$($W-$pad+2)' y='$($pad)' font-size='11'>$maxMs ms</text>" +
       "<text x='$pad' y='$($H-8)' font-size='11'>frame 0</text><text x='$($W-$pad-60)' y='$($H-8)' font-size='11'>frame $maxF</text>" +
       (Line 'fps' 60 '#1565c0') + (Line 'dma' $maxMs '#c62828') + (Line 'skip' $maxMs '#2e7d32') + '</svg>'
$name = Split-Path -Leaf $Log
$html = "<!doctype html><meta charset='utf-8'><title>bleem2 stats $name</title><body style='font:14px sans-serif;margin:16px'>" +
        "<h1>bleem2 stats: $name</h1><p>$($rows.Count) samples, fps average $avgFps, minimum $minFps. " +
        "<span style='color:#1565c0'>fps</span> / <span style='color:#c62828'>dma ms per 30 frames</span> / " +
        "<span style='color:#2e7d32'>skip ms per 30 frames</span></p>$svg<p>CSV: $(Split-Path -Leaf $csv)</p></body>"
$htmlPath = [System.IO.Path]::ChangeExtension($Log, '.stats.html')
Set-Content -LiteralPath $htmlPath -Value $html -Encoding utf8
Write-Host "[stats] $($rows.Count) samples, fps avg $avgFps min $minFps -> $(Split-Path -Leaf $htmlPath)" -ForegroundColor DarkCyan
