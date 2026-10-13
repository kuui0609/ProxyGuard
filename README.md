# ProxyGuard · 代理守护

**解决使用代理直接关机,再次重启后需要打开控制面板才能恢复网络的繁琐步骤**

开机登录后自动检查系统代理，发现客户端被关机前留下的**代理**就恢复直连.

[![CI](https://github.com/kuui0609/ProxyGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/kuui0609/ProxyGuard/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue.svg)](README.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](README.md)
[![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen.svg)](README.md)

[English](README.en.md) | **简体中文**

---

## 一、遇到的问题

- 开加速器后直接关机,下次开机后，**浏览器、Steam、微软商店、各种启动器全都上不了网**
- 打开「控制面板 → 网络和 Internet → Internet 选项 → 连接 → 局域网(LAN)设置」，
  发现在已经**没有人用**的代理地址上还打着勾（比如 `xxx.0.0.1:xxxx`）;
- 把这个勾取消、或者勾一下「自动检测设置」，点确定才可以使用;

## 二、原因

这类客户端会把**系统代理**改成 `http://xxx.0.0.1:<端口>` —— 让系统的流量先交给它自己转发。

- 正常退出时，它会把这个设置还原；
- **但关机时进程直接被 Windows 杀掉，来不及还原**；
- 于是这个"指向死端口的代理"被原样保存下来，下次开机继续生效；
- 系统把流量发给一个**没有任何程序在监听**的端口 → 没网。

## 三、为什么不做"关机时自动清理"？

不够可靠。Win10/Win11 默认开启**快速启动**，关机其实是"休眠 + 下次恢复"，
关机脚本、关机计划任务**经常根本不执行**；强制关机、断电、蓝屏、任务管理器结束进程更不用说。
客户端自带的"退出时还原代理"也是因为同样的原因失效的。

**所以修复点放在开机登录之后** —— 那是 100% 会发生的时机。本项目就干这一件事。

## 四、断网情况下

| 场景 | 操作 |
| --- | --- |
| 无法上网 | 双击桌面上的 **`修复上网`** |
| 问题原由 | 双击 **`一键体检.cmd`**（只检查、**不做任何修改**） |
| 命令行急救 | `powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\ProxyGuard\Reset-Proxy.ps1" -Force` |
| 开机后运行的日志 | `%LOCALAPPDATA%\ProxyGuard\logs\proxyguard.log` |
## 五、快速开始

### 方式 A：下载即用（推荐，不需要 git）

1. 点本页面右上角 **`Code`** → **`Download ZIP`**，解压到任意位置（例如 `D:\Tools\ProxyGuard`）；
2. 双击 **`安装.cmd`**（**不需要管理员权限**）；
3. 看到 `安装完成` 就好了。**下次开机登录后约 20 秒自动生效。**

### 方式 B：git 克隆

```bash
git clone https://github.com/kuui0609/ProxyGuard.git
cd ProxyGuard
```

然后双击 `安装.cmd`，或：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProxyGuard.ps1 -DesktopShortcut
```

## 六、实际应用状况

**可以做的...**

| 时机 | 动作 |
| --- | --- |
| 开机登录后（默认延迟 20 秒） | 探测系统代理指向的端口有没有程序在监听 |
| 端口**无**监听（=死代理） | 恢复直连，并**立刻通知系统生效**：刷新 WinINET + 同步「局域网(LAN)设置」底层数据 + 清 DNS 缓存 |
| 端口**有**在监听（客户端正常运行） | **什么都不做**，绝不打扰你正在用的加速/VPN |
| 常驻监视模式（安装时选择） | 每 5 分钟检查一次，客户端**中途崩溃**也能自动恢复 |
| 每次修改前 | 把原设置备份到 `logs\backup\*.json`（保留最近 20 份） |

**不会做的...**

- 不会动正在正常工作的代理（上面那条"智能检测"就是干这个的）；
- 不会改你的「自动检测设置」—— **除非**你显式加 `-AutoDetect` / `-NoAutoDetect`；
- 不会删远程 PAC 地址（只清理指向 `127.0.0.1` / `localhost` 的本地失效 PAC）；
- 不会改路由表（只体检报告，理由见[第十二节](#十二已知边界)）；
- 不会联网、不会下载任何东西、不收集任何信息。

## 七、常见问题

**Q：开机后日志里没有新记录？**
说明开机自启被拦了。安全软件（360、火绒、电脑管家等）或"优化 / 清理"类工具常会禁用启动项。
把 `ProxyGuard.cmd` 放行，或者改用计划任务方式（运行 `安装为计划任务(需管理员).cmd`）。

**Q：日志里一直是"跳过清理"，但我就是上不了网？**
说明那个端口确实有程序在监听，但它自己没在工作（VPN 隧道没建立、订阅过期、节点挂了、网络锁拦住了）。
这时用「修复上网」（带 `-Force`）强制恢复直连。

**Q：为什么不做"关机时自动清理"？**
见[第三节](#三为什么不做关机时自动清理)。不是不做（安装时可加 `-AtShutdown`），而是**不能当主力**。

**Q：会不会和我正在使用的加速器冲突?**
不会。端口有监听就完全不动手，正常使用加速器时它连注册表都不会碰。

**Q：卸载**
双击 `卸载.cmd`：结束常驻监视进程、删除计划任务、启动项、桌面快捷方式和安装目录，不留常驻进程。

## 八、体检报告界面

`一键体检.cmd` 会输出 9 项结论，且**不做任何修改**：

```
================ 网络残留体检 ================
[1] 系统代理(当前用户) : 已开启 -> 127.0.0.1:26561   [端口无人监听 → 死代理，就是它导致上不了网]
[2] 自动配置脚本(PAC)  : 未设置   [正常]
[3] 自动检测设置       : 未勾选
[4] 系统代理(计算机级) : 未设置   [正常]
[5] WinHTTP 代理       : 未设置（直连）   [正常]
[6] 网卡 DNS           : WLAN -> 172.20.10.1   [可用]
[7] 默认路由           : WLAN 网关 172.20.10.1 有效跃点 30   [当前优先]
[7] 默认路由           : Radmin VPN 网关 26.0.0.1 有效跃点 9257   [备用，虚拟网卡]
[8] hosts 文件         : 正常（无指向本机的条目）
[9] 管理员权限         : 否（系统代理修复可用；WinHTTP/DNS/跃点/hosts 需要管理员）
==============================================
```

覆盖 9 个可能被客户端搞坏的地方：**用户级代理、PAC、自动检测、计算机级代理（组策略）、
WinHTTP 代理、网卡 DNS、默认路由 / 虚拟网卡、hosts 文件、当前权限**。

> 提 issue 时把这份报告贴上来，定位速度会快很多。

## 九、参数说明

### `Reset-Proxy.ps1`

| 参数 | 说明 |
| --- | --- |
| `-DryRun` | 只体检，不修改（等价于 `一键体检.cmd`） |
| `-Force` | 跳过智能检测，无条件恢复直连（急救用） |
| `-Delay <秒>` | 先等待 N 秒再检查（开机自启用；默认 20） |
| `-ProxyPort <端口>` | 手动指定探活端口（默认自动从 ProxyServer / PAC 解析） |
| `-AutoDetect` / `-NoAutoDetect` | 清理后强制勾选 / 取消勾选「自动检测设置」（默认保持原样） |
| `-KeepAutoConfigURL` | 保留 PAC 地址（默认只删本地失效 PAC） |
| `-IncludeWinHttp` | 同时重置 WinHTTP 代理（需管理员） |
| `-FixDns` | 同时修复疑似残留的死 DNS（需管理员，判定很保守） |
| `-FixMetric` | 同时纠正"虚拟网卡抢走默认路由"（需管理员，先探测再动手） |
| `-FixHosts` | 同时注释掉 hosts 里指向 `127.0.0.1` 的条目（需管理员，可逆） |
| `-RepairAll` | 等于 `-IncludeWinHttp -FixDns -FixMetric -FixHosts` |
| `-Quiet` | 不输出到控制台；且"什么都没做"时不写日志 |

### `Install-ProxyGuard.ps1`

| 参数 | 说明 |
| --- | --- |
| `-Delay <秒>` | 登录后延迟秒数，默认 20 |
| `-Watch` / `-WatchIntervalMinutes <分>` | 常驻监视模式（默认间隔 5 分钟） |
| `-AutoDetect` / `-IncludeWinHttp` / `-RepairAll` | 透传给守护脚本 |
| `-AtShutdown` | 额外注册关机清理任务（尽力而为，快速启动下可能不执行） |
| `-DesktopShortcut` | 创建桌面快捷方式 |
| `-UseTask` | 只接受计划任务方式，并让任务以最高权限运行（需管理员） |
| `-InstallDir <路径>` | 自定义安装目录 |
| `-Uninstall` | 卸载 |

## 十、原理与实现细节

### 1. 改的是哪个设置

「Internet 选项 → 连接 → 局域网(LAN)设置」对应注册表
`HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`：

| 注册表值 | 对应界面 | 说明 |
| --- | --- | --- |
| `ProxyEnable` | 为 LAN 使用代理服务器 | `1` = 启用 |
| `ProxyServer` | 地址 / 端口 | `127.0.0.1:7897`、`http://127.0.0.1:7897`、`http=...;https=...` 三种写法都有客户端在用 |
| `AutoConfigURL` | 使用自动配置脚本 | PAC 地址 |
| `AutoDetect` | 自动检测设置 | WPAD |

另外还有一个隐藏的二进制值 `Connections\DefaultConnectionSettings`，是**对话框的底层数据**，
必须一起改，否则控制面板里显示的勾选状态会和实际不一致。它的结构：

```
offset 0  : 版本号 (0x46)
offset 4  : 变更计数器（每次修改 +1）
offset 8  : 标志位  DIRECT=1, PROXY=2, AUTO_PROXY_URL=4, AUTO_DETECT=8
offset 12 : 代理串、绕过列表、PAC 串……
```

ProxyGuard 只改 **offset 8 的标志位**并把 **offset 4 的计数器 +1**，其余字节**逐字节原样保留**
（测试里就是这么校验的）。

### 2. 为什么改完要"通知系统"

只写注册表，很多已经在运行的程序不会立刻重新读取。所以改完会调用 WinINET 的
`InternetSetOption(INTERNET_OPTION_SETTINGS_CHANGED)` + `(INTERNET_OPTION_REFRESH)`，
再清一次 DNS 缓存 —— 这样浏览器等软件**不用重启系统**就能恢复。

### 3. 智能检测（本工具最重要的安全设计）

清理之前先对 `ProxyServer` 里的 `主机:端口` 做一次 TCP 连接：

- 连得上 → 客户端在正常工作，**退出，什么都不改**；
- 连不上 → 这是死代理，恢复直连；
- 地址解析不出主机和端口（例如企业代理写 `proxy.corp.local`）→ **只告警，不擅自清理**。

### 4. 为什么脚本必须存成「UTF-8 带 BOM」

Windows PowerShell 5.1 读取**没有 BOM** 的 UTF-8 文件时，会按系统 ANSI 代码页（简体中文是 GBK）解码，
脚本里的中文全部变成乱码，**直接导致语法解析失败** —— 脚本根本跑不起来，而且是静默失败。

所以本项目有三条硬编码约定（CI 会检查前两条）：

1. `.ps1` 必须 **UTF-8 with BOM**（`.editorconfig` 已帮你设置好）；
2. `.cmd` / `.bat` 的内容必须是**纯 ASCII**（文件名可以用中文，双击友好）；
3. 必须兼容 **Windows PowerShell 5.1**，不能用 `?:`、`??`、`-Parallel` 等 7.x 专有语法。

> 这是这个项目踩过的最大的坑：本地用 PowerShell 7 测试一切正常，一到用户机器上（5.1）
> 就因为编码问题整个脚本解析失败。现在有 CI + 自带测试守着，不会再有第二次。

## 十一、验证记录

在 Windows 11（简体中文，Windows PowerShell 5.1.26100）上验证：

| 验证项 | 结果 |
| --- | --- |
| 三个 `.ps1` 的语法解析（5.1） | 通过（BOM 缺失时会失败，因此部署时强制写入并回读校验） |
| `127.0.0.1:26561` 死端口 | 正确清理：`ProxyEnable 1→0`、标志 `0x0B→0x01`、计数器 +1、**其余字节零差异** |
| `http://127.0.0.1:26561` **端口活着** | 正确 **SKIP**（回归用例：早期版本会把它误判成死代理，从而误清正常工作的代理） |
| `http://` 死端口 / 复合写法 `http=...;https=...` | 正确清理 |
| 手动代理正常 + 本地 PAC 失效 | 只删失效 PAC、**保留**代理，标志位正确 `0x0F→0x0B` |
| 地址无法解析（`proxy.corp.local`） | 只告警，不擅自清理 |
| `-DryRun` | 一个字节都不改 |
| 默认行为下的「自动检测设置」 | 保持用户原样（用例：勾选状态下清理后仍为勾选，标志 `0x09`） |
| 常驻监视循环 | 连续多轮正常；发现死代理自动清理并记日志；停止标记文件可正常退出 |
| 无人值守模式（`-Quiet`） | 无变化时不写日志（不刷屏）；出现 WARN / ERROR 时**一定**会落盘 |
| 全流程 | 真实生效中的代理设置**从未被改动**（所有用例都在影子注册表项上跑，逐项核对） |
| 中文 + 空格路径下解压运行 | 正常 |
| 故意去掉 BOM 后运行 | 直接跑会语法报错；经 `安装.cmd` / `一键体检.cmd` 的自动修复后正常运行 |

以上大部分用例已经固化成 `tests\Test-ProxyGuard.ps1`，每次提交都会在 CI 里自动重跑。

## 十二、已知边界

- **不处理"网络锁 / kill switch"**：有些 VPN 客户端有"未连接时阻断全部流量"的功能，
  那是它自己的策略，只能在客户端里关掉。体检报告会提示"默认路由落在虚拟网卡上"帮你定位。
- **不改路由表**：`-FixMetric` 只在"优先默认路由落在虚拟网卡上，且此刻确实连不上外网"时才动手，
  其余情况只报告。乱改路由比代理残留更容易把网络搞坏。
- **`-FixDns` 判定很保守**：只处理【回环地址且本机 53 端口无人监听】或【私有网段地址且完全不可达】的 DNS，
  且只在该网卡是 DHCP 自动获取时才改回"自动获取"。公网 DNS（`8.8.8.8` 之类）和你手动设置的静态 DNS 永远不会被碰。
- **不处理 LSP / WFP 驱动级劫持**：少数客户端用驱动层拦截流量，那不属于系统代理，本工具覆盖不到。
- **只在 Windows 上工作**（Windows 10 / 11；理论上 Windows 8.1 及以上也能用，但没有测试过）。

## 十三、开发与测试

**不需要安装任何东西**：本项目有意不依赖 Pester 或任何第三方模块，保持"下载即用"。

```powershell
# 规范检查：编码、BOM、.cmd 是否纯 ASCII、语法能否解析
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Conventions.ps1

# 行为测试：在影子注册表项上跑完整判定矩阵（不会碰你真实的代理设置）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyGuard.ps1

# 打包出可发布的 zip
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 -Version 1.0.0
```

两个测试脚本都用**退出码**表示结果：`0` = 全部通过，非 0 = 失败数量。

`Test-ProxyGuard.ps1` 会：

- 在 `HKCU\Software\ProxyGuardTest` 下建一个临时注册表项（跑完自动删除）；
- 自己开一个本地 TCP 监听端口来扮演"活代理"，所以任何机器、任何 CI 上都能稳定复现。

代码约定、目录结构、提交规范请看 [CONTRIBUTING.md](CONTRIBUTING.md)。
变更历史请看 [CHANGELOG.md](CHANGELOG.md)。

## 十四、贡献与许可

- 欢迎提 issue 和 PR！报 bug 时请附上 `一键体检.cmd` 的输出，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 本项目使用 [MIT 许可证](LICENSE)，可以自由使用、修改、商用，只需保留版权声明。

### 免责声明

本工具会修改 Windows 的**系统代理设置**（以及你在参数中显式开启的 DNS / hosts / WinHTTP 修复项）。
虽然每次修改前都会自动备份、并且默认只处理"确定已经失效"的代理，但任何系统级修改都存在风险。
请自行评估后再使用；作者不对使用本工具造成的任何后果承担责任。

本工具**不包含任何网络功能**，不会上传、下载或收集任何数据。你完全可以自己审阅全部源码。
