@echo off
title Amazing Church - Autostart
cd /d D:\Test\amazing-church

echo Waiting for Docker Desktop...
:waitdocker
docker ps >nul 2>&1
if errorlevel 1 (
    timeout /t 3 /nobreak >nul
    goto waitdocker
)
echo Docker ready.

echo Ensuring Supabase stack up...
docker ps --filter "name=supabase_kong_amazing-church" --format "{{.Names}}" | findstr /I "supabase_kong_amazing-church" >nul
if errorlevel 1 (
    echo Starting Supabase (may take a minute)...
    call npx supabase start
) else (
    echo Supabase container present, verifying health...
)

echo Waiting for Supabase Kong to answer on 54321...
:waitkong
curl -s -o nul -w "%%{http_code}" http://127.0.0.1:54321/auth/v1/health | findstr /B "200" >nul
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto waitkong
)
echo Supabase ready.

echo Starting ngrok tunnel (static domain)...
start "ngrok - supabase" cmd /k ngrok http --url=boastful-humbly-preheated.ngrok-free.dev 54321

echo Starting Next.js dev server...
start "next dev" cmd /k npm run dev

echo.
echo All services launched.
echo   Local:  http://localhost:3000
echo   Ngrok:  https://boastful-humbly-preheated.ngrok-free.dev
echo.
timeout /t 8 /nobreak >nul
