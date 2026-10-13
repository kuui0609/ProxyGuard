#Requires -Version 5.1
<#
.SYNOPSIS
    打包出可发布的 zip（用于 GitHub Release 附件）。

.DESCRIPTION
    只把「使用者真正需要的文件」放进包里：
      LICENSE、README.md、README.en.md、CHANGELOG.md、
      三个 .ps1、三个 .cmd 启动器。
    tests/、tools/、.github/ 这些开发用的东西不会进包 —— 这样别人下载解压后
    就是"双击 安装.cmd"的干净结构。

.PARAMETER Version
    版本号，会出现在文件名里，例如 1.0.0 / v1.0.0。默认 dev。
    传入 'v1.0.0' 时会自动去掉前缀 v。

.PARAMETER OutputDir
    输出目录，默认 <仓库根>\dist。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 -Version 1.0.0
#>
[CmdletBinding()]
param(
    [string]$Version = 'dev',
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $RepoRoot 'dist' }

$cleanVersion = $Version.TrimStart('v', 'V')
$zipName = 'ProxyGuard-{0}.zip' -f $cleanVersion
$zipPath = Join-Path $OutputDir $zipName

$payload = @(
    'LICENSE',
    'README.md',
    'README.en.md',
    'CHANGELOG.md',
    'Reset-Proxy.ps1',
    'Watch-Proxy.ps1',
    'Install-ProxyGuard.ps1',
    '安装.cmd',
    '卸载.cmd',
    '一键体检.cmd'
)

Write-Host ''
Write-Host 'ProxyGuard 打包' -ForegroundColor Cyan
Write-Host ('  版本     : {0}' -f $cleanVersion)
Write-Host ('  输出     : {0}' -f $zipPath)

$missing = @()
foreach ($name in $payload) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $name))) { $missing += $name }
}
if ($missing.Count -gt 0) {
    throw ('以下文件缺失，无法打包：{0}' -f ($missing -join ', '))
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

# 先复制到临时目录再压缩，保证包内是扁平结构
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('proxyguard-pack-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
    foreach ($name in $payload) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination (Join-Path $staging $name) -Force
        Write-Host ('  + {0}' -f $name)
    }

    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

$item = Get-Item -LiteralPath $zipPath
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash

Write-Host ''
Write-Host ('  完成: {0}  ({1:N0} 字节)' -f $item.Name, $item.Length) -ForegroundColor Green
Write-Host ('  SHA256: {0}' -f $hash)
Write-Host ''
Write-Host '  下一步：把这个 zip 作为附件上传到 GitHub Release。' -ForegroundColor Cyan
Write-Host '  （打 v* 标签推送时，.github/workflows/release.yml 会自动完成这一步）'
