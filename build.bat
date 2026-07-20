@echo off
setlocal
cd /d "%~dp0"

echo.
echo PalworldEasyCheats - v1.0 - ModularRex
echo Nuitka standalone build
echo.

set "PKG=release\PalworldEasyCheats"
set "ZIP=release\PalworldEasyCheats.zip"

if exist "%PKG%" (
  echo Removing existing %PKG%\ folder...
  rmdir /s /q "%PKG%"
)
if exist "%ZIP%" del /q "%ZIP%"

py -m nuitka --standalone ^
  --output-filename=PalworldEasyCheats ^
  --output-dir=dist ^
  --product-name=PalworldEasyCheats ^
  --windows-company-name="ModularRex" ^
  --file-version=1.0 ^
  --product-version=1.0 ^
  --windows-icon-from-ico=icon.ico ^
  --windows-console-mode=disable ^
  --enable-plugin=pyside6 ^
  PalworldEasyCheats.py
if errorlevel 1 (
  echo.
  echo Build failed.
  exit /b 1
)

echo.
echo Packaging release folder...

set "DIST=dist\PalworldEasyCheats.dist"

if not exist "%DIST%\PalworldEasyCheats.exe" (
  echo.
  echo Build output not found: %DIST%\PalworldEasyCheats.exe
  exit /b 1
)

mkdir "%PKG%\gui"
mkdir "%PKG%\scripts"

echo Copying dist -^> %PKG%\gui\
xcopy /e /i /y /q "%DIST%\*" "%PKG%\gui\" >nul
if errorlevel 1 (
  echo Failed to copy dist files.
  exit /b 1
)

echo Copying scripts -^> %PKG%\scripts\ (excluding settings.json)
xcopy /e /i /y /q "scripts\*" "%PKG%\scripts\" >nul
if errorlevel 1 (
  echo Failed to copy scripts folder.
  exit /b 1
)
if exist "%PKG%\scripts\settings.json" del /q "%PKG%\scripts\settings.json"

echo Copying readme.txt
copy /y "package\readme.txt" "%PKG%\readme.txt" >nul
if errorlevel 1 (
  echo Failed to copy package\readme.txt.
  exit /b 1
)

echo Copying PalworldEasyCheats.bat
copy /y "package\PalworldEasyCheats.bat" "%PKG%\PalworldEasyCheats.bat" >nul
if errorlevel 1 (
  echo Failed to copy package\PalworldEasyCheats.bat.
  exit /b 1
)

echo.
where powershell >nul 2>&1
if not errorlevel 1 (
  echo Creating %ZIP%...
  powershell -NoProfile -Command "Compress-Archive -Path 'release\PalworldEasyCheats' -DestinationPath 'release\PalworldEasyCheats.zip' -Force"
  if errorlevel 1 (
    echo Zip failed.
  ) else (
    echo Created %ZIP%
  )
) else (
  echo PowerShell not found; skipping zip.
)

echo.
echo Build complete.
echo   %PKG%\gui\PalworldEasyCheats.exe
echo   %PKG%\scripts\
echo   %PKG%\readme.txt
echo   %PKG%\PalworldEasyCheats.bat
if exist "%ZIP%" echo   %ZIP%
endlocal
