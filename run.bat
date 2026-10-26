@echo off
setlocal
title WinDebloat Tool (Windows 10 / 11)
cd /d "%~dp0"

rem Entry script (WinDebloatTool.ps1, or its alias Win11DebloatTool.ps1)
set "W11D_PS1=%~dp0WinDebloatTool.ps1"
if not exist "%W11D_PS1%" set "W11D_PS1=%~dp0Win11DebloatTool.ps1"

rem Prefer 64-bit PowerShell when launched from a 32-bit process
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" (
  echo PowerShell not found. Windows 7 SP1 or newer is required.
  echo Khong tim thay PowerShell. Can Windows 7 SP1 tro len.
  pause
  exit /b 1
)

rem Self-elevate: "net session" only succeeds for administrators
"%SystemRoot%\System32\net.exe" session >nul 2>&1
if errorlevel 1 goto :elevate

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%W11D_PS1%" %*
if errorlevel 1 pause
endlocal
exit /b

:elevate
echo Requesting administrator rights... / Dang xin quyen Administrator...
set "W11D_ARGS=%*"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$a = $env:W11D_ARGS; if ($a) { Start-Process -FilePath '%~f0' -ArgumentList $a -Verb RunAs } else { Start-Process -FilePath '%~f0' -Verb RunAs }"
endlocal
exit /b
