<#
.SYNOPSIS
    Generates an Azure DevOps / TFS-style HTML test report from a VSTest .trx file.

.DESCRIPTION
    Reads the most recent .trx file in the given results directory and writes
    report.html styled like the Azure DevOps "Tests" results tab:
      - Header bar with pass/fail status icon and build/run name
      - Summary row: total tests, donut chart, pass %, run duration, not-reported count
      - Filterable/searchable results table with outcome badges
      - Celebratory "Hooray! No test failures" state when everything passes
    Uses Chart.js from cdnjs for the donut chart; requires outbound access to
    cdnjs.cloudflare.com (or vendor chart.min.js locally and edit the <script src>).

.PARAMETER ResultsDir
    Directory containing the .trx file(s). Defaults to "TestResults".

.PARAMETER OutFile
    Output HTML file name, written inside ResultsDir. Defaults to "report.html".

.PARAMETER RunName
    Display name for the run/build shown in the header. Defaults to the trx file name.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Generate-TestReport.ps1 -ResultsDir TestResults -RunName "BasicMath unit tests"
#>

param(
    [string]$ResultsDir = "TestResults",
    [string]$OutFile = "report.html",
    [string]$RunName = "",
    [string]$TriggeredBy = "",
    [string]$RepoName = "",
    [string]$GitBranch = "",
    [string]$GitCommit = "",
    [string]$BuildDurationDisplay = "",
    [string]$JobsJson = ""
)

# Fall back to common Jenkins environment variables when not explicitly passed in
if ([string]::IsNullOrWhiteSpace($TriggeredBy)) {
    $TriggeredBy = if ($env:BUILD_USER) { $env:BUILD_USER } else { "Jenkins" }
}
if ([string]::IsNullOrWhiteSpace($RepoName)) {
    $RepoName = if ($env:JOB_NAME) { $env:JOB_NAME } else { "" }
}
if ([string]::IsNullOrWhiteSpace($GitBranch)) {
    $GitBranch = if ($env:GIT_BRANCH) { $env:GIT_BRANCH } else { "" }
}
if ([string]::IsNullOrWhiteSpace($GitCommit)) {
    $GitCommit = if ($env:GIT_COMMIT) { $env:GIT_COMMIT.Substring(0, [Math]::Min(7, $env:GIT_COMMIT.Length)) } else { "" }
}

# Jobs/stages list: expects a JSON array like
#   [{"name":"Build","status":"Success","duration":"10m 0s"},{"name":"Run MSTest","status":"Success","duration":"3s"}]
# Falls back to a single "Build" row if nothing is supplied.
$jobsList = @()
if (-not [string]::IsNullOrWhiteSpace($JobsJson)) {
    try {
        $jobsList = $JobsJson | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse -JobsJson, falling back to default jobs list."
    }
}
if (-not $jobsList -or $jobsList.Count -eq 0) {
    $jobsList = @([PSCustomObject]@{ name = "Build"; status = "Success"; duration = "" })
}

$ErrorActionPreference = "Stop"

$trxFile = Get-ChildItem -Path $ResultsDir -Filter *.trx -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $trxFile) {
    Write-Error "No .trx file found in '$ResultsDir'."
    exit 1
}

Write-Host "Using trx file: $($trxFile.FullName)"

if ([string]::IsNullOrWhiteSpace($RunName)) {
    $RunName = $trxFile.BaseName
}

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

$total    = $tests.Count
$passed   = ($tests | Where-Object { $_.Outcome -eq "Passed" }).Count
$failed   = ($tests | Where-Object { $_.Outcome -eq "Failed" }).Count
$other    = $total - $passed - $failed
$notRun   = ($tests | Where-Object { $_.Outcome -eq "NotExecuted" -or $_.Outcome -eq "Inconclusive" }).Count
$passPct  = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 1) } else { 0 }
$totalDurationSec = [math]::Round(($tests | Measure-Object -Property DurationS -Sum).Sum, 3)
$durTs = [TimeSpan]::FromSeconds($totalDurationSec)
$durationDisplay = if ($durTs.TotalMinutes -ge 1) {
    "{0}m {1}s" -f [int]$durTs.TotalMinutes, $durTs.Seconds
} else {
    "{0}s" -f [math]::Round($durTs.TotalSeconds, 1)
}
$runDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$allPassed = ($failed -eq 0 -and $other -eq 0 -and $total -gt 0)

$tableRows = ($tests | ForEach-Object {
    $badgeClass = switch ($_.Outcome) {
        "Passed" { "badge-pass" }
        "Failed" { "badge-fail" }
        default  { "badge-other" }
    }
    $escapedName = $_.Name -replace "'", "&#39;"
    "<tr data-outcome='$($_.Outcome)' data-name='$($escapedName.ToLower())'><td>$($_.Name)</td><td><span class='badge $badgeClass'>$($_.Outcome)</span></td><td>$($_.DurationS) s</td></tr>"
}) -join "`n"

$statusIcon = if ($allPassed) { "&#10004;" } else { "&#33;" }
$statusIconClass = if ($allPassed) { "icon-pass" } else { "icon-fail" }

if ([string]::IsNullOrWhiteSpace($BuildDurationDisplay)) {
    $BuildDurationDisplay = $durationDisplay
}

$jobsRows = ($jobsList | ForEach-Object {
    $jobIconClass = if ($_.status -eq "Success") { "icon-pass" } else { "icon-fail" }
    $jobIcon = if ($_.status -eq "Success") { "&#10004;" } else { "&#33;" }
    $jobDuration = if ($_.duration) { $_.duration } else { "&mdash;" }
    "<tr><td><span class='status-icon-sm $jobIconClass'>$jobIcon</span>$($_.name)</td><td>$($_.status)</td><td>$jobDuration</td></tr>"
}) -join "`n"

$emptyStateBlock = ""
if ($allPassed) {
    $emptyStateBlock = @"
<div class="celebrate">
  <div class="trophy">&#127942;</div>
  <div class="celebrate-title">Hooray! There are no test failures.</div>
  <div class="celebrate-sub">All $total tests passed in this run.</div>
</div>
"@
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Test Results - $RunName</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.min.js"></script>
<style>
  * { box-sizing: border-box; }
  body { font-family: Segoe UI, Arial, sans-serif; background: #faf9f8; margin: 0; padding: 0; color: #201f1e; }
  .header { display: flex; align-items: center; justify-content: space-between; padding: 18px 28px; background: #fff; border-bottom: 1px solid #edebe9; }
  .header-left { display: flex; align-items: center; gap: 12px; }
  .status-icon { width: 28px; height: 28px; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-size: 15px; font-weight: 700; flex-shrink: 0; }
  .icon-pass { background: #13a10e; }
  .icon-fail { background: #d13438; }
  .header-title { font-size: 17px; font-weight: 600; }
  .header-sub { font-size: 12px; color: #605e5c; margin-top: 2px; }
  .tabs { display: flex; gap: 24px; padding: 0 28px; background: #fff; border-bottom: 1px solid #edebe9; }
  .tab { padding: 12px 2px; font-size: 13px; color: #605e5c; border-bottom: 2px solid transparent; }
  .tab.active { color: #201f1e; border-bottom-color: #0078d4; font-weight: 600; }
  .content { padding: 24px 28px; }
  .summary-panel { background: #fff; border: 1px solid #edebe9; border-radius: 4px; margin-bottom: 20px; }
  .summary-heading { padding: 12px 20px; font-size: 13px; font-weight: 600; border-bottom: 1px solid #edebe9; }
  .summary-strip { padding: 10px 20px; background: #faf9f8; font-size: 13px; color: #323130; border-bottom: 1px solid #edebe9; }
  .summary-stats { display: flex; align-items: center; gap: 48px; padding: 24px 20px; flex-wrap: wrap; }
  .stat-total .num { font-size: 40px; font-weight: 600; line-height: 1; }
  .stat-total .lbl { font-size: 13px; color: #605e5c; margin-top: 4px; }
  .donut-block { display: flex; align-items: center; gap: 16px; }
  .donut-wrap { width: 84px; height: 84px; }
  .legend-row { display: flex; align-items: center; gap: 6px; font-size: 13px; margin: 2px 0; }
  .dot { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }
  .dot-pass { background: #13a10e; }
  .dot-fail { background: #d13438; }
  .dot-other { background: #c8c6c4; }
  .stat-block .num { font-size: 26px; font-weight: 600; line-height: 1; }
  .stat-block .lbl { font-size: 13px; color: #605e5c; margin-top: 4px; }
  .toolbar { display: flex; align-items: center; justify-content: space-between; padding: 10px 20px; border-bottom: 1px solid #edebe9; font-size: 13px; color: #605e5c; }
  .filter-input { padding: 8px 20px; border-bottom: 1px solid #edebe9; }
  .filter-input input { width: 280px; max-width: 100%; padding: 6px 10px; font-size: 13px; border: 1px solid #d2d0ce; border-radius: 2px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 10px 20px; border-bottom: 1px solid #f3f2f1; font-size: 13px; }
  th { color: #605e5c; font-weight: 600; background: #fff; }
  .badge { padding: 2px 10px; border-radius: 10px; font-size: 12px; font-weight: 600; }
  .badge-pass { background: #dff6dd; color: #107c10; }
  .badge-fail { background: #fde7e9; color: #a4262c; }
  .badge-other { background: #f3f2f1; color: #605e5c; }
  .celebrate { text-align: center; padding: 60px 20px 70px; }
  .trophy { font-size: 64px; }
  .celebrate-title { font-size: 20px; color: #323130; margin-top: 12px; }
  .celebrate-sub { font-size: 13px; color: #605e5c; margin-top: 6px; }
  .chart-box { background: #fff; border: 1px solid #edebe9; border-radius: 4px; padding: 16px 20px; margin-bottom: 20px; }
  .chart-box h3 { font-size: 13px; margin: 0 0 12px; color: #323130; }
  .tab-panel { display: none; }
  .tab-panel.active { display: block; }
  .run-meta-panel { background: #fff; border: 1px solid #edebe9; border-radius: 4px; padding: 20px; margin-bottom: 20px; }
  .run-meta-top { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; }
  .run-meta-who { display: flex; align-items: center; gap: 10px; font-size: 15px; }
  .avatar { width: 26px; height: 26px; border-radius: 50%; background: #a4262c; color: #fff; font-size: 11px; font-weight: 700; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .run-meta-sub { font-size: 12px; color: #605e5c; display: flex; gap: 16px; margin-bottom: 20px; }
  .meta-grid { display: flex; gap: 60px; flex-wrap: wrap; }
  .meta-col-heading { font-size: 12px; color: #605e5c; margin-bottom: 8px; }
  .meta-row { font-size: 13px; margin-bottom: 6px; }
  .commits-pill { background: #f3f2f1; border-radius: 3px; padding: 5px 12px; font-size: 12px; color: #323130; }
  .jobs-panel { background: #fff; border: 1px solid #edebe9; border-radius: 4px; }
  .jobs-heading { padding: 14px 20px; font-size: 15px; font-weight: 600; border-bottom: 1px solid #edebe9; }
  .jobs-panel table th { color: #605e5c; }
  .status-icon-sm { width: 18px; height: 18px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; color: #fff; font-size: 10px; margin-right: 8px; vertical-align: middle; }
</style>
</head>
<body>

<div class="header">
  <div class="header-left">
    <div class="status-icon $statusIconClass">$statusIcon</div>
    <div>
      <div class="header-title">$RunName</div>
      <div class="header-sub">Generated $runDate &middot; Source: $($trxFile.Name)</div>
    </div>
  </div>
</div>

<div class="tabs">
  <div class="tab active" onclick="showTab('summary', this)">Summary</div>
  <div class="tab" onclick="showTab('tests', this)">Tests</div>
  <div class="tab" onclick="showTab('coverage', this)">Code Coverage</div>
</div>

<div class="content">

  <div id="tab-summary" class="tab-panel active">

    <div class="run-meta-panel">
      <div class="run-meta-top">
        <div class="run-meta-who">
          <span class="avatar">$($TriggeredBy.Substring(0, [Math]::Min(2,$TriggeredBy.Length)).ToUpper())</span>
          <span>Manually run by <strong>$TriggeredBy</strong></span>
        </div>
        <div class="commits-pill">$($jobsList.Count) job(s)</div>
      </div>
      <div class="run-meta-sub">
        <span>&#128197; $runDate</span>
        <span>&#128337; $BuildDurationDisplay</span>
      </div>
      <div class="meta-grid">
        <div>
          <div class="meta-col-heading">Repository and version</div>
          <div class="meta-row">$RepoName</div>
          <div class="meta-row">$GitBranch $(if ($GitCommit) { "&nbsp;&middot;&nbsp;$GitCommit" })</div>
        </div>
        <div>
          <div class="meta-col-heading">Tests and coverage</div>
          <div class="meta-row">$passPct% passed</div>
          <div class="meta-row">$total total tests</div>
        </div>
      </div>
    </div>

    <div class="jobs-panel">
      <div class="jobs-heading">Jobs</div>
      <table>
        <thead><tr><th>Name</th><th>Status</th><th>Duration</th></tr></thead>
        <tbody>
$jobsRows
        </tbody>
      </table>
    </div>

  </div>

  <div id="tab-coverage" class="tab-panel">
    <div class="summary-panel">
      <div class="summary-heading">Code Coverage</div>
      <div class="summary-strip">No code coverage data was collected for this run.</div>
    </div>
  </div>

  <div id="tab-tests" class="tab-panel">

  <div class="summary-panel">
    <div class="summary-heading">Summary</div>
    <div class="summary-strip">1 Run(s) Completed ( $passed Passed, $failed Failed )</div>
    <div class="summary-stats">
      <div class="stat-total">
        <div class="num">$total</div>
        <div class="lbl">Total tests</div>
      </div>
      <div class="donut-block">
        <div class="donut-wrap"><canvas id="donut"></canvas></div>
        <div>
          <div class="legend-row"><span class="dot dot-pass"></span>$passed &nbsp;Passed</div>
          <div class="legend-row"><span class="dot dot-fail"></span>$failed &nbsp;Failed</div>
          <div class="legend-row"><span class="dot dot-other"></span>$other &nbsp;Others</div>
        </div>
      </div>
      <div class="stat-block">
        <div class="num">$passPct%</div>
        <div class="lbl">Pass percentage</div>
      </div>
      <div class="stat-block">
        <div class="num">$durationDisplay</div>
        <div class="lbl">Run duration</div>
      </div>
      <div class="stat-block">
        <div class="num">$notRun</div>
        <div class="lbl">Tests not reported</div>
      </div>
    </div>
  </div>

  <div class="chart-box">
    <h3>Duration per test</h3>
    <canvas id="bar" height="90"></canvas>
  </div>

  <div class="summary-panel">
    <div class="toolbar">
      <span>Test results</span>
      <span>$total total</span>
    </div>
    <div class="filter-input">
      <input type="text" id="filterBox" placeholder="Filter by test name..." onkeyup="filterTable()">
    </div>
"@

if ($allPassed) {
    $html += $emptyStateBlock
} else {
    $html += @"
    <table id="resultsTable">
      <thead><tr><th>Test name</th><th>Outcome</th><th>Duration</th></tr></thead>
      <tbody>
$tableRows
      </tbody>
    </table>
"@
}

$labels = ($tests | ForEach-Object { '"' + ($_.Name -replace '"','\"') + '"' }) -join ","
$durations = ($tests | ForEach-Object { $_.DurationS }) -join ","
$barColors = ($tests | ForEach-Object {
    if ($_.Outcome -eq "Passed") { "'#13a10e'" }
    elseif ($_.Outcome -eq "Failed") { "'#d13438'" }
    else { "'#c8c6c4'" }
}) -join ","

$html += @"
  </div>

  </div>
</div>

<script>
function showTab(name, el) {
  document.querySelectorAll('.tab-panel').forEach(function(p) { p.classList.remove('active'); });
  document.querySelectorAll('.tab').forEach(function(t) { t.classList.remove('active'); });
  document.getElementById('tab-' + name).classList.add('active');
  el.classList.add('active');
}

new Chart(document.getElementById('donut'), {
  type: 'doughnut',
  data: {
    labels: ['Passed', 'Failed', 'Other'],
    datasets: [{
      data: [$passed, $failed, $other],
      backgroundColor: ['#13a10e', '#d13438', '#c8c6c4'],
      borderWidth: 0
    }]
  },
  options: {
    cutout: '70%',
    plugins: { legend: { display: false }, tooltip: { enabled: true } }
  }
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

function filterTable() {
  var input = document.getElementById('filterBox');
  if (!input) return;
  var filter = input.value.toLowerCase();
  var rows = document.querySelectorAll('#resultsTable tbody tr');
  rows.forEach(function(row) {
    var name = row.getAttribute('data-name') || '';
    row.style.display = name.indexOf(filter) > -1 ? '' : 'none';
  });
}
</script>

</body>
</html>
"@

$outPath = Join-Path $ResultsDir $OutFile
$html | Out-File -FilePath $outPath -Encoding utf8
Write-Host "Report written to $outPath"
