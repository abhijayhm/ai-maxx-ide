' Run a program with no visible console (for scheduled tasks / watchdog restarts).
' Usage:
'   wscript.exe _run_hidden.vbs "C:\path\program.exe" [arg1 [arg2 ...]]
If WScript.Arguments.Count < 1 Then WScript.Quit 1
cmd = """" & WScript.Arguments(0) & """"
If WScript.Arguments.Count > 1 Then
    For i = 1 To WScript.Arguments.Count - 1
        cmd = cmd & " """ & Replace(WScript.Arguments(i), """", """""") & """"
    Next
End If
CreateObject("WScript.Shell").Run cmd, 0, False
