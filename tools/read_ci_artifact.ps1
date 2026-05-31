$ErrorActionPreference = 'Stop'
Set-Location 'c:/Users/JB/workspace/ardour'

$artifactId = $args[0]
if (-not $artifactId) {
  throw 'Usage: pwsh -File tools/read_ci_artifact.ps1 <artifact-id>'
}

$suffix = "${artifactId}_$PID"
$zipPath = "_ci_artifact_$suffix.zip"
$outDir = "_ci_artifact_$suffix"

if (Test-Path $zipPath) {
  Remove-Item -Force $zipPath
}
if (Test-Path $outDir) {
  Remove-Item -Recurse -Force $outDir
}

# gh api writes binary zip bytes to stdout; redirect to file
gh api "repos/LimitlessGreen/ardour/actions/artifacts/$artifactId/zip" > $zipPath

Expand-Archive -LiteralPath $zipPath -DestinationPath $outDir -Force
Get-ChildItem $outDir | ForEach-Object { $_.Name }

foreach ($logName in @('python.log', 'gcc.log', 'pkg-config.log', 'ccache-config.log', 'configure.log', 'build.log', 'i18n.log')) {
  $logPath = Join-Path $outDir $logName
  if (Test-Path $logPath) {
    Write-Host "--- $logName ---"
    Get-Content $logPath -TotalCount 200
  }
}
