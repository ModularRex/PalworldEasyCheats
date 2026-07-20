@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0gui\PalworldEasyCheats.exe" (
  echo.
  echo  Could not find gui\PalworldEasyCheats.exe
  echo  Keep this file inside the PalworldEasyCheats mod folder.
  echo.
  pause
  exit /b 1
)

start "" "%~dp0gui\PalworldEasyCheats.exe"
endlocal
