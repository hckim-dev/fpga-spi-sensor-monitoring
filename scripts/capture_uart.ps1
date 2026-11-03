param(
  [Parameter(Mandatory = $true)]
  [string]$Port,
  [ValidateRange(1, 60)]
  [int]$Seconds = 8,
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not $OutputPath) {
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $OutputPath = Join-Path $repoRoot 'master/spi_sensor_master.sim/step11/uart_capture.json'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force
$connection = [System.IO.Ports.SerialPort]::new(
  $Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One
)
$connection.Encoding = [System.Text.Encoding]::ASCII
$received = [System.Text.StringBuilder]::new()
try {
  $connection.Open()
  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
    $null = $received.Append($connection.ReadExisting())
    Start-Sleep -Milliseconds 20
  }
  $null = $received.Append($connection.ReadExisting())
} finally {
  if ($connection.IsOpen) { $connection.Close() }
  $connection.Dispose()
}

$raw = $received.ToString()
$parts = $raw -split "`n"
$validLines = [System.Collections.Generic.List[string]]::new()
$invalidLines = [System.Collections.Generic.List[string]]::new()
$leadingFragment = ''
$pattern = '^T=(--|-?\d+\.\d)C H=(--|\d+\.\d)% D=(--|\d+)cm L=(OK|ERR:(NONE|TIMEOUT|LENGTH|HEADER|XOR|RESERVED|RANGE|STALE)) O=(OK|ERR)$'
# Port를 열 때 진행 중이던 첫 줄과 마지막 미완성 줄은 별도로 보존한다.
for ($index = 0; $index -lt $parts.Length - 1; $index++) {
  $line = $parts[$index].TrimEnd("`r")
  if ($line.Length -eq 0) { continue }
  if ($line -match $pattern) {
    $validLines.Add($line)
  } elseif ($index -eq 0) {
    $leadingFragment = $line
  } else {
    $invalidLines.Add($line)
  }
}
$result = [ordered]@{
  port = $Port
  baud = 115200
  seconds = $Seconds
  raw = $raw
  leading_fragment = $leadingFragment
  trailing_fragment = $parts[-1]
  valid_lines = $validLines.ToArray()
  invalid_lines = $invalidLines.ToArray()
}
[System.IO.File]::WriteAllText(
  $OutputPath, ($result | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false)
)
Write-Output "UART_CAPTURE valid=$($validLines.Count) invalid=$($invalidLines.Count) file=$OutputPath"
if ($validLines.Count -lt 3 -or $invalidLines.Count -ne 0) {
  throw 'UART capture did not contain at least three correctly formatted complete lines.'
}
$validLines | Select-Object -Unique | ForEach-Object { Write-Output $_ }
