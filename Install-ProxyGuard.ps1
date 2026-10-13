#Requires -Version 5.1
<#
.SYNOPSIS
    安装 / 卸载「代理守护」：开机后自动清理加速器、代理、VPN 客户端遗留的死代理，恢复上网。

.DESCRIPTION
    做四件事：
      1. 把脚本部署到稳定目录（默认 %LOCALAPPDATA%\ProxyGuard），不依赖你从哪个文件夹运行；
         部署时强制写成 UTF-8 带 BOM 并回读校验（PowerShell 5.1 读无 BOM 的 UTF-8 会乱码并报语法错误）。
      2. 生成「修复上网.cmd」「一键体检.cmd」「卸载.cmd」等双击即用的入口。
      3. 注册开机自启：
         - 先尝试计划任务（需要管理员权限，注册后会回读确认，避免误判成功）；
         - 注册不了就自动回退到「启动文件夹」方式（免管理员权限，效果一样，只是登录时有个极短的隐藏窗口）。
      4. 可选：生成桌面快捷方式、常驻监视、关机清理任务。

.PARAMETER InstallDir
    安装目录，默认 %LOCALAPPDATA%\ProxyGuard。

.PARAMETER Delay
    登录后等待多少秒再检查，默认 20 秒（给加速器/VPN 客户端留出启动时间，避免误判）。
    如果你不打算让客户端开机自启，可以改成 5。

.PARAMETER Watch
    安装成「常驻监视」模式：不只是开机检查一次，而是每隔一段时间检查一次，
    客户端中途崩溃也能自动恢复上网。

.PARAMETER WatchIntervalMinutes
    常驻监视的检查间隔（分钟），默认 5。

.PARAMETER AutoDetect
    清理后勾选「自动检测设置」（默认不勾，纯直连）。

.PARAMETER IncludeWinHttp
    让守护脚本同时重置 WinHTTP 代理（普通权限下会自动跳过，见 -UseTask）。

.PARAMETER RepairAll
    让守护脚本同时修复 WinHTTP 代理 / DNS / 虚拟网卡跃点 / hosts（这些需要管理员权限）。

.PARAMETER AtShutdown
    额外注册「关机时清理」任务（尽力而为：快速启动/强制关机时可能不执行，不能当主力）。

.PARAMETER DesktopShortcut
    在桌面生成「修复上网」快捷方式。

.PARAMETER UseTask
    只接受计划任务方式（以管理员身份运行时用），并把任务设为"最高权限"运行，
    这样开机时也能一并修复 WinHTTP/DNS/hosts。注册失败即报错退出，不回退。

.PARAMETER Uninstall
    卸载：停掉常驻监视、删除计划任务、启动项、桌面快捷方式和安装目录。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProxyGuard.ps1 -DesktopShortcut
    普通安装（免管理员），带桌面快捷方式。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProxyGuard.ps1 -UseTask -RepairAll -DesktopShortcut
    以管理员身份运行：注册成计划任务，开机时连 DNS / WinHTTP / hosts 一起修。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProxyGuard.ps1 -Uninstall
    卸载干净。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'ProxyGuard'),
    [int]$Delay = 20,
    [switch]$Watch,
    [double]$WatchIntervalMinutes = 5,
    [switch]$AutoDetect,
    [switch]$IncludeWinHttp,
    [switch]$RepairAll,
    [switch]$AtShutdown,
    [switch]$DesktopShortcut,
    [switch]$UseTask,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$TaskName         = 'ProxyGuard'
$ShutdownTaskName = 'ProxyGuard-Shutdown'
$StartupFolder    = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$StartupCmdName   = 'ProxyGuard.cmd'
$FixCmdName       = '修复上网.cmd'
$CheckCmdName     = '一键体检.cmd'
$UninstallCmdName = '卸载.cmd'
$ElevatedCmdName  = '安装为计划任务(需管理员).cmd'
$SourceGuard      = Join-Path $PSScriptRoot 'Reset-Proxy.ps1'
$SourceWatch      = Join-Path $PSScriptRoot 'Watch-Proxy.ps1'

function Write-Step { param([string]$m) Write-Host "[ProxyGuard] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[ProxyGuard] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[ProxyGuard] $m" -ForegroundColor Yellow }

function Get-CurrentUserSid {
    return ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
}

function Deploy-Utf8Bom {
    # 必须以「UTF-8 带 BOM」存放：
    # Windows PowerShell 5.1 读取无 BOM 的 UTF-8 文件时会按系统 ANSI(GBK 等) 解码，
    # 中文会全部变成乱码并导致语法解析失败 —— 脚本会直接跑不起来。
    param([string]$Source, [string]$Destination)
    $text = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
    $enc  = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Destination, $text, $enc)

    $bytes = [System.IO.File]::ReadAllBytes($Destination)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Remove-StartupEntry {
    $p = Join-Path $StartupFolder $StartupCmdName
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        Write-Ok "已删除启动项: $p"
    }
}

function Remove-DesktopShortcut {
    $p = Join-Path ([Environment]::GetFolderPath('Desktop')) '修复上网.lnk'
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        Write-Ok "已删除桌面快捷方式: $p"
    }
}

function Stop-WatcherProcesses {
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -and $_.CommandLine -like '*Watch-Proxy.ps1*' })
        foreach ($p in $procs) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Ok ("已停止常驻监视进程 (PID {0})" -f $p.ProcessId)
        }
    } catch { }
}

function Remove-ProxyGuardTasks {
    foreach ($name in @($TaskName, $ShutdownTaskName)) {
        $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if ($t) {
            try {
                Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
                Write-Ok "已删除计划任务: $name"
            } catch {
                Write-Warn "删除计划任务 $name 失败: $($_.Exception.Message)"
            }
        }
    }
}

# ---------------------------------------------------------------- 卸载

if ($Uninstall) {
    Write-Step '开始卸载 ProxyGuard ...'
    # 先让常驻监视退出，否则安装目录里的日志文件可能被占用
    $stopFile = Join-Path $InstallDir 'logs\watch.stop'
    try {
        $dir = Split-Path -Parent $stopFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $stopFile -Value 'stop' -Encoding ASCII
    } catch { }
    Stop-WatcherProcesses
    Remove-ProxyGuardTasks
    Remove-StartupEntry
    Remove-DesktopShortcut
    if (Test-Path -LiteralPath $InstallDir) {
        try {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
            Write-Ok "已删除安装目录: $InstallDir"
        } catch {
            Write-Warn "安装目录未完全删除（可能日志被占用，注销后重试即可）: $($_.Exception.Message)"
        }
    }
    Write-Ok '卸载完成。'
    exit 0
}

# ---------------------------------------------------------------- 安装

if (-not (Test-Path -LiteralPath $SourceGuard)) {
    throw "找不到 Reset-Proxy.ps1（应与本脚本在同一目录）: $SourceGuard"
}
if ($Watch -and -not (Test-Path -LiteralPath $SourceWatch)) {
    throw "指定了 -Watch，但找不到 Watch-Proxy.ps1（应与本脚本在同一目录）: $SourceWatch"
}

Write-Step "安装目录: $InstallDir"
if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$installedGuard = Join-Path $InstallDir 'Reset-Proxy.ps1'
if (Deploy-Utf8Bom -Source $SourceGuard -Destination $installedGuard) {
    Write-Ok '已部署 Reset-Proxy.ps1（UTF-8 BOM，兼容 PowerShell 5.1）'
} else {
    Write-Warn '部署的 Reset-Proxy.ps1 缺少 UTF-8 BOM，PowerShell 5.1 下可能解析失败！'
}

$installedWatch = $null
if (Test-Path -LiteralPath $SourceWatch) {
    $installedWatch = Join-Path $InstallDir 'Watch-Proxy.ps1'
    [void](Deploy-Utf8Bom -Source $SourceWatch -Destination $installedWatch)
}
if ($Watch -and -not $installedWatch) { throw '常驻监视脚本部署失败' }

# 安装器自身也复制一份，方便以后从安装目录直接卸载 / 升级
$selfPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($selfPath)) { $selfPath = $MyInvocation.MyCommand.Path }
$installedInstaller = Join-Path $InstallDir 'Install-ProxyGuard.ps1'
if ($selfPath -and (Test-Path -LiteralPath $selfPath)) {
    [void](Deploy-Utf8Bom -Source $selfPath -Destination $installedInstaller)
}

# --- 透传给守护脚本的参数
$extraArgs = ''
if ($AutoDetect)     { $extraArgs += ' -AutoDetect' }
if ($IncludeWinHttp) { $extraArgs += ' -IncludeWinHttp' }
if ($RepairAll)      { $extraArgs += ' -RepairAll' }

# --- 决定由谁来做这件事：一次性守护 或 常驻监视
if ($Watch) {
    $runner     = $installedWatch
    $runnerArgs = ('-IntervalMinutes {0} -Delay {1}{2}' -f $WatchIntervalMinutes, $Delay, $extraArgs)
} else {
    $runner     = $installedGuard
    $runnerArgs = ('-Delay {0}{1}' -f $Delay, $extraArgs)
}

# --- 生成双击即用的入口（cmd 内容保持纯 ASCII，任何语言/代码页的 Windows 都不会乱码）
$psCommon = '-NoProfile -NonInteractive -ExecutionPolicy Bypass'

$fixCmd = @"
@echo off
echo Restoring internet access (removing leftover proxy settings)...
powershell.exe $psCommon -File "$installedGuard" -Force$extraArgs
echo.
echo Done. If it says OK, open your browser - usually no reboot needed.
pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir $FixCmdName) -Value $fixCmd -Encoding ASCII
Write-Ok "已生成一键修复脚本: $(Join-Path $InstallDir $FixCmdName)"

$checkCmd = @"
@echo off
echo Network leftovers health check (no changes will be made)...
powershell.exe $psCommon -File "$installedGuard" -DryRun
echo.
pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir $CheckCmdName) -Value $checkCmd -Encoding ASCII
Write-Ok "已生成一键体检脚本: $(Join-Path $InstallDir $CheckCmdName)"

$uninstallCmd = @"
@echo off
echo Uninstalling ProxyGuard...
powershell.exe $psCommon -File "$installedInstaller" -Uninstall
echo.
pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir $UninstallCmdName) -Value $uninstallCmd -Encoding ASCII

$elevatedCmd = @"
@echo off
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe $psCommon -File "$installedInstaller" -UseTask -Delay $Delay -RepairAll -DesktopShortcut
echo.
pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir $ElevatedCmdName) -Value $elevatedCmd -Encoding ASCII

# --- 注册开机自启：计划任务优先（需管理员），失败自动回退启动文件夹
$taskArgs = '{0} -WindowStyle Hidden -File "{1}" {2}' -f $psCommon, $runner, $runnerArgs
$runLevel = 'Limited'
if ($UseTask) { $runLevel = 'Highest' }

$registered = $false
$action = $null
try {
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId (Get-CurrentUserSid) -LogonType Interactive -RunLevel $runLevel
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -StartWhenAvailable -MultipleInstances IgnoreNew `
                     -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $settings.Hidden = $true

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Force -ErrorAction Stop `
        -Description '开机后自动清理加速器/代理/VPN 客户端遗留的死系统代理，恢复上网。卸载: Install-ProxyGuard.ps1 -Uninstall' | Out-Null

    # 注册后必须回读确认：无管理员权限时 Register-ScheduledTask 会以「非终止错误」失败，
    # 只看有没有抛异常会把失败误判成成功。
    $verify = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $verify) { throw '注册命令已返回，但任务并未真正创建' }

    $registered = $true
    Write-Ok "已注册计划任务: $TaskName （登录后延迟 $Delay 秒执行，权限: $runLevel）"
} catch {
    Write-Warn "注册计划任务失败: $($_.Exception.Message)"
    Write-Warn '原因通常是：注册计划任务需要管理员权限。可以改用「安装为计划任务(需管理员).cmd」，或直接使用免提权的启动文件夹方式。'
    if ($UseTask) {
        throw '按 -UseTask 要求只使用计划任务方式，注册失败即终止。请以管理员身份重新运行。'
    }
}

# --- 可选：关机时清理（尽力而为）
if ($AtShutdown) {
    try {
        $sdAction = $action
        if (-not $sdAction) {
            $sdAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs
        }
        $sdTrigger = New-CimInstance -CimClass (Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' `
                          -ClassName 'MSFT_TaskShutdownTrigger') -ClientOnly
        $sdPrincipal = New-ScheduledTaskPrincipal -UserId (Get-CurrentUserSid) -LogonType Interactive -RunLevel $runLevel
        $sdSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                           -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        Register-ScheduledTask -TaskName $ShutdownTaskName -Action $sdAction -Trigger $sdTrigger `
            -Principal $sdPrincipal -Settings $sdSettings -Force `
            -Description '关机时清理系统代理（尽力而为：快速启动/强制关机时可能不执行）' | Out-Null
        if (Get-ScheduledTask -TaskName $ShutdownTaskName -ErrorAction SilentlyContinue) {
            Write-Ok "已注册关机清理任务: $ShutdownTaskName （快速启动/强制关机时可能不执行）"
        }
    } catch {
        Write-Warn "注册关机任务失败（不影响开机自动修复）: $($_.Exception.Message)"
    }
}

# --- 兜底：计划任务不可用时用启动文件夹（免管理员权限）
if (-not $registered) {
    try {
        if (-not (Test-Path -LiteralPath $StartupFolder)) {
            New-Item -ItemType Directory -Path $StartupFolder -Force -ErrorAction Stop | Out-Null
        }
        $startupCmd = @"
@echo off
start "" /min powershell.exe $taskArgs
"@
        $startupCmdPath = Join-Path $StartupFolder $StartupCmdName
        Set-Content -LiteralPath $startupCmdPath -Value $startupCmd -Encoding ASCII -ErrorAction Stop
        if (Test-Path -LiteralPath $startupCmdPath) {
            Write-Ok "已改用启动文件夹方式（免管理员权限）: $startupCmdPath"
        } else {
            throw '启动项文件未创建成功'
        }
    } catch {
        Write-Warn "启动文件夹方式也失败: $($_.Exception.Message)"
        Write-Warn '请手动把下面的命令放进「启动」文件夹或任务计划程序：'
        Write-Warn ('  powershell.exe ' + $taskArgs)
    }
}

# 计划任务注册成功时，清掉可能残留的启动项，避免开机执行两次
if ($registered) { Remove-StartupEntry }

# --- 可选的桌面快捷方式
if ($DesktopShortcut) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnkPath = Join-Path $desktop '修复上网.lnk'
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($lnkPath)
        $lnk.TargetPath       = Join-Path $InstallDir $FixCmdName
        $lnk.WorkingDirectory = $InstallDir
        $lnk.Description      = '清理加速器/代理/VPN 遗留的系统代理，恢复上网'
        $lnk.Save()
        Write-Ok "已创建桌面快捷方式: $lnkPath"
    } catch {
        Write-Warn "创建桌面快捷方式失败: $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Step '安装完成。'
if ($registered) {
    Write-Host "  自启方式 : 计划任务 $TaskName（登录后延迟 $Delay 秒，权限 $runLevel）"
} else {
    Write-Host "  自启方式 : 启动文件夹 $StartupCmdName（登录后延迟 $Delay 秒）"
}
if ($Watch) { Write-Host "  运行模式 : 常驻监视，每 $WatchIntervalMinutes 分钟检查一次" }
else        { Write-Host '  运行模式 : 只在登录后检查一次' }
Write-Host "  脚本位置 : $runner"
Write-Host "  日志位置 : $(Join-Path $InstallDir 'logs\proxyguard.log')"
Write-Host "  一键修复 : $(Join-Path $InstallDir $FixCmdName)"
Write-Host "  一键体检 : $(Join-Path $InstallDir $CheckCmdName)"
Write-Host "  立即生效 : powershell -NoProfile -ExecutionPolicy Bypass -File `"$installedGuard`" -Force"
Write-Host "  立即体检 : powershell -NoProfile -ExecutionPolicy Bypass -File `"$installedGuard`" -DryRun"
Write-Host "  卸载     : powershell -NoProfile -ExecutionPolicy Bypass -File `"$installedInstaller`" -Uninstall"
exit 0
