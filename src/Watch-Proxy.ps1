#Requires -Version 5.1
<#
.SYNOPSIS
    常驻监视：每隔一段时间检查一次系统代理，发现"客户端崩溃留下的死代理"就自动清理。

.DESCRIPTION
    Reset-Proxy.ps1 负责"检查并修复一次"，本脚本把它变成循环执行的常驻监视，
    这样不只是开机时能自愈，客户端在开机状态下崩溃 / 被任务管理器结束 / 更新重启时，
    也能自动恢复上网（Reset-Proxy.ps1 的智能检测保证不会去动正在正常工作的代理）。

    监视开销极小：每个周期只做一次 TCP 连接探测（几十毫秒），没有网络请求。
    默认每 5 分钟检查一次。

.PARAMETER IntervalMinutes
    检查间隔（分钟），默认 5。可以给小数，例如 0.5 表示 30 秒，便于测试。

.PARAMETER Delay
    启动后先等 N 秒再开始第一轮检查。

.PARAMETER StopFile
    停止标记文件路径。该文件一旦出现，监视进程就会正常退出（默认 <脚本目录>\logs\watch.stop）。

    其余参数（-AutoDetect / -Force / -IncludeWinHttp / -FixDns / -FixMetric / -FixHosts / -RepairAll / -LogPath）
    原样透传给 Reset-Proxy.ps1。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Watch-Proxy.ps1 -IntervalMinutes 5 -Delay 20
#>
[CmdletBinding()]
param(
    [double]$IntervalMinutes = 5,
    [int]$Delay = 0,
    [string]$StopFile,
    [switch]$AutoDetect,
    [switch]$Force,
    [int]$ProxyPort = 0,
    [string]$SettingsPath,
    [switch]$IncludeWinHttp,
    [switch]$FixDns,
    [switch]$FixMetric,
    [switch]$FixHosts,
    [switch]$RepairAll,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'

$GuardScript = Join-Path $PSScriptRoot 'Reset-Proxy.ps1'
if (-not (Test-Path -LiteralPath $GuardScript)) {
    throw "找不到 Reset-Proxy.ps1（应与本脚本在同一目录）: $GuardScript"
}
if (-not $StopFile) { $StopFile = Join-Path $PSScriptRoot 'logs\watch.stop' }
if ($IntervalMinutes -lt 0.05) { $IntervalMinutes = 0.05 }
$IntervalSeconds = [int][Math]::Round($IntervalMinutes * 60)
if ($IntervalSeconds -lt 3) { $IntervalSeconds = 3 }

function Write-WatchLog {
    param([string]$Message)
    if (-not $LogPath) { return }
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $LogPath -Value ('{0} [WATCH] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
}

# 把参数按名字转交给 Reset-Proxy.ps1
# （注意：数组 splat 是"按位置"传参，会把 '-Quiet' 当成某个参数的值；命名参数必须用哈希表 splat）
# -Quiet 的含义：没事时不写日志，避免日志被心跳刷屏
$guardArgs = @{ Quiet = $true }
if ($AutoDetect)    { $guardArgs['AutoDetect']     = $true }
if ($Force)         { $guardArgs['Force']          = $true }
if ($IncludeWinHttp){ $guardArgs['IncludeWinHttp'] = $true }
if ($FixDns)        { $guardArgs['FixDns']         = $true }
if ($FixMetric)     { $guardArgs['FixMetric']      = $true }
if ($FixHosts)      { $guardArgs['FixHosts']       = $true }
if ($RepairAll)     { $guardArgs['RepairAll']      = $true }
if ($LogPath)       { $guardArgs['LogPath']        = $LogPath }
# 以下两个是进阶/测试用：正常安装不需要指定
if ($ProxyPort -gt 0) { $guardArgs['ProxyPort']    = $ProxyPort }
if ($SettingsPath)    { $guardArgs['SettingsPath'] = $SettingsPath }

if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }
Write-WatchLog ('监视已启动，每 {0} 秒检查一次' -f $IntervalSeconds)

while ($true) {
    if (Test-Path -LiteralPath $StopFile) {
        Write-WatchLog '发现停止标记文件，监视退出'
        Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
        break
    }
    try {
        $global:ProxyGuardChanged = $false
        & $GuardScript @guardArgs
        if ($global:ProxyGuardChanged) {
            Write-WatchLog '检测到死代理并已自动清理（详情见上方日志）'
        }
    } catch {
        Write-WatchLog ('本轮检查出错: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $IntervalSeconds
}

exit 0
