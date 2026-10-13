@echo off
setlocal
rem ============================================================
rem  ProxyGuard - network health check only (makes NO changes)
rem
rem  Checks: user proxy, PAC, auto-detect, computer-wide proxy,
rem  WinHTTP proxy, adapter DNS, default routes / virtual
rem  adapters, hosts file, current privileges.
rem  This file itself is intentionally plain ASCII only.
rem ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; Get-ChildItem -LiteralPath '%~dp0.' -Filter '*.ps1' | ForEach-Object { $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8; if ($null -ne $t) { [System.IO.File]::WriteAllText($_.FullName, $t, (New-Object System.Text.UTF8Encoding($true))) } }"

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Reset-Proxy.ps1" -DryRun %*

echo.
echo Check finished. Press any key to close.
pause >nul
