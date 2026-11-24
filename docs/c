@echo off
setlocal EnableExtensions DisableDelayedExpansion
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $r='aladiiplyton-alt/CarCar'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; for($i=0;$i -lt 3;$i++){try{$b=(Invoke-WebRequest -UseBasicParsing -TimeoutSec 40 ('https://github.com/'+$r+'/releases/download/v1.0.0/bootstrap-profile-c8dbc631e019d86e.ps1?carcar='+[guid]::NewGuid())).Content; if($b -is [string]){$b=[Text.Encoding]::UTF8.GetBytes($b)}; $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b)).Replace('-',''); if($h -ne 'c8dbc631e019d86edc1e2d4b18a1e521f922ef210862eb4f87c3a4cd0038551c'){throw 'Bootstrap SHA256 mismatch'}; break}catch{if($i -eq 2){throw}; Write-Host 'CarCar: retrying the startup download...'; Start-Sleep -Seconds 2}}; & ([scriptblock]::Create([Text.Encoding]::UTF8.GetString($b))) -Repository $r"
set "CARCAR_RESULT=%ERRORLEVEL%"
if not "%CARCAR_RESULT%"=="0" echo CarCar: startup failed. See the error above.
rem Delete only the temporary copy created by the documented CMD command.
rem A saved or repository copy of start.cmd is retained.
for %%I in ("%TEMP%\.") do set "CARCAR_TEMP=%%~fI\"
if /i not "%~dp0"=="%CARCAR_TEMP%" exit /b %CARCAR_RESULT%
if /i not "%~nx0"=="carcar-start.cmd" if /i not "%~nx0"=="cc.cmd" exit /b %CARCAR_RESULT%
rem Release the batch context before deleting this file; retain the caller's CMD.
endlocal & (goto) 2>nul & del /q "%~f0" & cmd /d /c exit /b %CARCAR_RESULT%
