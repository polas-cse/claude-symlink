<#
  Registers the ClaudeConfigSync scheduled task: runs `claude-sync.ps1 auto`
  at logon and every 10 minutes, as the current user. No admin rights needed.

  Run once per PC:   .\bin\install-task.ps1
  Remove it again:   .\bin\install-task.ps1 -Remove
#>
param(
  [switch]$Remove,
  [int]$IntervalMinutes = 10
)

$ErrorActionPreference = 'Stop'
$TaskName = 'ClaudeConfigSync'

if ($Remove) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Removed task '$TaskName'." -ForegroundColor Green
  return
}

$script = Join-Path $PSScriptRoot 'claude-sync.ps1'
if (-not (Test-Path -LiteralPath $script)) {
  throw "claude-sync.ps1 not found next to this script ($PSScriptRoot)."
}

$argLine = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" auto' -f $script

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine

$triggers = @(
  New-ScheduledTaskTrigger -AtLogOn
  New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
)

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
  -Settings $settings -Description 'Keeps Claude config in sync with the claude-symlink repo' -Force | Out-Null

Write-Host "Registered '$TaskName': at logon and every $IntervalMinutes minutes." -ForegroundColor Green
Write-Host "Log: $(Join-Path (Split-Path -Parent $PSScriptRoot) 'sync.log')" -ForegroundColor DarkGray
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State
