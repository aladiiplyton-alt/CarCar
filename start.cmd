@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
powershell.exe -NoProfile -Command "$r='aladiiplyton-alt/CarCar'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $b=(Invoke-WebRequest -UseBasicParsing ('https://github.com/'+$r+'/releases/download/v1.0.0/bootstrap.ps1?carcar='+[guid]::NewGuid())).Content; if($b -is [string]){$b=[Text.Encoding]::UTF8.GetBytes($b)}; $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b)).Replace('-',''); if($h -ne 'c0b16ded3904adc4b1386578ca94d31979efe875274f40b6a9c6400c527b1527'){throw 'Bootstrap SHA256 mismatch'}; & ([scriptblock]::Create([Text.Encoding]::UTF8.GetString($b))) -Repository $r"
set "CARCAR_RESULT=%ERRORLEVEL%"
if not "%CARCAR_RESULT%"=="0" echo CarCar: запуск не выполнен. Проверьте сообщение выше.
rem Delete only the temporary copy created by the documented CMD command.
rem A saved or repository copy of start.cmd is retained.
for %%I in ("%TEMP%\.") do set "CARCAR_TEMP=%%~fI\"
if /i not "%~dp0"=="%CARCAR_TEMP%" exit /b %CARCAR_RESULT%
if /i not "%~nx0"=="carcar-start.cmd" exit /b %CARCAR_RESULT%
endlocal & del /q "%~f0" & exit /b %CARCAR_RESULT%
