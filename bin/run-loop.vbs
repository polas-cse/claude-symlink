' Syncs forever, with no console window and no Task Scheduler.
'
' Started from the Startup folder by install-startup.ps1, this needs no admin
' rights at all - unlike a task in the root Task Scheduler folder, which cannot
' be modified without elevation.
'
' Run(cmd, 0, True): 0 = hidden window, True = wait for it to finish before
' sleeping again, so two syncs never overlap.

Dim shell, fso, here, script, cmd, intervalMs

intervalMs = 10 * 60 * 1000   ' 10 minutes

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(here, "claude-sync.ps1")
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & script & """ auto"

' Let the desktop and network settle before the first sync.
WScript.Sleep 30000

Do
  On Error Resume Next
  shell.Run cmd, 0, True
  On Error Goto 0
  WScript.Sleep intervalMs
Loop
