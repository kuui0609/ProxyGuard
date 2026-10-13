#Requires -Version 5.1
<#
.SYNOPSIS
    行为测试：在「影子注册表项」上跑完整的判定矩阵。

.DESCRIPTION
    本测试**完全不依赖真实环境**，也**绝不会改动使用者真实的代理设置**：

      * 所有读写都发生在 HKCU\Software\ProxyGuardTest\Net 这个临时注册表项里（跑完自动删除）；
      * "活代理"由测试自己开的一个本地 TCP 监听端口扮演；
      * "死代理"用一个确定没人监听的端口。

    这样在任何机器、任何 CI 上都能稳定复现，包括那些没有装加速器/VPN 的环境。

    退出码 = 失败用例数（0 表示全部通过）。

.PARAMETER GuardPath
    被测脚本路径，默认 <仓库根>\Reset-Proxy.ps1。

.PARAMETER KeepTemp
    保留临时注册表项和日志，方便排查。
#>
[CmdletBinding()]
param(
    [string]$GuardPath,
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $GuardPath) { $GuardPath = Join-Path $RepoRoot 'Reset-Proxy.ps1' }

if (-not (Test-Path -LiteralPath $GuardPath)) { throw "找不到被测脚本: $GuardPath" }

# 用「用户实际运行脚本的方式」来测：优先用 Windows PowerShell 5.1
$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $PsExe)) { $PsExe = (Get-Process -Id $PID).Path }

$ShadowRoot = 'HKCU:\Software\ProxyGuardTest'
$ShadowPath = Join-Path $ShadowRoot 'Net'
$ConnPath   = Join-Path $ShadowPath 'Connections'
$BlobName   = 'DefaultConnectionSettings'
$BlobTailLength = 40

$script:Pass = 0
$script:Fail = 0

function Write-Case {
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

function Get-ClosedPort {
    # 找一个确定没人监听的端口
    for ($i = 0; $i -lt 40; $i++) {
        $port = Get-Random -Minimum 20000 -Maximum 60000
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $client.Connect('127.0.0.1', $port)
            $client.Close()
        } catch {
            try { $client.Close() } catch { }
            return $port
        } finally {
            try { $client.Close() } catch { }
        }
    }
    return 19999
}

function Reset-Shadow {
    param(
        [int]$ProxyEnable = 0,
        [string]$ProxyServer = '',
        [string]$AutoConfigURL = '',
        [int]$AutoDetect = 0,
        [int]$Flags = 0x0B
    )
    Remove-Item -LiteralPath $ShadowRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $ConnPath -Force | Out-Null

    $blob = [byte[]]::new($BlobTailLength)
    $blob[0] = 0x46
    $blob[4] = 0x10                              # 变更计数器 = 16
    $blob[8] = [byte]($Flags -band 0xFF)
    $blob[9] = [byte](($Flags -shr 8) -band 0xFF)
    for ($i = 12; $i -lt $BlobTailLength; $i++) { $blob[$i] = [byte](($i * 7) % 251) }

    New-ItemProperty -Path $ConnPath -Name $BlobName -Value $blob -Type Binary -Force | Out-Null
    New-ItemProperty -Path $ShadowPath -Name 'ProxyEnable' -Value $ProxyEnable -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ShadowPath -Name 'ProxyServer' -Value $ProxyServer -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ShadowPath -Name 'AutoConfigURL' -Value $AutoConfigURL -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ShadowPath -Name 'AutoDetect' -Value $AutoDetect -PropertyType DWord -Force | Out-Null
}

function Get-ShadowState {
    $key = Get-ItemProperty -Path $ShadowPath
    $blob = (Get-ItemProperty -Path $ConnPath -Name $BlobName).$BlobName
    $counter = [int]$blob[4] + ([int]$blob[5] -shl 8) + ([int]$blob[6] -shl 16) + ([int]$blob[7] -shl 24)
    $flags = [int]$blob[8] + ([int]$blob[9] -shl 8)
    $tailIntact = $true
    for ($i = 12; $i -lt $blob.Length; $i++) {
        if ($blob[$i] -ne [byte](($i * 7) % 251)) { $tailIntact = $false }
    }
    [pscustomobject]@{
        ProxyEnable   = [int]$key.ProxyEnable
        ProxyServer   = [string]$key.ProxyServer
        AutoConfigURL = [string]$key.AutoConfigURL
        AutoDetect    = [int]$key.AutoDetect
        Flags         = $flags
        Counter       = $counter
        Length        = $blob.Length
        TailIntact    = $tailIntact
        BlobPresent   = ($null -ne $blob)
    }
}

function Invoke-Guard {
    param([string[]]$ExtraArgs = @(), [string]$LogPath)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $GuardPath,
                 '-SettingsPath', $ShadowPath, '-LogPath', $LogPath) + $ExtraArgs
    $output = & $PsExe @argList 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Text     = ($output | Out-String)
    }
}

function Read-Log {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw) }
    return ''
}

# ---------------------------------------------------------------- 准备

Write-Host ''
Write-Host 'ProxyGuard 行为测试' -ForegroundColor Cyan
Write-Host ('  被测脚本 : {0}' -f $GuardPath)
Write-Host ('  PowerShell: {0}' -f $PsExe)
Write-Host ('  临时注册表项: {0}' -f $ShadowPath)
Write-Host ''

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$livePort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$deadPort = Get-ClosedPort
$liveUrl  = '127.0.0.1:{0}' -f $livePort
$deadUrl  = '127.0.0.1:{0}' -f $deadPort
$liveUrl2 = 'http://127.0.0.1:{0}' -f $livePort
$deadUrl2 = 'http://127.0.0.1:{0}' -f $deadPort
Write-Host ('  活代理端口 : {0}（测试自己开的监听）' -f $livePort)
Write-Host ('  死代理端口 : {0}（确定没人监听）' -f $deadPort)
Write-Host ''

$log = Join-Path $env:TEMP ('proxyguard-test-{0}.log' -f ([guid]::NewGuid().ToString('N')))

try {
    # ------------------------------------------------------------ 用例
    Write-Host '--- 智能检测：端口活着时必须完全不动 ---' -ForegroundColor Cyan

    Reset-Shadow -ProxyEnable 1 -ProxyServer $liveUrl -Flags 0x0B
    $before = Get-ShadowState
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '活代理(host:port) -> 跳过，不修改任何东西' `
        ($after.ProxyEnable -eq 1 -and $after.Counter -eq $before.Counter -and $after.Flags -eq 0x0B -and $r.ExitCode -eq 0) `
        ('ProxyEnable={0} counter {1}->{2} flags={3:X2} exit={4}' -f $after.ProxyEnable, $before.Counter, $after.Counter, $after.Flags, $r.ExitCode)

    Reset-Shadow -ProxyEnable 1 -ProxyServer $liveUrl2 -Flags 0x0B
    $before = Get-ShadowState
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '活代理(http:// 前缀) -> 跳过（回归用例）' `
        ($after.ProxyEnable -eq 1 -and $after.Counter -eq $before.Counter) `
        ('ProxyEnable={0} counter {1}->{2}' -f $after.ProxyEnable, $before.Counter, $after.Counter)
    Write-Case '活代理 -> 日志里应出现"跳过清理"' `
        ((Read-Log $log) -match '跳过清理') ''

    Write-Host ''
    Write-Host '--- 死代理：必须恢复直连 ---' -ForegroundColor Cyan

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl -Flags 0x0B -AutoDetect 0
    $before = Get-ShadowState
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '死代理(host:port) -> 关闭代理' ($after.ProxyEnable -eq 0) ('ProxyEnable={0}' -f $after.ProxyEnable)
    Write-Case '死代理 -> blob 标志变为 0x01(DIRECT)' ($after.Flags -eq 0x01) ('flags={0:X2}' -f $after.Flags)
    Write-Case '死代理 -> 变更计数器 +1' ($after.Counter -eq ($before.Counter + 1)) ('{0}->{1}' -f $before.Counter, $after.Counter)
    Write-Case '死代理 -> blob 长度与其余字节原样保留' ($after.TailIntact -and $after.Length -eq $before.Length) `
        ('tailIntact={0} len {1}->{2}' -f $after.TailIntact, $before.Length, $after.Length)
    Write-Case '死代理 -> 退出码为 0' ($r.ExitCode -eq 0) ('exit={0}' -f $r.ExitCode)

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl2 -Flags 0x0B
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '死代理(http:// 前缀) -> 关闭代理' ($after.ProxyEnable -eq 0) ('ProxyEnable={0}' -f $after.ProxyEnable)

    Reset-Shadow -ProxyEnable 1 -ProxyServer ('http={0};https={0}' -f $deadUrl) -Flags 0x0B
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '死代理(复合写法 http=;https=) -> 关闭代理' ($after.ProxyEnable -eq 0) ('ProxyEnable={0}' -f $after.ProxyEnable)

    Write-Host ''
    Write-Host '--- 本地 PAC ---' -ForegroundColor Cyan

    Reset-Shadow -ProxyEnable 1 -ProxyServer $liveUrl -AutoConfigURL ('http://{0}/pac?x=1' -f $deadUrl) -Flags 0x0F
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '代理活着 + 本地 PAC 死了 -> 只删 PAC，保留代理' `
        ($after.ProxyEnable -eq 1 -and $after.AutoConfigURL -eq '') `
        ('ProxyEnable={0} PAC="{1}"' -f $after.ProxyEnable, $after.AutoConfigURL)
    Write-Case '代理活着 + 本地 PAC 死了 -> 标志位正确清掉 PAC 位(0x0F->0x0B)' `
        ($after.Flags -eq 0x0B) ('flags={0:X2}' -f $after.Flags)

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl -AutoConfigURL ('http://{0}/pac' -f $deadUrl) -Flags 0x0B
    $r = Invoke-Guard -ExtraArgs @('-KeepAutoConfigURL') -LogPath $log
    $after = Get-ShadowState
    Write-Case '-KeepAutoConfigURL -> PAC 被保留，但死代理仍被清理' `
        ($after.ProxyEnable -eq 0 -and $after.AutoConfigURL -ne '') `
        ('ProxyEnable={0} PAC="{1}"' -f $after.ProxyEnable, $after.AutoConfigURL)

    Write-Host ''
    Write-Host '--- 安全护栏 ---' -ForegroundColor Cyan

    Reset-Shadow -ProxyEnable 1 -ProxyServer 'proxy.corp.local' -Flags 0x0B
    $before = Get-ShadowState
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '地址解析不出主机端口 -> 不擅自清理' `
        ($after.ProxyEnable -eq 1 -and $after.Counter -eq $before.Counter) `
        ('ProxyEnable={0} counter {1}->{2}' -f $after.ProxyEnable, $before.Counter, $after.Counter)
    Write-Case '地址解析不出主机端口 -> 日志里给出告警' ((Read-Log $log) -match '解析不出') ''

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl -Flags 0x0B
    $before = Get-ShadowState
    $r = Invoke-Guard -ExtraArgs @('-DryRun') -LogPath $log
    $after = Get-ShadowState
    Write-Case '-DryRun -> 一个字都不改' `
        ($after.ProxyEnable -eq 1 -and $after.Counter -eq $before.Counter -and $after.Flags -eq 0x0B) `
        ('ProxyEnable={0} counter {1}->{2} flags={3:X2}' -f $after.ProxyEnable, $before.Counter, $after.Counter, $after.Flags)

    Reset-Shadow -ProxyEnable 1 -ProxyServer $liveUrl -Flags 0x0B
    $r = Invoke-Guard -ExtraArgs @('-Force') -LogPath $log
    $after = Get-ShadowState
    Write-Case '-Force -> 即使端口活着也强制恢复直连' ($after.ProxyEnable -eq 0) ('ProxyEnable={0}' -f $after.ProxyEnable)

    Write-Host ''
    Write-Host '--- 自动检测设置：默认保持原样 ---' -ForegroundColor Cyan

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl -AutoDetect 1 -Flags 0x0F
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '默认不改动用户的「自动检测设置」(保持勾选)' `
        ($after.AutoDetect -eq 1 -and $after.Flags -eq 0x09) `
        ('AutoDetect={0} flags={1:X2}' -f $after.AutoDetect, $after.Flags)

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl -AutoDetect 1 -Flags 0x09
    $r = Invoke-Guard -ExtraArgs @('-NoAutoDetect') -LogPath $log
    $after = Get-ShadowState
    Write-Case '-NoAutoDetect -> 取消勾选，标志位变 0x01' `
        ($after.AutoDetect -eq 0 -and $after.Flags -eq 0x01) `
        ('AutoDetect={0} flags={1:X2}' -f $after.AutoDetect, $after.Flags)

    Reset-Shadow -ProxyEnable 1 -ProxyServer $deadUrl -AutoDetect 0 -Flags 0x01
    $r = Invoke-Guard -ExtraArgs @('-AutoDetect') -LogPath $log
    $after = Get-ShadowState
    Write-Case '-AutoDetect -> 勾选，标志位变 0x09' `
        ($after.AutoDetect -eq 1 -and $after.Flags -eq 0x09) `
        ('AutoDetect={0} flags={1:X2}' -f $after.AutoDetect, $after.Flags)

    Write-Host ''
    Write-Host '--- 已经干净时不应乱动 ---' -ForegroundColor Cyan

    Reset-Shadow -ProxyEnable 0 -ProxyServer $deadUrl -AutoDetect 0 -Flags 0x01
    $before = Get-ShadowState
    $r = Invoke-Guard -LogPath $log
    $after = Get-ShadowState
    Write-Case '代理已关闭 -> 不写注册表' `
        ($after.Counter -eq $before.Counter -and $after.Flags -eq 0x01 -and $r.ExitCode -eq 0) `
        ('counter {0}->{1} flags={2:X2} exit={3}' -f $before.Counter, $after.Counter, $after.Flags, $r.ExitCode)

    Write-Host ''
    Write-Host '--- 无人值守模式(-Quiet)：出错必须留痕 ---' -ForegroundColor Cyan

    $errorLog = Join-Path $env:TEMP ('proxyguard-test-err-{0}.log' -f ([guid]::NewGuid().ToString('N')))
    Remove-Item -LiteralPath $errorLog -Force -ErrorAction SilentlyContinue
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $GuardPath,
                 '-Quiet', '-SettingsPath', 'HKCU:\Software\ProxyGuardNoSuchKey', '-LogPath', $errorLog)
    $null = & $PsExe @argList 2>&1
    $errText = Read-Log $errorLog
    Write-Case '-Quiet 模式下出错会写日志（不会被静默吞掉）' ($errText -match 'ERROR') ''
    Remove-Item -LiteralPath $errorLog -Force -ErrorAction SilentlyContinue
} finally {
    $listener.Stop()
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    if (-not $KeepTemp) {
        Remove-Item -LiteralPath $ShadowRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ('  通过 {0}    失败 {1}' -f $script:Pass, $script:Fail)
Write-Host '========================================' -ForegroundColor Cyan

if ($script:Fail -gt 0) { exit $script:Fail }
exit 0
