#Requires -Version 5.1
<#
.SYNOPSIS
    网络代理残留「体检 + 修复」：加速器 / 代理 / VPN 客户端被强制关机后上不了网。

.DESCRIPTION
    很多加速器、代理和 VPN 客户端（Watt Toolkit(Steam++)、Clash Verge、v2rayN、各种机场客户端、
    企业 VPN 客户端……）会把系统代理改成 http://127.0.0.1:<端口>，有的还会顺带改 WinHTTP 代理、
    网卡 DNS 和 hosts。它们正常退出时会还原，但【关机时进程是被系统直接杀掉的，来不及还原】。
    于是下次开机后系统仍然把流量发给一个没人监听的端口 —— 浏览器、Steam、商店等全部断网。
    （Win10/11 默认开启"快速启动"，所以"关机时自动清理"这类方案基本靠不住。）

    本脚本做两件事：
      1. 体检：系统代理 / PAC / 自动检测 / 计算机级代理 / WinHTTP / DNS / 默认路由 / hosts 全部检查并给出结论；
      2. 修复：默认把"指向本机死端口"的系统代理恢复成直连；可选再修 WinHTTP 代理、DNS、跃点、hosts。

    默认「智能模式」：先探测代理端口上有没有程序在监听 ——
    有（客户端正在运行）就什么都不做；只有端口没人监听（=死代理）时才清理。
    因此不会和正在工作的加速器/VPN 打架。

    脚本不联网、不下载任何东西；每次修改前都会把原设置备份到 logs\backup。

.PARAMETER DryRun
    只体检并打印报告，绝不修改任何设置（排障时首选）。

.PARAMETER Force
    跳过智能检测，无条件把系统代理恢复为直连。

.PARAMETER Delay
    先等待 N 秒再检查。开机自启场景用它给客户端留出启动时间（默认安装为 20 秒）。

.PARAMETER ProxyPort
    手动指定用于探活的端口；0 = 自动从 ProxyServer / PAC 地址中解析。

.PARAMETER AutoDetect
    清理后勾选「自动检测设置」。默认【保持原样】，不去动用户已有的自动检测设置。

.PARAMETER NoAutoDetect
    清理后取消勾选「自动检测设置」。

.PARAMETER KeepAutoConfigURL
    保留「使用自动配置脚本(PAC)」。默认只删除指向 127.0.0.1 / localhost 的本地失效 PAC，远程 PAC 一律保留。

.PARAMETER IncludeWinHttp
    同时重置 WinHTTP 代理（netsh winhttp reset proxy，需要管理员，否则自动跳过）。

.PARAMETER FixDns
    同时修复"疑似残留的死 DNS"。判定很保守：只处理【回环地址且本机 53 端口无人监听】或
    【私有网段地址且完全不可达】的 DNS，且只在该网卡是 DHCP 自动获取时才改回自动获取。
    公网 DNS（8.8.8.8 之类）永远不会被自动改动。

.PARAMETER FixMetric
    当"优先级最高的默认路由"落在虚拟网卡上、且此刻确实连不上外网时，提高该虚拟网卡的接口跃点，
    让物理网卡重新优先。（先探测再动手，不会在 VPN 正常工作时乱改。）

.PARAMETER FixHosts
    把 hosts 文件中指向 127.0.0.1 / 0.0.0.0 / ::1 的条目注释掉（先备份，可逆）。
    注意：你自己写的"屏蔽广告"条目也长这样，所以这项默认关闭。

.PARAMETER RepairAll
    等于同时打开 -IncludeWinHttp -FixDns -FixMetric -FixHosts。

.PARAMETER LogPath
    日志文件路径，默认 <脚本目录>\logs\proxyguard.log（超过 512KB 自动截断保留最近 500 行）。

.PARAMETER SettingsPath
    注册表路径，默认当前用户的 Internet Settings。一般不用改，仅供测试。

.PARAMETER Quiet
    不输出到控制台；且"什么都没做"时不写日志（给常驻监视用）。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-Proxy.ps1 -DryRun
    体检：看看代理 / DNS / 路由 / hosts 到底哪里有问题，不做任何修改。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-Proxy.ps1 -Force
    立刻恢复直连（断网急救，不需要管理员权限）。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-Proxy.ps1 -RepairAll
    连 WinHTTP / DNS / 跃点 / hosts 一起体检修复（需要管理员权限才生效）。
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [int]$Delay = 0,
    [int]$ProxyPort = 0,
    [switch]$AutoDetect,
    [switch]$NoAutoDetect,
    [switch]$KeepAutoConfigURL,
    [switch]$IncludeWinHttp,
    [switch]$FixDns,
    [switch]$FixMetric,
    [switch]$FixHosts,
    [switch]$RepairAll,
    [string]$LogPath,
    [string]$SettingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

if ($RepairAll) {
    $IncludeWinHttp = $true
    $FixDns         = $true
    $FixMetric      = $true
    $FixHosts       = $true
}

$ConnPath  = Join-Path $SettingsPath 'Connections'
$BlobName  = 'DefaultConnectionSettings'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

if (-not $LogPath) { $LogPath = Join-Path $PSScriptRoot 'logs\proxyguard.log' }
$LogDir = Split-Path -Parent $LogPath

$script:QuietMode = [bool]$Quiet
$script:Changed   = $false
$script:Important = $false
$script:LogBuffer = New-Object System.Collections.ArrayList

# ================================================================ 日志

function Add-LogLine {
    param([string]$Line)
    try {
        if ($LogDir -and -not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 512KB) {
            $tail = Get-Content -LiteralPath $LogPath -Tail 500
            Set-Content -LiteralPath $LogPath -Value $tail -Encoding UTF8
        }
        Add-Content -LiteralPath $LogPath -Value $Line -Encoding UTF8
    } catch {
        # 日志写不进去也绝不能影响修复流程
    }
}

function Write-Log {
    param(
        [Parameter(Position = 0)][string]$Message,
        [Parameter(Position = 1)][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $script:QuietMode) {
        Write-Host $line
        Add-LogLine $line
    } else {
        [void]$script:LogBuffer.Add($line)
        # 警告和错误永远要落盘：否则 Quiet 模式下出错会静默消失，没法排查
        if ($Level -eq 'WARN' -or $Level -eq 'ERROR') { $script:Important = $true }
    }
}

function Complete {
    param([int]$Code = 0)
    # 让调用方（例如 Watch-Proxy.ps1）知道本轮到底有没有改动过设置
    $global:ProxyGuardChanged = [bool]$script:Changed
    if ($script:QuietMode -and ($script:Changed -or $DryRun -or $script:Important)) {
        foreach ($l in $script:LogBuffer) { Add-LogLine $l }
    }
    exit $Code
}

# ================================================================ 基础工具

function Test-IsAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-EndpointAlive {
    param([string]$TargetHost, [int]$Port, [int]$TimeoutMs = 600)
    if ([string]::IsNullOrWhiteSpace($TargetHost) -or $Port -le 0) { return $false }
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch { } }
    }
}

function Test-IsLoopback {
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    return ($Address -eq '::1' -or $Address -match '^127\.')
}

function Test-IsPrivateAddress {
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    if (Test-IsLoopback $Address) { return $true }
    return ($Address -match '^10\.' -or $Address -match '^192\.168\.' -or
            $Address -match '^172\.(1[6-9]|2[0-9]|3[01])\.' -or
            $Address -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' -or
            $Address -match '^169\.254\.')
}

function Test-InternetReachable {
    # 任一公共地址的 443 能连通就算"有外网"；多试几个避免单个地址被墙导致误判
    foreach ($ip in @('223.5.5.5', '8.8.8.8', '1.1.1.1')) {
        if (Test-EndpointAlive -TargetHost $ip -Port 443 -TimeoutMs 1200) { return $true }
    }
    return $false
}

function Test-IsVirtualAdapter {
    param([string]$Description)
    if ([string]::IsNullOrWhiteSpace($Description)) { return $false }
    return ($Description -match 'TAP|TUN|Wintun|WireGuard|OpenVPN|VPN|Virtual|虚拟|Radmin|ZeroTier|Tailscale|Hyper-V|VMware|VirtualBox')
}

function Resolve-ProxyEndpoint {
    # 支持这些写法：
    #   127.0.0.1:7897
    #   http://127.0.0.1:7897              （Watt Toolkit 就是这样写的）
    #   http=127.0.0.1:7897;https=127.0.0.1:7897
    #   socks=127.0.0.1:1080
    param([string]$ProxyServer)
    if ([string]::IsNullOrWhiteSpace($ProxyServer)) { return $null }
    $candidates = @()
    if ($ProxyServer -match '=') {
        foreach ($part in ($ProxyServer -split ';')) {
            if ($part -match '=\s*([^;]+)$') { $candidates += $Matches[1] }
        }
    } else {
        $candidates += $ProxyServer
    }
    foreach ($c in $candidates) {
        $c = $c.Trim()
        # 带协议头时优先交给 Uri 解析（能正确处理 http:// 和 IPv6 方括号写法）
        if ($c -match '^[a-zA-Z][\w+.\-]*://') {
            try {
                $uri = [System.Uri]$c
                if ($uri.IsAbsoluteUri -and $uri.Port -gt 0) {
                    return [pscustomobject]@{ Host = $uri.Host; Port = [int]$uri.Port }
                }
            } catch { }
            # Uri 解析失败就退回手工剥离协议头
            $c = $c -replace '^[a-zA-Z][\w+.\-]*://', ''
            $c = $c -replace '/.*$', ''
        }
        $c = $c -replace '@.*$', ''      # 去掉 user:pass@ 前缀
        if ($c -match '^(?<h>[^:]+):(?<p>\d+)$') {
            return [pscustomobject]@{ Host = $Matches['h']; Port = [int]$Matches['p'] }
        }
    }
    return $null
}

function Resolve-PacEndpoint {
    param([string]$AutoConfigURL)
    if ([string]::IsNullOrWhiteSpace($AutoConfigURL)) { return $null }
    try {
        $uri = [System.Uri]$AutoConfigURL
        if ($uri.IsAbsoluteUri -and $uri.Port -gt 0) {
            return [pscustomobject]@{ Host = $uri.Host; Port = $uri.Port }
        }
    } catch { }
    return $null
}

function Invoke-InternetSettingsRefresh {
    try {
        if (-not ('ProxyGuard.WinINet' -as [type])) {
            Add-Type -Namespace 'ProxyGuard' -Name 'WinINet' -MemberDefinition @'
[DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool InternetSetOption(System.IntPtr hInternet, int dwOption, System.IntPtr lpBuffer, int dwBufferLength);
'@
        }
        # 39 = INTERNET_OPTION_SETTINGS_CHANGED, 37 = INTERNET_OPTION_REFRESH
        [void][ProxyGuard.WinINet]::InternetSetOption([System.IntPtr]::Zero, 39, [System.IntPtr]::Zero, 0)
        [void][ProxyGuard.WinINet]::InternetSetOption([System.IntPtr]::Zero, 37, [System.IntPtr]::Zero, 0)
        Write-Log '已通知系统代理设置变更（WinINET 刷新），浏览器等无需重启系统即可恢复'
        return $true
    } catch {
        Write-Log "通知系统刷新失败（重启相关软件即可生效）: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Save-Backup {
    param([string]$Name, $Content)
    try {
        $dir = Join-Path $LogDir 'backup'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir ('{0}-{1}.json' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $Content | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
        $old = Get-ChildItem -LiteralPath $dir -Filter "$Name-*.json" |
               Sort-Object LastWriteTime -Descending | Select-Object -Skip 20
        foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    } catch {
        Write-Log "备份失败（不影响修复）: $($_.Exception.Message)" 'WARN'
    }
}

# ================================================================ 读取各项状态

function Get-ProxyState {
    $state = [pscustomobject]@{
        ProxyEnable   = 0
        ProxyServer   = ''
        ProxyOverride = ''
        AutoConfigURL = ''
        AutoDetect    = 0
    }
    try {
        $item = Get-ItemProperty -Path $SettingsPath -ErrorAction Stop
        if ($null -ne $item.ProxyEnable)   { $state.ProxyEnable   = [int]$item.ProxyEnable }
        if ($null -ne $item.ProxyServer)   { $state.ProxyServer   = [string]$item.ProxyServer }
        if ($null -ne $item.ProxyOverride) { $state.ProxyOverride = [string]$item.ProxyOverride }
        if ($null -ne $item.AutoConfigURL) { $state.AutoConfigURL = [string]$item.AutoConfigURL }
        if ($null -ne $item.AutoDetect)    { $state.AutoDetect    = [int]$item.AutoDetect }
    } catch {
        Write-Log "读取用户代理设置失败: $($_.Exception.Message)" 'ERROR'
    }
    return $state
}

function Get-MachineProxyState {
    try {
        $item = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $enable = 0
        if ($null -ne $item.ProxyEnable) { $enable = [int]$item.ProxyEnable }
        return [pscustomobject]@{
            ProxyEnable = $enable
            ProxyServer = [string]$item.ProxyServer
            PerUser     = $item.ProxySettingsPerUser
        }
    } catch {
        return $null
    }
}

function Get-WinHttpProxyInfo {
    try {
        $raw = (& netsh winhttp show proxy 2>&1 | Out-String).Trim()
        # 各语言版本的"直连"字样
        $direct = [bool]($raw -match 'Direct access|直接访问|直接存取|ダイレクト アクセス|Accès direct|Direkter Zugriff|직접 액세스|Direct toegang|Acesso direto|Acceso directo')
        return [pscustomobject]@{ Raw = $raw; IsDirect = $direct }
    } catch {
        return [pscustomobject]@{ Raw = 'n/a'; IsDirect = $true }
    }
}

function Get-DnsFindings {
    $out = @()
    $cfgs = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
    foreach ($c in $cfgs) {
        if (-not $c.ServerAddresses) { continue }
        $servers = @($c.ServerAddresses)
        if ($servers.Count -eq 0) { continue }
        $ipif = Get-NetIPInterface -InterfaceIndex $c.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $ipif -or $ipif.ConnectionState -ne 'Connected') { continue }

        $suspect = @()
        $deadAny = @()
        foreach ($s in $servers) {
            if (Test-IsLoopback $s) {
                if (-not (Test-EndpointAlive -TargetHost '127.0.0.1' -Port 53)) { $suspect += $s; $deadAny += $s }
            } elseif (Test-IsPrivateAddress $s) {
                if (-not (Test-EndpointAlive -TargetHost $s -Port 53 -TimeoutMs 500)) { $suspect += $s; $deadAny += $s }
            } else {
                if (-not (Test-EndpointAlive -TargetHost $s -Port 53 -TimeoutMs 500)) { $deadAny += $s }
            }
        }
        $out += [pscustomobject]@{
            Interface   = $c.InterfaceAlias
            Index       = $c.InterfaceIndex
            Servers     = ($servers -join ', ')
            DeadAny     = ($deadAny -join ', ')
            DeadFixable = (@($suspect).Count -eq $servers.Count)
            Dhcp        = ($ipif.Dhcp -eq 'Enabled')
        }
    }
    return $out
}

function Get-RouteFindings {
    $out = @()
    $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 -ErrorAction SilentlyContinue
    foreach ($r in $routes) {
        $adapter = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        $im = 0
        $ipif = Get-NetIPInterface -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipif) { $im = [int]$ipif.InterfaceMetric }
        $virtual = $false
        $name = 'if#' + $r.ifIndex
        $status = 'Unknown'
        if ($adapter) {
            $name = $adapter.Name
            $status = [string]$adapter.Status
            $virtual = Test-IsVirtualAdapter $adapter.InterfaceDescription
        }
        $out += [pscustomobject]@{
            Interface = $name
            Index     = [int]$r.ifIndex
            NextHop   = [string]$r.NextHop
            Effective = ([int]$r.RouteMetric + $im)
            Metric    = $im
            Virtual   = $virtual
            Status    = $status
        }
    }
    return ($out | Sort-Object Effective)
}

function Get-HostsFindings {
    $result = [pscustomobject]@{
        Path    = $HostsPath
        Exists  = $false
        Total   = 0
        Suspect = @()
        Raw     = @()
    }
    try {
        if (-not (Test-Path -LiteralPath $HostsPath)) { return $result }
        $result.Exists = $true
        $all = @(Get-Content -LiteralPath $HostsPath -ErrorAction Stop)
        $result.Raw = $all
        $suspect = @()
        foreach ($l in $all) {
            $t = $l.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $result.Total = $result.Total + 1
            if ($t -match '^(127\.0\.0\.1|0\.0\.0\.0|::1)\s+\S+') { $suspect += $t }
        }
        $result.Suspect = $suspect
    } catch {
        Write-Log "读取 hosts 失败: $($_.Exception.Message)" 'WARN'
    }
    return $result
}

# ================================================================ 体检报告

function Write-Report {
    param($State, $PacEndpoint, $PacLocal, $PacAlive, $ProxyAlive, $Machine, $WinHttp, $DnsList, $RouteList, $Hosts, [bool]$Admin)

    $DnsList   = @($DnsList)
    $RouteList = @($RouteList)

    Write-Log '================ 网络残留体检 ================'

    # 1) 系统代理（当前用户）
    if ($State.ProxyEnable -ne 0 -and $State.ProxyServer) {
        $verdict = '无法解析地址'
        if ($null -ne $ProxyAlive) {
            if ($ProxyAlive) { $verdict = '端口有程序在监听（客户端运行中，正常）' }
            else { $verdict = '端口无人监听 → 死代理，就是它导致上不了网' }
        }
        Write-Log ('[1] 系统代理(当前用户) : 已开启 -> {0}   [{1}]' -f $State.ProxyServer, $verdict)
    } elseif ($State.ProxyEnable -ne 0) {
        Write-Log '[1] 系统代理(当前用户) : 已开启但地址为空   [等于直连，不影响上网，不去动它]'
    } else {
        Write-Log '[1] 系统代理(当前用户) : 未开启（直连）   [正常]'
    }

    # 2) PAC
    if ($State.AutoConfigURL) {
        $tag = '远程 PAC，保留不动'
        if ($PacLocal) {
            if ($null -ne $PacAlive -and -not $PacAlive) { $tag = '本地 PAC 且端口无人监听 → 死 PAC' }
            else { $tag = '本地 PAC，端口有监听   [正常]' }
        }
        Write-Log ('[2] 自动配置脚本(PAC)  : {0}   [{1}]' -f $State.AutoConfigURL, $tag)
    } else {
        Write-Log '[2] 自动配置脚本(PAC)  : 未设置   [正常]'
    }

    # 3) 自动检测
    if ([int]$State.AutoDetect -eq 1) { Write-Log '[3] 自动检测设置       : 已勾选' } else { Write-Log '[3] 自动检测设置       : 未勾选' }

    # 4) 计算机级代理
    if ($Machine -and ($Machine.ProxyEnable -ne 0 -or $Machine.ProxyServer)) {
        $scope = '存在，但未强制全局生效'
        if ($null -ne $Machine.PerUser -and [int]$Machine.PerUser -eq 0) {
            $scope = '全局生效(ProxySettingsPerUser=0)，用户级设置会被它覆盖，需要管理员才能改'
        }
        Write-Log ('[4] 系统代理(计算机级) : 已开启 -> {0}   [{1}]' -f $Machine.ProxyServer, $scope)
    } else {
        Write-Log '[4] 系统代理(计算机级) : 未设置   [正常]'
    }

    # 5) WinHTTP
    if ($WinHttp.IsDirect) {
        Write-Log '[5] WinHTTP 代理       : 未设置（直连）   [正常]'
    } else {
        $first = (@($WinHttp.Raw -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Skip 1 -First 2) -join ' / '
        Write-Log ('[5] WinHTTP 代理       : 已设置 -> {0}   [部分命令行工具会受影响]' -f $first)
    }

    # 6) DNS
    if ($DnsList.Count -eq 0) {
        Write-Log '[6] 网卡 DNS           : 没有查到已连接网卡的 DNS 配置'
    } else {
        foreach ($d in $DnsList) {
            $tag = '可用'
            if ($d.DeadFixable) { $tag = '全部不可达且属私有/回环 → 疑似残留死 DNS' }
            elseif ($d.DeadAny) { $tag = '部分不可达: ' + $d.DeadAny }
            Write-Log ('[6] 网卡 DNS           : {0} -> {1}   [{2}]' -f $d.Interface, $d.Servers, $tag)
        }
    }

    # 7) 默认路由
    if ($RouteList.Count -eq 0) {
        Write-Log '[7] 默认路由           : 没有默认路由（当前可能处于离线状态）'
    } else {
        $winner = $RouteList | Select-Object -First 1
        foreach ($r in $RouteList) {
            $tag = '备用'
            if ($r.Index -eq $winner.Index) { $tag = '当前优先' }
            if ($r.Virtual) { $tag = $tag + '，虚拟网卡' }
            Write-Log ('[7] 默认路由           : {0} 网关 {1} 有效跃点 {2}   [{3}]' -f $r.Interface, $r.NextHop, $r.Effective, $tag)
        }
        if ($winner.Virtual) {
            Write-Log '[7] 提示：当前优先的默认路由落在虚拟网卡上。若此时又上不了网，多半是 VPN/加速器的隧道没建立起来（网络锁或残留路由）。' 'WARN'
        }
    }

    # 8) hosts
    if (-not $Hosts.Exists) {
        Write-Log '[8] hosts 文件         : 不存在（正常）'
    } elseif (@($Hosts.Suspect).Count -gt 0) {
        Write-Log ('[8] hosts 文件         : {0} 条有效条目，其中 {1} 条指向 127.0.0.1/0.0.0.0（可能是加速器残留，也可能是你自己写的屏蔽规则）' -f $Hosts.Total, @($Hosts.Suspect).Count)
        foreach ($s in (@($Hosts.Suspect) | Select-Object -First 5)) { Write-Log ('      {0}' -f $s) }
        if (@($Hosts.Suspect).Count -gt 5) {
            Write-Log ('      …… 其余 ' + (@($Hosts.Suspect).Count - 5) + ' 条已备份到 logs\backup')
        }
    } else {
        Write-Log '[8] hosts 文件         : 正常（无指向本机的条目）'
    }

    # 9) 权限
    if ($Admin) {
        Write-Log '[9] 管理员权限         : 是（所有修复项都可用）'
    } else {
        Write-Log '[9] 管理员权限         : 否（系统代理修复可用；WinHTTP/DNS/跃点/hosts 需要管理员）'
    }
    Write-Log '=============================================='
}

# ================================================================ 修复动作

function Set-ConnectionBlobFlags {
    # 同步「局域网(LAN)设置」对话框背后的二进制数据，保证控制面板里显示的勾选状态一致。
    # flags 位：DIRECT=1, PROXY=2, AUTO_PROXY_URL=4, AUTO_DETECT=8
    param([int]$Flags)
    try {
        if (-not (Test-Path -LiteralPath $ConnPath)) { return $false }
        $item = Get-ItemProperty -Path $ConnPath -Name $BlobName -ErrorAction Stop
        $blob = $item.$BlobName
        if ($null -eq $blob -or $blob.Length -lt 12) { return $false }

        # offset 4..7：变更计数器，每次修改 +1（这也是判断"改动是不是本工具做的"的指纹）
        $counter = [int]$blob[4] + ([int]$blob[5] -shl 8) + ([int]$blob[6] -shl 16) + ([int]$blob[7] -shl 24)
        $counter = ($counter + 1) -band 0x7FFFFFFF
        $blob[4] = $counter -band 0xFF
        $blob[5] = ($counter -shr 8) -band 0xFF
        $blob[6] = ($counter -shr 16) -band 0xFF
        $blob[7] = ($counter -shr 24) -band 0xFF

        $blob[8]  = $Flags -band 0xFF
        $blob[9]  = ($Flags -shr 8) -band 0xFF
        $blob[10] = 0
        $blob[11] = 0

        Set-ItemProperty -Path $ConnPath -Name $BlobName -Value $blob -Type Binary -ErrorAction Stop
        return $true
    } catch {
        Write-Log "同步 LAN 设置二进制失败（不影响上网）: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Get-ConnectionBlobFlags {
    try {
        if (-not (Test-Path -LiteralPath $ConnPath)) { return -1 }
        $item = Get-ItemProperty -Path $ConnPath -Name $BlobName -ErrorAction Stop
        $blob = $item.$BlobName
        if ($null -eq $blob -or $blob.Length -lt 12) { return -1 }
        return ([int]$blob[8] + ([int]$blob[9] -shl 8))
    } catch {
        return -1
    }
}

function Set-CleanProxyState {
    param([bool]$AutoDetectOn, $State)
    Save-Backup -Name 'proxy-backup' -Content $State

    New-ItemProperty -Path $SettingsPath -Name 'ProxyEnable' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Log 'ProxyEnable -> 0（已关闭「为 LAN 使用代理服务器」）'

    if (-not $KeepAutoConfigURL) {
        Remove-ItemProperty -Path $SettingsPath -Name 'AutoConfigURL' -Force -ErrorAction SilentlyContinue
        Write-Log 'AutoConfigURL -> 已删除（原为本地失效 PAC）'
    }

    $v = 0
    if ($AutoDetectOn) { $v = 1 }
    New-ItemProperty -Path $SettingsPath -Name 'AutoDetect' -Value $v -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Log ('AutoDetect -> {0}' -f $v)

    $flags = 1                                     # PROXY_TYPE_DIRECT
    if ($AutoDetectOn) { $flags = $flags -bor 8 }   # PROXY_TYPE_AUTO_DETECT
    if (Set-ConnectionBlobFlags -Flags $flags) {
        Write-Log 'Connections\DefaultConnectionSettings 已同步（控制面板显示一致）'
    }

    $script:Changed = $true
}

function Invoke-WinHttpReset {
    if (-not (Test-IsAdmin)) {
        Write-Log 'WinHTTP 代理重置需要管理员权限，已跳过（可用管理员身份重跑，或加 -RepairAll）' 'WARN'
        return
    }
    try {
        & netsh winhttp reset proxy | Out-Null
        Write-Log 'WinHTTP 代理已重置为直连'
        $script:Changed = $true
    } catch {
        Write-Log "WinHTTP 代理重置失败: $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-DnsFix {
    param($DnsList)
    $targets = @(@($DnsList) | Where-Object { $_.DeadFixable })
    if ($targets.Count -eq 0) { return }
    if (-not (Test-IsAdmin)) {
        Write-Log '发现疑似残留死 DNS，但修复需要管理员权限，已跳过' 'WARN'
        return
    }
    foreach ($d in $targets) {
        if (-not $d.Dhcp) {
            Write-Log ('{0} 的 DNS 不可达，但该网卡不是自动获取(DHCP)，为避免改坏静态配置，只报告不修改' -f $d.Interface) 'WARN'
            continue
        }
        try {
            Save-Backup -Name ('dns-' + ($d.Interface -replace '[^\w\-]', '_')) -Content $d
            Set-DnsClientServerAddress -InterfaceIndex $d.Index -ResetServerAddresses -ErrorAction Stop
            Write-Log ('{0} 的 DNS 已改回「自动获取」（原为不可达的 {1}）' -f $d.Interface, $d.Servers)
            $script:Changed = $true
        } catch {
            Write-Log ('{0} 的 DNS 修复失败: {1}' -f $d.Interface, $_.Exception.Message) 'WARN'
        }
    }
}

function Invoke-MetricFix {
    param($RouteList)
    $RouteList = @($RouteList)
    $winner = $RouteList | Select-Object -First 1
    if (-not $winner -or -not $winner.Virtual) { return }

    $physical = $RouteList | Where-Object { (-not $_.Virtual) -and $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $physical) {
        Write-Log '默认路由落在虚拟网卡上，但没有可用的物理网卡路由，不做处理' 'WARN'
        return
    }
    if (Test-InternetReachable) {
        Write-Log '当前能连上外网，判定虚拟网卡路由属正常使用，不做处理'
        return
    }
    if (-not (Test-IsAdmin)) {
        Write-Log '外网不通且优先路由在虚拟网卡上，但调整跃点需要管理员权限，已跳过' 'WARN'
        return
    }
    try {
        Save-Backup -Name ('route-' + ($winner.Interface -replace '[^\w\-]', '_')) -Content $winner
        $newMetric = [int]$physical.Effective + 100
        Set-NetIPInterface -InterfaceIndex $winner.Index -AddressFamily IPv4 -InterfaceMetric $newMetric -ErrorAction Stop
        Write-Log ('已把虚拟网卡 {0} 的接口跃点提到 {1}，让物理网卡 {2} 重新优先' -f $winner.Interface, $newMetric, $physical.Interface)
        $script:Changed = $true
        Start-Sleep -Seconds 1
        if (Test-InternetReachable) { Write-Log '复测：外网已恢复连通' } else { Write-Log '复测：外网仍不通，请检查网卡 / DNS / VPN 客户端设置' 'WARN' }
    } catch {
        Write-Log ("调整虚拟网卡跃点失败: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Invoke-HostsFix {
    param($Hosts)
    if (@($Hosts.Suspect).Count -eq 0) { return }
    if (-not (Test-IsAdmin)) {
        Write-Log ('hosts 里有 {0} 条指向本机的条目，修复需要管理员权限，已跳过' -f @($Hosts.Suspect).Count) 'WARN'
        return
    }
    try {
        Save-Backup -Name 'hosts-backup' -Content $Hosts.Raw
        $out = New-Object System.Collections.ArrayList
        $count = 0
        foreach ($l in $Hosts.Raw) {
            $t = $l.Trim()
            if ($t -ne '' -and -not $t.StartsWith('#') -and $t -match '^(127\.0\.0\.1|0\.0\.0\.0|::1)\s+\S+') {
                [void]$out.Add('# [ProxyGuard] ' + $l)
                $count++
            } else {
                [void]$out.Add($l)
            }
        }
        Set-Content -LiteralPath $HostsPath -Value $out -Encoding ASCII -ErrorAction Stop
        Write-Log ('hosts: 已注释掉 {0} 条指向本机的条目（原文已备份到 logs\backup；要恢复就把行首的「# [ProxyGuard] 」删掉）' -f $count)
        $script:Changed = $true
    } catch {
        Write-Log ("hosts 修复失败: {0}" -f $_.Exception.Message) 'WARN'
    }
}

# ================================================================ 主流程

try {
    if ($Delay -gt 0) {
        Write-Log "等待 $Delay 秒后再检查（给客户端留出启动时间）"
        Start-Sleep -Seconds $Delay
    }

    $Admin = Test-IsAdmin
    $State = Get-ProxyState
    Write-Log ('当前用户代理设置: ProxyEnable={0}; ProxyServer="{1}"; AutoConfigURL="{2}"; AutoDetect={3}' -f `
        $State.ProxyEnable, $State.ProxyServer, $State.AutoConfigURL, $State.AutoDetect)

    # ---- 探活
    $PacEndpoint = Resolve-PacEndpoint $State.AutoConfigURL
    $PacLocal = $false
    if ($PacEndpoint -and (Test-IsLoopback $PacEndpoint.Host)) { $PacLocal = $true }

    $endpoint = $null
    if ($ProxyPort -gt 0) {
        $endpoint = [pscustomobject]@{ Host = '127.0.0.1'; Port = $ProxyPort }
    } elseif ($State.ProxyEnable -ne 0) {
        $endpoint = Resolve-ProxyEndpoint $State.ProxyServer
    }
    if (-not $endpoint -and $PacLocal) { $endpoint = $PacEndpoint }

    $ProxyAlive = $null
    if ($endpoint) { $ProxyAlive = Test-EndpointAlive -TargetHost $endpoint.Host -Port $endpoint.Port -TimeoutMs 1500 }

    $PacAlive = $null
    if ($PacEndpoint) { $PacAlive = Test-EndpointAlive -TargetHost $PacEndpoint.Host -Port $PacEndpoint.Port -TimeoutMs 1500 }

    # ---- 体检
    $Machine   = Get-MachineProxyState
    $WinHttp   = Get-WinHttpProxyInfo
    $DnsList   = @(Get-DnsFindings)
    $RouteList = @(Get-RouteFindings)
    $Hosts     = Get-HostsFindings

    Write-Report -State $State -PacEndpoint $PacEndpoint -PacLocal $PacLocal -PacAlive $PacAlive -ProxyAlive $ProxyAlive `
                 -Machine $Machine -WinHttp $WinHttp -DnsList $DnsList -RouteList $RouteList -Hosts $Hosts -Admin $Admin

    if ($DryRun) {
        Write-Log '体检完成，未做任何修改（去掉 -DryRun 才会真正修复）。'
        Complete 0
    }

    # ---- 修复 1：系统代理（免管理员，核心项）
    # 「自动检测设置」默认保持原样：不去动用户已有的选择，免得每次开机都来回改
    $desiredAutoDetect = [bool]$State.AutoDetect
    if ($AutoDetect)   { $desiredAutoDetect = $true }
    if ($NoAutoDetect) { $desiredAutoDetect = $false }

    $hasManualProxy = ($State.ProxyEnable -ne 0 -and -not [string]::IsNullOrWhiteSpace($State.ProxyServer))
    $deadLocalPac   = ($PacLocal -and (-not $KeepAutoConfigURL) -and ($PacAlive -eq $false))

    $needFix = $false
    if ($hasManualProxy) { $needFix = $true }
    if ($deadLocalPac)   { $needFix = $true }

    if (-not $needFix) {
        Write-Log '系统代理已是干净状态（直连），无需处理。'
    } elseif ($Force) {
        Write-Log '按 -Force 无条件恢复直连'
        Set-CleanProxyState -AutoDetectOn $desiredAutoDetect -State $State
    } elseif ($endpoint -and $ProxyAlive -and $deadLocalPac) {
        # 手动代理还活着，但本地 PAC 已经失效；PAC 优先级更高，会拖垮上网 —— 只清失效的 PAC，保留用户的代理
        Save-Backup -Name 'pac-backup' -Content $State
        Remove-ItemProperty -Path $SettingsPath -Name 'AutoConfigURL' -Force -ErrorAction SilentlyContinue
        $curFlags = Get-ConnectionBlobFlags
        if ($curFlags -ge 0) { [void](Set-ConnectionBlobFlags -Flags ($curFlags -band 0xFFFFFFFB)) }
        Write-Log '代理本身在正常工作，但本地 PAC 已失效 → 只清掉失效的 PAC，保留你的代理'
        $script:Changed = $true
    } elseif ($endpoint -and $ProxyAlive) {
        Write-Log ('代理端口 {0}:{1} 有程序在监听 → 客户端正在运行，跳过清理（如需强制请加 -Force）' -f $endpoint.Host, $endpoint.Port) 'SKIP'
    } elseif ($hasManualProxy -and -not $endpoint) {
        Write-Log ('代理地址 "{0}" 解析不出主机和端口，出于安全不自动清理（确认它确实是死代理，就加 -Force 修一次）' -f $State.ProxyServer) 'WARN'
    } else {
        if ($endpoint) {
            Write-Log ('代理端口 {0}:{1} 无任何程序监听 → 这是死代理，开始清理' -f $endpoint.Host, $endpoint.Port)
        } else {
            Write-Log '本地 PAC 已失效 → 开始清理'
        }
        Set-CleanProxyState -AutoDetectOn $desiredAutoDetect -State $State
    }

    # ---- 修复 2~5：可选项目
    if ($IncludeWinHttp -and -not $WinHttp.IsDirect) { Invoke-WinHttpReset }
    if ($FixDns)    { Invoke-DnsFix    -DnsList $DnsList }
    if ($FixMetric) { Invoke-MetricFix -RouteList $RouteList }
    if ($FixHosts)  { Invoke-HostsFix  -Hosts $Hosts }

    # ---- 收尾
    if ($script:Changed) {
        Invoke-InternetSettingsRefresh | Out-Null
        try { & ipconfig /flushdns | Out-Null; Write-Log '已刷新 DNS 缓存' } catch { }
        $after = Get-ProxyState
        Write-Log ('修复后: ProxyEnable={0}; AutoConfigURL="{1}"; AutoDetect={2}' -f $after.ProxyEnable, $after.AutoConfigURL, $after.AutoDetect)
        Write-Log '完成。现在应该可以直接上网，浏览器等软件一般无需重启系统。'
    } else {
        Write-Log '本次没有任何修改。'
    }
    Complete 0
} catch {
    Write-Log "执行出错: $($_.Exception.Message)" 'ERROR'
    Complete 1
}
