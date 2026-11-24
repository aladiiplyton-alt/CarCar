@echo off
setlocal
chcp 65001 >nul
if not exist "%~dp0carcar-launcher.exe" (
  echo CarCar: рядом с carcar.cmd должен находиться carcar-launcher.exe.
  exit /b 1
)
"%~dp0carcar-launcher.exe" %*
exit /b %errorlevel%
