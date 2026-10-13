@echo off
setlocal
rem ============================================================
rem  ProxyGuard - uninstall
rem
rem  Double-click this file to remove ProxyGuard completely:
rem  stops the watcher, deletes the scheduled task, the startup
rem  entry, the desktop shortcut and the install folder.
rem  This file itself is intentionally plain ASCII only.
rem ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; Get-ChildItem -LiteralPath '%~dp0.' -Filter '*.ps1' | ForEach-Object { $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8; if ($null -ne $t) { [System.IO.File]::WriteAllText($_.FullName, $t, (New-Object System.Text.UTF8Encoding($true))) } }"

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Install-ProxyGuard.ps1" -Uninstall %*

echo.
echo Uninstall finished. Press any key to close.
pause >nul
