@echo off
REM Starts the persistent ngrok tunnel from your reserved domain to local Supabase (port 54321).
REM Run manually with: scripts\start-tunnel.cmd
REM Or install as an auto-start task via scripts\install-autostart.ps1
REM
REM Logs go to %LOCALAPPDATA%\amazing-church\tunnel.log

setlocal
set NGROK_EXE=C:\Users\%USERNAME%\AppData\Local\Microsoft\WinGet\Links\ngrok.exe
set LOG_DIR=%LOCALAPPDATA%\amazing-church
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM Kill any stale ngrok processes so we don't fight for the reserved domain
taskkill /IM ngrok.exe /F >nul 2>&1

echo [%date% %time%] Starting ngrok tunnel to 127.0.0.1:54321 >> "%LOG_DIR%\tunnel.log"
"%NGROK_EXE%" http --url=boastful-humbly-preheated.ngrok-free.dev 54321 --log=stdout --log-format=logfmt >> "%LOG_DIR%\tunnel.log" 2>&1
