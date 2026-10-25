' Launches claude-sync.ps1 auto with no console window at all.
'
' The scheduled task calls this through wscript.exe, which is a windowless host:
' passing -WindowStyle Hidden to powershell.exe is not enough, because Windows
' creates the console first and hides it a moment later - that is the terminal
' that flashes for about a second.
'
' Run(cmd, 0, False): 0 = hidden window, False = do not wait.

Dim shell, fso, here, script, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(here, "claude-sync.ps1")

cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & script & """ auto"

shell.Run cmd, 0, False
