' model-console launcher v15 - opens the console with NO black box, resolves paths from THIS folder.
' -WindowStyle Hidden is REQUIRED: without it pwsh style 0 makes the WinForms window invisible (verified 2026-10-19).
' ASCII only (machine ACP=936). 2026-10-19.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Dim here, ps1, pwsh
here = fso.GetParentName(WScript.ScriptFullName)
ps1 = here + "\model-console.ps1"
pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"
If Not fso.FileExists(pwsh) Then pwsh = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
sh.Run """" & pwsh & """ -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """", 0, False