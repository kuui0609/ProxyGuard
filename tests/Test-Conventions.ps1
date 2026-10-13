#Requires -Version 5.1
<#
.SYNOPSIS
    规范检查：编码约定与语法。

.DESCRIPTION
    本项目有三条硬性编码约定，违反任何一条都会让脚本在 Windows PowerShell 5.1 下直接跑不起来：

      1. 所有 .ps1 必须保存为 UTF-8 with BOM
         （5.1 会把「无 BOM 的 UTF-8」按系统 ANSI 代码页解码 → 中文乱码 → 语法解析失败）
      2. 所有 .cmd / .bat 的内容必须是纯 ASCII
         （否则在非中文代码页的 Windows 上会显示乱码）
      3. 所有 .ps1 必须能通过语法解析

    注意：第 3 条只有在 **Windows PowerShell 5.1** 下运行本脚本才有完整意义
    （PowerShell 7 能解析 5.1 解析不了的 7.x 语法）。CI 里是用 `shell: powershell` 跑的。

    退出码 = 失败项数量（0 表示全部通过）。
#>
[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$script:Pass = 0
$script:Fail = 0

function Write-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) {
        $script:Pass++
        Write-Host ('  PASS  {0}' -f $Name) -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host ('  FAIL  {0}' -f $Name) -ForegroundColor Red
        if ($Detail) { Write-Host ('        {0}' -f $Detail) -ForegroundColor DarkYellow }
    }
}

function Test-HasBom {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Get-NonAsciiCount {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $n = 0
    foreach ($b in $bytes) { if ($b -gt 127) { $n++ } }
    return $n
}

Write-Host ''
Write-Host 'ProxyGuard 规范检查' -ForegroundColor Cyan
Write-Host ('  仓库根目录 : {0}' -f $RepoRoot)
Write-Host ('  PowerShell : {0} ({1})' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Host '  提示：当前不是 Windows PowerShell 5.1，语法检查无法覆盖 5.x 兼容性问题（CI 中会覆盖）' -ForegroundColor DarkYellow
}
Write-Host ''

$allFiles = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.git\\' }

$ps1List = @($allFiles | Where-Object { $_.Extension -eq '.ps1' })
$cmdList = @($allFiles | Where-Object { $_.Extension -in @('.cmd', '.bat') })

Write-Host ('--- 1) .ps1 必须是 UTF-8 with BOM（共 {0} 个）---' -f $ps1List.Count) -ForegroundColor Cyan
foreach ($f in $ps1List) {
    $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\')
    Write-Result ('BOM  {0}' -f $rel) (Test-HasBom $f.FullName) '缺少 UTF-8 BOM：Windows PowerShell 5.1 下会乱码并解析失败'
}

Write-Host ''
Write-Host ('--- 2) .cmd / .bat 必须是纯 ASCII（共 {0} 个）---' -f $cmdList.Count) -ForegroundColor Cyan
foreach ($f in $cmdList) {
    $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\')
    $n = Get-NonAsciiCount $f.FullName
    Write-Result ('ASCII {0}' -f $rel) ($n -eq 0) ('含 {0} 个非 ASCII 字节；请把注释和提示改成英文' -f $n)
}

Write-Host ''
Write-Host ('--- 3) .ps1 语法解析（共 {0} 个）---' -f $ps1List.Count) -ForegroundColor Cyan
foreach ($f in $ps1List) {
    $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\')
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    $ok = ($null -eq $errors -or $errors.Count -eq 0)
    $detail = ''
    if (-not $ok) {
        $detail = ($errors | Select-Object -First 3 | ForEach-Object { $_.Message }) -join ' | '
    }
    Write-Result ('PARSE {0}' -f $rel) $ok $detail
}

Write-Host ''
Write-Host '--- 4) 交付物完整性 ---' -ForegroundColor Cyan
foreach ($name in @('src\安装.cmd', 'src\卸载.cmd', 'src\一键体检.cmd', 'src\Reset-Proxy.ps1', 'src\Watch-Proxy.ps1', 'src\Install-ProxyGuard.ps1', 'README.md', 'LICENSE')) {
    $p = Join-Path $RepoRoot $name
    Write-Result ('存在  {0}' -f $name) (Test-Path -LiteralPath $p) '缺少文件会让"下载即用"和开源仓库不完整'
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ('  通过 {0}    失败 {1}' -f $script:Pass, $script:Fail)
Write-Host '========================================' -ForegroundColor Cyan

if ($script:Fail -gt 0) { exit $script:Fail }
exit 0
