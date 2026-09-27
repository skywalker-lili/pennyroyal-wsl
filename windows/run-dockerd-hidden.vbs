' Launch and wait for the hidden dockerd host.
' Window style 0 hides this helper. The .ps1 starts wsl.exe with CreateNoWindow.
' The path is this file's own folder, not a fixed drive.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = scriptDir & "\run-dockerd-hidden.ps1"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & launcher & """"
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
