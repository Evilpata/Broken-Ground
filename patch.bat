@echo off
chcp 65001 >nul 2>&1
title Broken Ground Patch

echo.
echo  =============================================
echo   BROKEN GROUND - LOCAL MULTIPLAYER PATCH
echo  =============================================
echo.
echo  Yama baslatiliyor...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  HATA: Patch tamamlanamadi!
    echo  patch.ps1 ile ayni klasorde oldugunuzu kontrol edin.
    echo.
    pause
)
