Dim WShell
Set WShell = CreateObject("WScript.Shell")
WShell.Run "watcher-vlc.exe", 0
Set WShell = Nothing