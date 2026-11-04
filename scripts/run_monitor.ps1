param(
  [string]$QtBin = 'C:\msys64\ucrt64\bin',
  [string]$Port,
  [switch]$Demo
)

$ErrorActionPreference = 'Stop'
if ($Demo -and $Port) { throw '-Demo와 -Port는 함께 사용할 수 없습니다.' }
if ($Port -and $Port -notmatch '^COM[0-9]+$') { throw '포트는 COM4와 같은 형식으로 지정하세요.' }
& (Join-Path $PSScriptRoot 'build_monitor.ps1') -QtBin $QtBin
$repoRoot = Split-Path -Parent $PSScriptRoot
$originalPath = $env:PATH
$originalPlatform = $env:QT_QPA_PLATFORM
try {
  $env:PATH = "$QtBin;$originalPath"
  $env:QT_QPA_PLATFORM = 'windows'
  $arguments = @()
  if ($Demo) { $arguments += '--demo' }
  if ($Port) { $arguments += '--port'; $arguments += $Port }
  $launch = @{
    FilePath = Join-Path $repoRoot 'desktop/build/release/sensor_monitor.exe'
    WorkingDirectory = $repoRoot
    WindowStyle = 'Normal'
  }
  if ($arguments.Count -gt 0) { $launch.ArgumentList = $arguments }
  Start-Process @launch
} finally {
  $env:PATH = $originalPath
  $env:QT_QPA_PLATFORM = $originalPlatform
}
