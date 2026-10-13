# 更新日志

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号用语义化版本。

## [1.0.0] - 2026-10-13

第一个版本。

- `Reset-Proxy.ps1`：核心脚本。先做九项体检（用户级代理、PAC、自动检测、计算机级代理、
  WinHTTP 代理、网卡 DNS、默认路由和虚拟网卡、hosts、当前权限），再把指向死端口的系统代理
  恢复成直连。
- 清理前先对代理端口做一次 TCP 连接：连得上就说明客户端在正常运行，直接退出什么都不改。
- 改完会调 WinINET 的 `InternetSetOption` 通知系统，不用重启。
- 同时修复「局域网设置」对话框背后的二进制数据 `Connections\DefaultConnectionSettings`，
  只改标志位和计数器，其余字节原样保留。
- 每次修改前把原设置备份到 `logs\backup\`，保留最近 20 份。
- 可选修复项，默认关闭：`-IncludeWinHttp`、`-FixDns`、`-FixMetric`、`-FixHosts`、`-RepairAll`。
- `Watch-Proxy.ps1`：可选常驻监视，每 N 分钟检查一次，客户端中途崩了也能自动恢复。
- `Install-ProxyGuard.ps1`：安装器。部署脚本到 `%LOCALAPPDATA%\ProxyGuard`，写入时强制加
  UTF-8 BOM 并回读确认；优先注册计划任务（注册后回读校验，避免把失败当成成功），不行就
  自动退回启动文件夹。
- 三个双击即用的启动器：`安装.cmd`、`卸载.cmd`、`一键体检.cmd`。内容是纯 ASCII，运行前会
  先把同目录的 `.ps1` 修成 UTF-8 BOM，防止复制粘贴转存把编码弄坏。
- 自带测试，不依赖 Pester。行为测试跑在临时注册表项上，自己开一个监听端口当"活代理"，
  所以在任何机器上结果都一样，也不会碰使用者真实的设置。
- GitHub Actions：推送时跑编码规范 + 语法 + 行为测试，推 `v*` 标签时自动打包发 Release。
