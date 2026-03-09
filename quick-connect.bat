@echo off
chcp 65001 >nul 2>&1
title DNS Tunnel - Quick Connect

REM ============================================================
REM  QUICK CONNECT - Edit these 3 values before sharing
REM ============================================================
set "DOMAIN=CHANGE_ME_t.example.com"
set "PUBKEY=CHANGE_ME_64_char_hex_public_key"
set "LOCAL_PORT=7000"
REM ============================================================

echo.
echo  =========================================
echo   DNS Tunnel - Quick Connect
echo   Trying DoH (HTTPS) transport...
echo  =========================================
echo.

REM Check if domain was configured
if "%DOMAIN%"=="CHANGE_ME_t.example.com" (
    echo  [ERROR] This script needs to be configured first!
    echo.
    echo  Open this file in Notepad and change:
    echo    DOMAIN = your tunnel domain
    echo    PUBKEY = your server public key
    echo.
    pause
    exit /b 1
)

REM Check for dnstt-client binary
set "CLIENT="
if exist "%~dp0dnstt-client-windows-amd64.exe" (
    set "CLIENT=%~dp0dnstt-client-windows-amd64.exe"
) else if exist "%~dp0dnstt-client.exe" (
    set "CLIENT=%~dp0dnstt-client.exe"
) else (
    echo  [ERROR] dnstt-client not found!
    echo.
    echo  Download from: https://dnstt.network
    echo  Place dnstt-client-windows-amd64.exe in the same folder as this script.
    echo.
    pause
    exit /b 1
)

REM Write public key file
echo %PUBKEY%> "%~dp0server.pub"

echo  Domain:  %DOMAIN%
echo  Client:  %CLIENT%
echo  Port:    127.0.0.1:%LOCAL_PORT%
echo.

:menu
echo  Choose resolver (DoH = HTTPS, hardest to block):
echo.
echo    1) DoH - Google       (recommended, try first)
echo    2) DoH - Cloudflare   (if Google fails)
echo    3) DoH - Quad9
echo    4) DoH - AdGuard
echo    5) DoT - Google       (TLS port 853)
echo    6) UDP - Google       (old method, often blocked)
echo    7) UDP - Cloudflare   (old method, often blocked)
echo.
set /p RESOLVER_CHOICE="  Choose [1]: "
if "%RESOLVER_CHOICE%"=="" set "RESOLVER_CHOICE=1"

set "TRANSPORT="
set "RESOLVER="

if "%RESOLVER_CHOICE%"=="1" set "TRANSPORT=-doh" & set "RESOLVER=https://dns.google/dns-query"
if "%RESOLVER_CHOICE%"=="2" set "TRANSPORT=-doh" & set "RESOLVER=https://cloudflare-dns.com/dns-query"
if "%RESOLVER_CHOICE%"=="3" set "TRANSPORT=-doh" & set "RESOLVER=https://dns.quad9.net/dns-query"
if "%RESOLVER_CHOICE%"=="4" set "TRANSPORT=-doh" & set "RESOLVER=https://dns.adguard-dns.com/dns-query"
if "%RESOLVER_CHOICE%"=="5" set "TRANSPORT=-dot" & set "RESOLVER=dns.google:853"
if "%RESOLVER_CHOICE%"=="6" set "TRANSPORT=-udp" & set "RESOLVER=8.8.8.8:53"
if "%RESOLVER_CHOICE%"=="7" set "TRANSPORT=-udp" & set "RESOLVER=1.1.1.1:53"

if "%TRANSPORT%"=="" (
    echo  Invalid choice. Try again.
    goto :menu
)

echo.
echo  =========================================
echo   Connecting with %TRANSPORT% %RESOLVER%
echo  =========================================
echo.
echo  Once connected, set your browser proxy:
echo    Type: SOCKS5
echo    Host: 127.0.0.1
echo    Port: %LOCAL_PORT%
echo.
echo  If it fails immediately, close this window
echo  and run again with a different resolver.
echo.
echo  Press Ctrl+C to disconnect.
echo  -----------------------------------------
echo.

"%CLIENT%" %TRANSPORT% %RESOLVER% -pubkey-file "%~dp0server.pub" %DOMAIN% 127.0.0.1:%LOCAL_PORT%

echo.
echo  Connection ended (exit code: %ERRORLEVEL%).
echo.
echo  If it failed, try a different resolver.
echo.
set /p RETRY="  Try another resolver? [Y/n]: "
if /i "%RETRY%"=="n" exit /b 0
goto :menu
