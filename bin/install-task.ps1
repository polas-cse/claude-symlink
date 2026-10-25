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

$launcher = Join-Path $PSScriptRoot 'run-hidden.vbs'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw "run-hidden.vbs not found next to this script ($PSScriptRoot)."
}

# Go through wscript.exe, not powershell.exe: powershell always creates a
# console window and only then hides it, which is the terminal that flashes for
# a second every run. wscript is windowless, so nothing appears at all.
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}"' -f $launcher)

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
