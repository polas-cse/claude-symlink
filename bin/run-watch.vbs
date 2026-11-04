' Starts the change watcher with no console window and keeps it running.
'
' Starts claude-sync.ps1 watch, which notices a change within about 20 seconds.
' If the watcher ever exits - a crash, or the repo being moved - this restarts
' it after a minute.
'
' The scheduled task fires this every ten minutes, so the first thing it does is
' check whether a copy of itself is already running and quit if so. Without that
' guard, a new watcher would pile up on every run.
'
' Run(cmd, 0, True): 0 = hidden window, True = wait, so the restart only
' happens once the watcher has actually stopped.

Dim shell, fso, here, script, cmd, wmi, procs, mine, others
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Quit if another run-watch.vbs is already going.
mine = "run-watch.vbs"
others = 0
On Error Resume Next
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set procs = wmi.ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'wscript.exe'")
If Err.Number = 0 Then
  Dim p
  For Each p In procs
    If Not IsNull(p.CommandLine) Then
      If InStr(1, p.CommandLine, mine, vbTextCompare) > 0 Then others = others + 1
    End If
  Next
End If
On Error Goto 0

' This process is one of them, so anything above one means a copy is running.
If others > 1 Then WScript.Quit 0

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
