<#
.SYNOPSIS
    Generates a graphical HTML test report (with charts) from a VSTest .trx file.

.DESCRIPTION
    Reads the most recent .trx file in the given results directory, extracts
    per-test outcome and duration, and writes report.html containing:
      - Summary cards (total / passed / failed / skipped / total duration)
      - A donut chart of pass/fail/skip breakdown
      - A bar chart of duration per test
      - A sortable table of full test details
    Uses Chart.js loaded from cdnjs, so the build agent needs outbound access
    to cdnjs.cloudflare.com (or you can vendor chart.min.js locally and change
    the <script src> below).

.PARAMETER ResultsDir
    Directory containing the .trx file(s). Defaults to "TestResults".

.PARAMETER OutFile
    Output HTML file name, written inside ResultsDir. Defaults to "report.html".

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Generate-TestReport.ps1 -ResultsDir TestResults
#>

param(
    [string]$ResultsDir = "TestResults",
    [string]$OutFile = "report.html"
)

$ErrorActionPreference = "Stop"

$trxFile = Get-ChildItem -Path $ResultsDir -Filter *.trx -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $trxFile) {
    Write-Error "No .trx file found in '$ResultsDir'."
    exit 1
}

Write-Host "Using trx file: $($trxFile.FullName)"

[xml]$xml = Get-Content -Path $trxFile.FullName

$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace("t", "http://microsoft.com/schemas/VisualStudio/TeamTest/2010")

$unitResults = $xml.SelectNodes("//t:UnitTestResult", $ns)

$tests = @()
foreach ($r in $unitResults) {
    $durationStr = $r.duration
    $durationSeconds = 0
    if ($durationStr) {
        try {
            $ts = [TimeSpan]::Parse($durationStr)
            $durationSeconds = [math]::Round($ts.TotalSeconds, 3)
        } catch { $durationSeconds = 0 }
    }
    $tests += [PSCustomObject]@{
        Name       = $r.testName
        Outcome    = $r.outcome
        DurationS  = $durationSeconds
    }
}

$total   = $tests.Count
$passed  = ($tests | Where-Object { $_.Outcome -eq "Passed" }).Count
$failed  = ($tests | Where-Object { $_.Outcome -eq "Failed" }).Count
$other   = $total - $passed - $failed
$totalDuration = [math]::Round(($tests | Measure-Object -Property DurationS -Sum).Sum, 3)
$runDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$labels = ($tests | ForEach-Object { '"' + ($_.Name -replace '"','\"') + '"' }) -join ","
$durations = ($tests | ForEach-Object { $_.DurationS }) -join ","
$barColors = ($tests | ForEach-Object {
    if ($_.Outcome -eq "Passed") { "'#1D9E75'" }
    elseif ($_.Outcome -eq "Failed") { "'#E24B4A'" }
    else { "'#B4B2A9'" }
}) -join ","

$tableRows = ($tests | ForEach-Object {
    $badgeClass = switch ($_.Outcome) {
        "Passed" { "badge-pass" }
        "Failed" { "badge-fail" }
        default  { "badge-other" }
    }
    "<tr><td>$($_.Name)</td><td><span class='badge $badgeClass'>$($_.Outcome)</span></td><td>$($_.DurationS) s</td></tr>"
}) -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Test Report - $runDate</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.min.js"></script>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; background: #f4f4f2; margin: 0; padding: 24px; color: #2c2c2a; }
  h1 { font-size: 22px; font-weight: 600; margin-bottom: 4px; }
  .subtitle { color: #5f5e5a; margin-bottom: 24px; }
  .cards { display: flex; gap: 16px; margin-bottom: 32px; flex-wrap: wrap; }
  .card { background: #fff; border-radius: 8px; padding: 16px 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); min-width: 120px; }
  .card .value { font-size: 28px; font-weight: 700; }
  .card .label { color: #5f5e5a; font-size: 13px; }
  .card.pass .value { color: #0F6E56; }
  .card.fail .value { color: #993C1D; }
  .charts { display: flex; gap: 24px; flex-wrap: wrap; margin-bottom: 32px; }
  .chart-box { background: #fff; border-radius: 8px; padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); flex: 1; min-width: 300px; }
  .chart-box h3 { font-size: 15px; margin-top: 0; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid #eee; font-size: 14px; }
  th { background: #efece4; font-weight: 600; }
  .badge { padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; }
  .badge-pass { background: #E1F5EE; color: #0F6E56; }
  .badge-fail { background: #FAECE7; color: #993C1D; }
  .badge-other { background: #F1EFE8; color: #5F5E5A; }
</style>
</head>
<body>

<h1>Test Report</h1>
<div class="subtitle">Generated $runDate &middot; Source: $($trxFile.Name)</div>

<div class="cards">
  <div class="card"><div class="value">$total</div><div class="label">Total tests</div></div>
  <div class="card pass"><div class="value">$passed</div><div class="label">Passed</div></div>
  <div class="card fail"><div class="value">$failed</div><div class="label">Failed</div></div>
  <div class="card"><div class="value">$other</div><div class="label">Other</div></div>
  <div class="card"><div class="value">$totalDuration s</div><div class="label">Total duration</div></div>
</div>

<div class="charts">
  <div class="chart-box" style="max-width: 320px;">
    <h3>Pass / fail breakdown</h3>
    <canvas id="donut"></canvas>
  </div>
  <div class="chart-box">
    <h3>Duration per test</h3>
    <canvas id="bar"></canvas>
  </div>
</div>

<table>
  <thead><tr><th>Test name</th><th>Outcome</th><th>Duration</th></tr></thead>
  <tbody>
$tableRows
  </tbody>
</table>

<script>
new Chart(document.getElementById('donut'), {
  type: 'doughnut',
  data: {
    labels: ['Passed', 'Failed', 'Other'],
    datasets: [{
      data: [$passed, $failed, $other],
      backgroundColor: ['#1D9E75', '#E24B4A', '#B4B2A9']
    }]
  },
  options: { plugins: { legend: { position: 'bottom' } } }
});

new Chart(document.getElementById('bar'), {
  type: 'bar',
  data: {
    labels: [$labels],
    datasets: [{
      label: 'Duration (s)',
      data: [$durations],
      backgroundColor: [$barColors]
    }]
  },
  options: {
    scales: { y: { beginAtZero: true, title: { display: true, text: 'seconds' } } },
    plugins: { legend: { display: false } }
  }
});
</script>

</body>
</html>
"@

$outPath = Join-Path $ResultsDir $OutFile
$html | Out-File -FilePath $outPath -Encoding utf8
Write-Host "Report written to $outPath"
