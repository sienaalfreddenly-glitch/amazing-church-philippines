# Installs a Windows Scheduled Task that starts the ngrok tunnel every time you sign in,
# and auto-restarts if it crashes. Run once from PowerShell:
#
#   powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
#
# Uninstall later with:
#   schtasks /Delete /TN "AmazingChurch-NgrokTunnel" /F

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Batch = Join-Path $Root 'scripts\start-tunnel.cmd'

if (-not (Test-Path $Batch)) {
  Write-Error "Missing $Batch"
  exit 1
}

# Trigger: at logon of the current user
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Action: run the batch file, minimized, no window
$Action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$Batch`"" -WorkingDirectory $Root

# Settings: restart on failure, run whether or not user is logged on, don't stop on idle,
# start within 30s of trigger, allow running on battery
$Settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -DontStopOnIdleEnd `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -StartWhenAvailable

$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Remove any previous version silently
Unregister-ScheduledTask -TaskName 'AmazingChurch-NgrokTunnel' -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName 'AmazingChurch-NgrokTunnel' `
  -Description 'Keeps the ngrok tunnel alive so the Vercel-hosted Amazing Church site can reach the local Supabase Docker stack.' `
  -Trigger $Trigger -Action $Action -Settings $Settings -Principal $Principal | Out-Null

Write-Host ''
Write-Host 'Installed scheduled task: AmazingChurch-NgrokTunnel' -ForegroundColor Green
Write-Host 'It will start automatically at every sign-in and restart if it crashes.'
Write-Host ''
Write-Host 'Starting it now...'
Start-ScheduledTask -TaskName 'AmazingChurch-NgrokTunnel'
Start-Sleep -Seconds 3
Get-ScheduledTask -TaskName 'AmazingChurch-NgrokTunnel' | Get-ScheduledTaskInfo | Select-Object LastRunTime, LastTaskResult, NextRunTime

Write-Host ''
Write-Host 'Logs: %LOCALAPPDATA%\amazing-church\tunnel.log' -ForegroundColor Cyan
