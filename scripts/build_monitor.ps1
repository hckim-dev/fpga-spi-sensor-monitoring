param(
  [string]$QtBin = 'C:\msys64\ucrt64\bin',
  [switch]$Test
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$originalPath = $env:PATH
$originalPlatform = $env:QT_QPA_PLATFORM
$qmake = Join-Path $QtBin 'qmake6.exe'
$make = Join-Path $QtBin 'mingw32-make.exe'
if (-not (Test-Path -LiteralPath $qmake) -or -not (Test-Path -LiteralPath $make)) {
  throw 'Qt 6 MinGW Kit이 필요합니다. -QtBin으로 qmake6.exe와 mingw32-make.exe 폴더를 지정하세요.'
}

function Invoke-BuildTool([string]$Executable, [string]$Arguments, [string]$Directory, [string]$LogName) {
  $options = @{
    FilePath = $Executable
    ArgumentList = $Arguments
    WorkingDirectory = $Directory
    WindowStyle = 'Hidden'
    Wait = $true
    PassThru = $true
    RedirectStandardOutput = Join-Path $Directory "$LogName.log"
    RedirectStandardError = Join-Path $Directory "$LogName.stderr.log"
  }
  $process = Start-Process @options
  if ($process.ExitCode -ne 0) { throw "도구 실행 실패: $Directory\$LogName.stderr.log" }
}

function Build-QtProject([string]$Project, [string]$BuildDirectory) {
  $null = New-Item -ItemType Directory -Force -Path $BuildDirectory
  Push-Location -LiteralPath $BuildDirectory
  try {
    Invoke-BuildTool $qmake ('"' + $Project + '"') $BuildDirectory 'qmake'
    Invoke-BuildTool $make '-j4' $BuildDirectory 'build'
    Write-Output "BUILD_PASS $BuildDirectory"
  } finally {
    Pop-Location
  }
}

try {
  $env:PATH = "$QtBin;$originalPath"
  Build-QtProject (Join-Path $repoRoot 'desktop/monitor.pro') (Join-Path $repoRoot 'desktop/build')
  if ($Test) {
    $testDirectory = Join-Path $repoRoot 'desktop/build-tests'
    Build-QtProject (Join-Path $repoRoot 'desktop/tests/tests.pro') $testDirectory
    $env:QT_QPA_PLATFORM = 'offscreen'
    $testOutput = (Join-Path $testDirectory 'results.txt') + ',txt'
    & (Join-Path $testDirectory 'release/test_monitor.exe') -o $testOutput
    if ($LASTEXITCODE -ne 0) { throw "시험 실패: $testDirectory\results.txt" }
    Get-Content -LiteralPath (Join-Path $testDirectory 'results.txt') | Select-String 'Totals:'
  }
} finally {
  $env:PATH = $originalPath
  $env:QT_QPA_PLATFORM = $originalPlatform
}
