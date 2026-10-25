' Starts the change watcher with no console window and keeps it running.
'
' Unlike run-loop.vbs, which syncs on a ten-minute timer, this starts
' claude-sync.ps1 watch, which notices a change within about half a minute. If
' the watcher ever exits - a crash, or the repo being moved - this restarts it
' after a minute.
'
' Run(cmd, 0, True): 0 = hidden window, True = wait, so the restart only
' happens once the watcher has actually stopped.

Dim shell, fso, here, script, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(here, "claude-sync.ps1")
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & script & """ watch"

' Let the desktop and network settle before the first sync.
WScript.Sleep 30000

Do
  On Error Resume Next
  shell.Run cmd, 0, True
  On Error Goto 0
  WScript.Sleep 60000
Loop
