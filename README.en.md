# ProxyGuard

**Fixes the "used a VPN/proxy client, shut down, and now half my apps have no internet" problem — automatically.**

On every logon, ProxyGuard checks the Windows system proxy. If it points at a **dead local port**
left behind by a client that was killed during shutdown, it restores direct access. No manual work.

[![CI](https://github.com/kuui0609/ProxyGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/kuui0609/ProxyGuard/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue.svg)](README.en.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](README.en.md)
[![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen.svg)](README.en.md)

**English** | [简体中文](README.md)

---

## 1. Do you have this problem?

- You ran an accelerator / proxy client / VPN, then **shut the machine down**;
- On the next boot, **your browser, Steam, the Microsoft Store and launchers have no internet**,
  while QQ / WeChat still work;
- In *Control Panel → Internet Options → Connections → LAN settings*, the
  **"Use a proxy server for your LAN"** box is still ticked and points at something like
  `127.0.0.1:26561` or `127.0.0.1:7897` — where **nothing is listening**;
- Clearing that tick (or ticking "Automatically detect settings") and clicking OK **fixes it instantly**;
- You have to do this every single time.

## 2. Why it happens (30 seconds)

These clients set the **system proxy** to `http://127.0.0.1:<port>` so that traffic goes through them.

- On a clean exit they restore the previous value;
- **but during shutdown the process is killed by Windows and never gets the chance**;
- so the "proxy pointing at a dead port" is persisted and takes effect again on the next boot;
- Windows sends all proxy-aware traffic to a port nobody is listening on → no internet.

> Your manual fix (unticking the proxy) is exactly the same thing ProxyGuard does automatically.

## 3. Why not "clean up at shutdown"?

Because it cannot be relied on. Windows 10/11 enables **Fast Startup** by default:
"shutdown" is really hibernate + resume, so shutdown scripts and shutdown scheduled tasks
**frequently never run**. Hard power-offs, crashes and "End task" obviously do not run them either.
The client's own "restore proxy on exit" fails for the same reason.

**So the repair belongs right after logon** — that is the one moment guaranteed to happen.

## 4. Emergency fix

| Situation | What to do |
| --- | --- |
| No internet, suspect a leftover proxy | Double-click the **`修复上网`** (`Fix internet`) shortcut |
| Want to know what is actually wrong | Double-click **`一键体检.cmd`** (`Health check`) — read-only, changes nothing |
| Command line | `powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\ProxyGuard\Reset-Proxy.ps1" -Force` |
| See what it did on each boot | `%LOCALAPPDATA%\ProxyGuard\logs\proxyguard.log` |

## 5. Quick start

1. Click **`Code` → `Download ZIP`** and extract anywhere (e.g. `D:\Tools\ProxyGuard`);
2. Double-click **`安装.cmd`** (`Install`) — **no administrator rights required**;
3. Done. **It takes effect automatically ~20 seconds after your next logon.**

Or, with git:

```bash
git clone https://github.com/kuui0609/ProxyGuard.git
cd ProxyGuard
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProxyGuard.ps1 -DesktopShortcut
```

To also auto-repair DNS / WinHTTP / hosts (those need admin), double-click
`安装为计划任务(需管理员).cmd` and accept the single UAC prompt. It registers a logon
scheduled task running with highest privileges.

> Note: the launcher file names are in Chinese because the primary audience is Chinese-speaking
> users; their *contents* are plain ASCII, and the PowerShell scripts are UTF-8 with BOM, so they
> run on any Windows locale.

## 6. What it does / doesn't do

**Does**

| When | Action |
| --- | --- |
| ~20 s after logon (configurable) | Probes whether anything listens on the port the system proxy points to |
| Nothing listening (= dead proxy) | Restores direct access **and notifies Windows immediately** (WinINET refresh + LAN-settings blob sync + DNS cache flush) |
| Something is listening (client running) | **Does nothing at all** — never disturbs a working VPN/proxy |
| Watch mode (optional) | Re-checks every 5 minutes, so a mid-session client crash also self-heals |
| Before every change | Backs up the previous settings to `logs\backup\*.json` (keeps the last 20) |

**Does not**

- never touches a working proxy (that is what the liveness probe is for);
- never changes your "Automatically detect settings" preference unless you pass `-AutoDetect` / `-NoAutoDetect`;
- never removes remote PAC URLs (only dead *localhost* PACs);
- never modifies the routing table (it only reports — see the limitations in `README.md`);
- never talks to the network, never downloads, never collects anything.

## 7. Health report (read-only)

`一键体检.cmd` prints 9 findings and changes nothing:

```
================ 网络残留体检 ================
[1] 系统代理(当前用户) : 已开启 -> 127.0.0.1:26561   [端口无人监听 → 死代理，就是它导致上不了网]
[2] 自动配置脚本(PAC)  : 未设置   [正常]
[3] 自动检测设置       : 未勾选
[4] 系统代理(计算机级) : 未设置   [正常]
[5] WinHTTP 代理       : 未设置（直连）   [正常]
[6] 网卡 DNS           : WLAN -> 172.20.10.1   [可用]
[7] 默认路由           : WLAN 网关 172.20.10.1 有效跃点 30   [当前优先]
[8] hosts 文件         : 正常（无指向本机的条目）
[9] 管理员权限         : 否
==============================================
```

It covers: per-user proxy, PAC, auto-detect, machine-wide (Group Policy) proxy,
WinHTTP proxy, adapter DNS, default routes / virtual adapters, hosts file, current privileges.

## 8. FAQ

**No new lines in the log after booting?**
The startup entry was blocked. Security suites (360, Huorong, etc.) and "optimizer/cleaner" tools
often disable startup entries. Whitelist `ProxyGuard.cmd`, or switch to the scheduled-task install.

**My antivirus flags it?**
"A startup entry that launches a hidden PowerShell" is genuinely a common malware pattern, so the
warning is not unreasonable. Mitigations: every script is **plain-text `.ps1`** you can read; nothing
ever touches the network; whitelist the install folder; or skip autostart entirely and just keep the
desktop shortcut for manual one-click repair.

**My client uses a different port — do I need to configure anything?**
No. The script reads whatever the system proxy currently points to.

**The log always says "skipped" but I still have no internet?**
The port *is* being listened on, but that program is not working (tunnel down, subscription expired,
kill switch engaged). Use `修复上网` (`-Force`) to force direct access.

## 9. How it works

The LAN settings dialog maps to
`HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`:
`ProxyEnable`, `ProxyServer`, `AutoConfigURL` (PAC), `AutoDetect` (WPAD).
There is also a hidden binary value `Connections\DefaultConnectionSettings` that backs the dialog —
it must be updated too, otherwise the checkboxes would show the wrong state.

ProxyGuard only rewrites the flags field (offset 8: `DIRECT=1, PROXY=2, AUTO_PROXY_URL=4, AUTO_DETECT=8`)
and increments the change counter (offset 4); **every other byte is preserved verbatim** — the test
suite asserts exactly that.

After writing, it calls WinINET `InternetSetOption(INTERNET_OPTION_SETTINGS_CHANGED)` +
`(INTERNET_OPTION_REFRESH)` so running applications pick up the change without a reboot.

The safety design: a TCP connect to the configured `host:port` decides dead vs. alive;
an address that cannot be parsed (e.g. `proxy.corp.local`) is only reported, never acted on.

## 10. Development

No dependencies — deliberately no Pester, no modules, nothing to install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Conventions.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyGuard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 -Version 1.0.0
```

Both test scripts exit with `0` on success and with the number of failures otherwise.
`Test-ProxyGuard.ps1` works on a **shadow registry key** and spins up its own listening socket to
impersonate a live proxy, so it is fully hermetic and never touches your real settings.

Three hard conventions (checked by CI) because Windows PowerShell 5.1 decodes BOM-less UTF-8 as ANSI,
which silently breaks script parsing: `.ps1` must be UTF-8 **with BOM**, `.cmd` must be ASCII-only,
and all code must run on **Windows PowerShell 5.1**.

## 11. License

[MIT](LICENSE) — free to use, modify and redistribute; just keep the copyright notice.

## Disclaimer

This tool modifies Windows **system proxy settings** (plus the DNS/hosts/WinHTTP repairs you
explicitly opt into). Every change is backed up first and only demonstrably-dead proxies are touched
by default, but any system-level change carries risk. Use at your own judgement; the author is not
liable for any consequences. The tool contains **no networking code** and collects nothing.
