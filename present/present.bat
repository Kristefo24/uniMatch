@echo off
setlocal
title UniMatch - presenter

rem One-click demo of UniMatch on a PC: serves the local web build and opens it
rem full screen in a phone frame, with no tabs, address bar or DevTools.
rem Needs no Android Studio, no emulator and no Netlify.

set "ROOT=%~dp0.."
set "WEB=%ROOT%\app\build\web"
set "PORT=8000"

if not exist "%WEB%\index.html" (
  echo.
  echo   The web build is missing.
  echo.
  echo   Build it once with:
  echo       cd /d "%ROOT%\app"
  echo       flutter build web --release
  echo.
  pause
  exit /b 1
)

rem The frame has to sit INSIDE the build so it is the same origin as the app --
rem a page cannot put a cross-origin Flutter build in an iframe. Copied on every
rem launch so a rebuild never leaves a stale copy behind.
copy /y "%~dp0frame.html" "%WEB%\present.html" >nul

rem Find a browser. Chrome first; Edge is on every Windows 11 machine as backup.
set "BROWSER="
for %%P in (
  "%ProgramFiles%\Google\Chrome\Application\chrome.exe"
  "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
  "%LocalAppData%\Google\Chrome\Application\chrome.exe"
  "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
  "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
) do if not defined BROWSER if exist %%P set "BROWSER=%%~P"

if not defined BROWSER (
  echo   Could not find Chrome or Edge. Open this manually instead:
  echo       http://localhost:%PORT%/present.html
)

rem Serve only the build folder, never the repo root -- that keeps server\.env
rem off the HTTP server even on localhost.
echo   Serving %WEB% on port %PORT% ...
start "UniMatch server" /min cmd /c python -m http.server %PORT% --directory "%WEB%"

rem Give the server a moment before the browser asks for the page.
ping -n 3 127.0.0.1 >nul

if defined BROWSER (
  echo   Opening the presenter view. Press Alt+F4 to finish.
  rem A separate profile keeps your own tabs, extensions and bookmarks bar out
  rem of the demo, and guarantees kiosk mode starts clean.
  "%BROWSER%" --kiosk "http://localhost:%PORT%/present.html" ^
    --user-data-dir="%TEMP%\unimatch-present" --no-first-run --no-default-browser-check
)

rem Control returns here when the browser window closes, so the server stops
rem with it rather than being left running on port %PORT%.
echo   Closing the server ...
taskkill /f /fi "WINDOWTITLE eq UniMatch server*" >nul 2>&1
endlocal
