$ErrorActionPreference = "Stop"

$processes = Get-CimInstance Win32_Process |
  Where-Object {
    ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
    $_.CommandLine -match "codex-compact-rescue\.ps1" -and
    $_.CommandLine -notmatch "stop-codex-compact-rescue\.ps1" -and
    $_.ProcessId -ne $PID
  }

if (-not $processes) {
  Write-Host "No codex compact rescue watcher process found."
  exit 0
}

foreach ($process in $processes) {
  Write-Host "Stopping PID $($process.ProcessId): $($process.CommandLine)"
  Stop-Process -Id $process.ProcessId -Force
}
