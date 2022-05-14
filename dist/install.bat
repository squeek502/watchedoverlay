@echo off

: watched

regsvr32 /s "%~dp0\watched.dll"
if NOT %errorlevel% == 0 (
	if %errorlevel% == 5 (
		echo Failed to install shell extension (access denied^). Make sure to run this script as administrator.
		pause
		exit /B %errorlevel%
	)
	echo Failed to install shell extension, exit code was %errorlevel%
	pause
	exit /B %errorlevel%
)
echo Installed shell extension successfully.
echo You must restart explorer.exe for the changes to take effect.

: watcher

FOR /f "tokens=1,2*" %%E in ('reg query "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"') DO (
	IF "%%E"=="Startup" (
		set StartupDir=%%G
	)
)
IF "%StartupDir%"=="" (
	echo Not able to determine Startup directory path, unable to make the watcher automatically run at startup.
	pause
	exit /B 1
)
: call is necessary to force evaluation of things like %USERPROFILE% within %StartupDir%
call set StartupDir=%StartupDir%

set SCRIPT="%TEMP%\%RANDOM%-%RANDOM%-%RANDOM%-%RANDOM%.vbs"

echo Set oWS = WScript.CreateObject("WScript.Shell") >> %SCRIPT%
echo sLinkFile = "%StartupDir%\watcher-vlc.lnk" >> %SCRIPT%
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> %SCRIPT%
echo oLink.TargetPath = "%~dp0\watcher-vlc-background.vbs" >> %SCRIPT%
echo oLink.WorkingDirectory = "%~dp0" >> %SCRIPT%
echo oLink.Save >> %SCRIPT%

cscript /nologo %SCRIPT%
del /q %SCRIPT%

echo Installed startup script (to make the watcher automatically run at startup) successfully.

tskill watcher-vlc 2>nul
"%StartupDir%\watcher-vlc.lnk"
echo Started watcher-vlc in the background.
pause