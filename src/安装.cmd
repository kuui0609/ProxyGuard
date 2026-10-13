@echo off
setlocal
rem ============================================================
rem  ProxyGuard - install (no administrator rights required)
rem
rem  Double-click this file.
rem  It first normalizes the .ps1 files to UTF-8 WITH BOM:
rem  Windows PowerShell 5.1 decodes BOM-less UTF-8 as ANSI, which
rem  turns non-ASCII text into mojibake and breaks script parsing.
rem  This file itself is intentionally plain ASCII only.
rem ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; Get-ChildItem -LiteralPath '%~dp0.' -Filter '*.ps1' | ForEach-Object { $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8; if ($null -ne $t) { [System.IO.File]::WriteAllText($_.FullName, $t, (New-Object System.Text.UTF8Encoding($true))) } }"

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Install-ProxyGuard.ps1" -DesktopShortcut %*

echo.
echo Install finished. Press any key to close.
pause >nul
