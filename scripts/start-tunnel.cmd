@echo off
REM Amazing Church — auto-start wrapper.
REM Waits for Docker Desktop, brings up Supabase, then holds the ngrok tunnel open.
REM Registered to run at every sign-in by scripts\install-autostart.ps1.

setlocal EnableDelayedExpansion

set "LOG_DIR=%LOCALAPPDATA%\amazing-church"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "LOG=%LOG_DIR%\tunnel.log"

set "PROJECT_DIR=D:\Test\amazing-church"
set "NGROK=%LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe"
set "DOMAIN=boastful-humbly-preheated.ngrok-free.dev"
set "SUPABASE_PORT=54321"

echo. >> "%LOG%"
echo ==== %DATE% %TIME% ==== >> "%LOG%"
echo Starting autostart wrapper >> "%LOG%"

REM 1) Wait for Docker Desktop to be ready (up to 10 min).
echo Waiting for Docker... >> "%LOG%"
for /L %%i in (1,1,60) do (
  docker info >nul 2>&1
  if !errorlevel! == 0 goto docker_ready
  timeout /t 10 /nobreak >nul
)
echo Docker never came up. Exiting. >> "%LOG%"
exit /b 1

:docker_ready
echo Docker is ready. >> "%LOG%"

REM 2) Ensure Supabase stack is running (idempotent).
pushd "%PROJECT_DIR%"
echo Running "npx supabase start"... >> "%LOG%"
call npx --yes supabase start >> "%LOG%" 2>&1
popd

REM 3) Wait for port 54321 to accept requests.
echo Waiting for Supabase API on port %SUPABASE_PORT%... >> "%LOG%"
for /L %%i in (1,1,60) do (
  powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:%SUPABASE_PORT%/' -TimeoutSec 3 -UseBasicParsing; exit 0 } catch { if ($_.Exception.Response) { exit 0 } else { exit 1 } }" >nul 2>&1
  if !errorlevel! == 0 goto supabase_ready
  timeout /t 3 /nobreak >nul
)
echo Supabase API never opened. Continuing anyway. >> "%LOG%"

:supabase_ready
echo Supabase reachable. Launching ngrok... >> "%LOG%"

REM 4) Keep ngrok alive. If it crashes, this script exits and Task Scheduler restarts it.
"%NGROK%" http --url=%DOMAIN% %SUPABASE_PORT% --log=stdout >> "%LOG%" 2>&1

echo ngrok exited at %TIME% >> "%LOG%"
exit /b 1
