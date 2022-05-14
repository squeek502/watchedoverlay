@echo off

: watched

regsvr32 /s /u "%~dp0\watched.dll"
if NOT %errorlevel% == 0 (
	if %errorlevel% == 5 (
		echo Failed to uninstall shell extension (access denied^). Make sure to run this script as administrator.
		pause
		exit /B %errorlevel%
	)
	echo Failed to uninstall shell extension, exit code was %errorlevel%
	pause
	exit /B %errorlevel%
)
echo Uninstalled shell extension successfully.
echo You must restart explorer.exe for the changes to take effect.

: watcher

tskill watcher-vlc 2>nul

FOR /f "tokens=1,2*" %%E in ('reg query "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"') DO (
	IF "%%E"=="Startup" (
		set StartupDir=%%G
	)
)
IF "%StartupDir%"=="" (
	echo Not able to determine Startup directory path, unable to uninstall the startup script.
	pause
	exit /B 1
)
: call is necessary to force evaluation of things like %USERPROFILE% within %StartupDir%
call set StartupDir=%StartupDir%

if exist "%StartupDir%\watcher-vlc.lnk" del /q "%StartupDir%\watcher-vlc.lnk"

echo Uninstalled startup script (that made the watcher automatically run at startup) successfully.
pause