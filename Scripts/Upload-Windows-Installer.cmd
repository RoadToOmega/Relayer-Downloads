@echo off
setlocal
where node >nul 2>nul
if %errorlevel% equ 0 (
  node "%~dp0ReleaseUpload.mjs" interactive --platform windows
) else if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" (
  "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" "%~dp0ReleaseUpload.mjs" interactive --platform windows
) else (
  echo Node.js 22 or newer is required. Install it from https://nodejs.org then try again.
)
echo.
pause
