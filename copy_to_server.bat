@echo off
set "DEST=\\192.168.1.84\smartbedv3"
echo Copying folders to %DEST%...

xcopy /E /I /Y reports "%DEST%\reports"
xcopy /E /I /Y docs "%DEST%\docs"
xcopy /E /I /Y plans "%DEST%\plans"
xcopy /E /I /Y firmware "%DEST%\firmware"
xcopy /E /I /Y edge "%DEST%\edge"
xcopy /E /I /Y app "%DEST%\app"

echo.
echo All done!
pause
