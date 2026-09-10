@echo off
cd /d E:\Project\unimatchGasabo

echo.
set /p MSG="Commit message: "
if "%MSG%"=="" (
  echo No message entered. Aborting.
  pause
  exit /b 1
)

git add -A
git commit -m "%MSG%"
git push origin main

if %ERRORLEVEL%==0 (
  echo.
  echo Pushed! Netlify + Railway are deploying now.
  echo Watch: https://github.com/Kristefo24/uniMatch/actions
) else (
  echo.
  echo Push failed. Check your connection and try again.
)

pause
