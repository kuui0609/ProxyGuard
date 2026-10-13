# ProxyGuard

**No more opening Control Panel after every reboot just to get your internet back.**

At logon it checks the Windows system proxy. If your proxy client left one behind before shutdown,
it switches back to a direct connection.

[![CI](https://github.com/kuui0609/ProxyGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/kuui0609/ProxyGuard/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue.svg)](README.en.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](README.en.md)
[![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen.svg)](README.en.md)

[简体中文](README.md) | **English**

---

## 1. The problem

- You run an accelerator or proxy client, then shut the machine down.
- On the next boot, **browsers, Steam, the Microsoft Store and similar apps have no internet**.
- You open Control Panel → Network and Internet → Internet Options → Connections → LAN settings
  and the proxy box is still ticked, pointing at something like `127.0.0.1:26561`.
- You untick it (or tick "Automatically detect settings"), click OK, and the internet comes back.
- You have to do this every single time.

## 2. Why it happens

These clients work by pointing the system proxy at a port they listen on locally, so traffic goes
through them first. On a clean exit they restore the previous setting. But when you shut down,
Windows kills the process before it gets the chance — so the leftover proxy is still in effect after
the next boot, and Windows keeps sending traffic to a port where nothing is listening.

## 3. No internet right now?

| Situation | What to do |
| --- | --- |
| No internet | Double-click the **`修复上网`** (Fix internet) shortcut on the desktop |
| Want to know what's actually wrong | Double-click **`一键体检.cmd`** (Health check) — read-only, changes nothing |
| Command line | `powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\ProxyGuard\Reset-Proxy.ps1" -Force` |
| What it did after booting | `%LOCALAPPDATA%\ProxyGuard\logs\proxyguard.log` |

## 4. Download

### A. Download and run

1. Grab `ProxyGuard-1.0.0.zip` from [Releases](https://github.com/kuui0609/ProxyGuard/releases).
   That archive is flat, so just extract it anywhere (e.g. `D:\Tools\ProxyGuard`).
2. Double-click **`安装.cmd`** (Install). **No administrator rights needed.**
3. That's it. **It takes effect about 20 seconds after your next logon.**

> If you downloaded the source via `Code` → `Download ZIP`, the runnable files live in the `src` folder.

### B. git clone

```bash
git clone https://github.com/kuui0609/ProxyGuard.git
cd ProxyGuard
```

Then double-click `src\安装.cmd`, or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\Install-ProxyGuard.ps1 -DesktopShortcut
```

## 5. What it does

| When | What it does |
| --- | --- |
| ~20 seconds after logon (configurable) | Probes whether anything is listening on the port the system proxy points at |
| Nothing is listening (= dead proxy) | Restores a direct connection and **notifies Windows immediately**: WinINET refresh + LAN-settings blob sync + DNS cache flush |
| Something *is* listening (client running normally) | Leaves your running accelerator/VPN alone |
| Watch mode (optional at install) | Checks every 5 minutes, so a mid-session crash also self-heals |
| Before every change | Backs up the previous settings to `logs\backup\*.json` (keeps the last 20) |

What it will **not** do:

- it never touches a proxy that is working normally;
- it does not change your "Automatically detect settings" preference;
- it does not delete remote PAC URLs — only dead *localhost* PACs are cleaned up;
- it does not modify the routing table.

## 6. FAQ

**Q: Nothing new in the log after booting?**
The startup entry got blocked. Whitelist `ProxyGuard.cmd`, or switch to the scheduled-task install
(run `安装为计划任务(需管理员).cmd`).

**Q: The log keeps saying "skipped" but I still have no internet.**
Use `修复上网` (with `-Force`) to force a direct connection.

**Q: Will it conflict with the accelerator I'm using?**
No. If something is listening on the port, it doesn't touch anything.

**Q: How do I uninstall?**
Double-click `卸载.cmd`. It stops the watcher, removes the scheduled task, the startup entry, the
desktop shortcut and the install folder. No resident process is left behind.

## 7. Options

### `Reset-Proxy.ps1`

| Option | What it does |
| --- | --- |
| `-DryRun` | report only, change nothing (same as `一键体检.cmd`) |
| `-Force` | skip the liveness check, go direct no matter what (for emergencies) |
| `-Delay <sec>` | wait N seconds before checking (used at logon; default 20) |
| `-ProxyPort <port>` | probe this port instead of parsing the proxy address |
| `-AutoDetect` / `-NoAutoDetect` | force the "Automatically detect settings" checkbox on/off (left alone by default) |
| `-KeepAutoConfigURL` | keep the PAC URL (by default only dead localhost PACs are removed) |
| `-IncludeWinHttp` | also reset the WinHTTP proxy (needs admin) |
| `-FixDns` | also repair a suspected dead DNS setting (needs admin, very conservative) |
| `-FixMetric` | also handle a virtual adapter stealing the default route (needs admin, probes first) |
| `-FixHosts` | also comment out hosts entries pointing at `127.0.0.1` (needs admin, reversible) |
| `-RepairAll` | same as `-IncludeWinHttp -FixDns -FixMetric -FixHosts` |
| `-Quiet` | no console output, and no log entries when nothing happened |

### `Install-ProxyGuard.ps1`

| Option | What it does |
| --- | --- |
| `-Delay <sec>` | logon delay, default 20 |
| `-Watch` / `-WatchIntervalMinutes <n>` | background watcher (default interval 5 minutes) |
| `-AutoDetect` / `-IncludeWinHttp` / `-RepairAll` | passed through to the guard script |
| `-AtShutdown` | also register a shutdown task (best effort — Fast Startup often skips it) |
| `-DesktopShortcut` | create a desktop shortcut |
| `-UseTask` | scheduled task only, running with highest privileges (needs admin) |
| `-InstallDir <path>` | install to a different folder |
| `-Uninstall` | remove everything |

## 8. Implementation notes

### 1. Which setting it changes

「Internet Options → Connections → LAN settings」maps to the registry key
`HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`:

| Registry value | Dialog control | Notes |
| --- | --- | --- |
| `ProxyEnable` | Use a proxy server for your LAN | `1` = enabled |
| `ProxyServer` | Address / Port | clients write `127.0.0.1:7897`, `http://127.0.0.1:7897`, and `http=...;https=...` |
| `AutoConfigURL` | Use automatic configuration script | PAC address |
| `AutoDetect` | Automatically detect settings | WPAD |

There is also a hidden binary value, `Connections\DefaultConnectionSettings`, which is what the
dialog actually reads. It has to be updated as well, otherwise the checkboxes in the Control Panel
still show the old state. Its layout:

```
offset 0  : version (0x46)
offset 4  : change counter (incremented on every write)
offset 8  : flags  DIRECT=1, PROXY=2, AUTO_PROXY_URL=4, AUTO_DETECT=8
offset 12 : proxy string, bypass list, PAC string ...
```

ProxyGuard rewrites **the flags at offset 8** and increments **the counter at offset 4**; every other
byte is preserved verbatim (the test suite asserts exactly that).

### 2. Why it has to "notify" Windows

Writing the registry alone is not enough — many running applications don't re-read the settings
immediately. So after a change it calls WinINET's
`InternetSetOption(INTERNET_OPTION_SETTINGS_CHANGED)` + `(INTERNET_OPTION_REFRESH)` and flushes the
DNS cache, which means browsers recover **without rebooting**.

### 3. The liveness check (the most important safety design in this tool)

Before cleaning anything, it opens a TCP connection to the `host:port` in `ProxyServer`:

- connects → the client is running normally, **exit, change nothing**;
- doesn't connect → dead proxy, restore a direct connection;
- can't parse a host and port out of it (corporate proxies are sometimes written as
  `proxy.corp.local`) → **warn only, don't touch it**.

### 4. Why the scripts must be saved as UTF-8 with BOM

When Windows PowerShell 5.1 reads a UTF-8 file **without a BOM**, it decodes it using the system ANSI
code page (GBK on Simplified Chinese systems). Non-ASCII text turns into mojibake and **the file
fails to parse** — the script simply doesn't run, and it fails silently.

That's why the project has three hard conventions (CI checks the first two):

1. `.ps1` must be **UTF-8 with BOM** (`.editorconfig` is already set up for this);
2. `.cmd` / `.bat` contents must be **plain ASCII** (Chinese file names are fine — they're friendlier
   to double-click);
3. everything must stay compatible with **Windows PowerShell 5.1**: no `?:`, no `??`, no `-Parallel`.

> This was the biggest pitfall in this project: everything worked locally under PowerShell 7, and
> then on a user's machine (5.1) the whole script failed to parse because of the encoding. Now CI and
> the built-in tests keep an eye on it, so it won't happen again.

## 9. Verification

Verified on Windows 11 (Simplified Chinese, Windows PowerShell 5.1.26100):

| Check | Result |
| --- | --- |
| Syntax parsing of all three `.ps1` files (5.1) | Pass (it fails without a BOM, which is why deployment forces one and reads it back) |
| `127.0.0.1:26561` dead port | Cleaned correctly: `ProxyEnable 1→0`, flags `0x0B→0x01`, counter +1, **zero other byte differences** |
| `http://127.0.0.1:26561` with the **port alive** | Correctly **SKIPPED** (regression case: an early version misjudged it as dead and would have disabled a working proxy) |
| `http://` dead port / `http=...;https=...` | Cleaned correctly |
| Working manual proxy + dead local PAC | Only the dead PAC is removed, the proxy is **kept**, flags correctly `0x0F→0x0B` |
| Unparseable address (`proxy.corp.local`) | Warns only, doesn't touch it |
| `-DryRun` | Changes not a single byte |
| "Automatically detect settings" under default behaviour | Left exactly as the user had it (case: still ticked after cleanup, flags `0x09`) |
| Watch loop | Multiple rounds fine; cleans a dead proxy and logs it; exits on the stop file |
| Unattended mode (`-Quiet`) | No log noise when nothing happens; WARN / ERROR **always** get written |
| Whole flow | The live proxy settings were **never modified** (every case runs against a shadow registry key, checked item by item) |
| Extracting and running from a path with Chinese characters and spaces | Works |
| Running after deliberately removing the BOM | Fails to parse directly; the automatic repair in `安装.cmd` / `一键体检.cmd` fixes it and it runs |

Most of these cases are now frozen into `tests\Test-ProxyGuard.ps1` and re-run in CI on every commit.

## 10. Known limitations

- **Kill switches are not handled.** Some VPN clients block all traffic while disconnected. That's
  their own policy and can only be turned off inside the client. The health report hints at this by
  telling you when the preferred default route is on a virtual adapter.
- **The routing table is not changed.** `-FixMetric` only acts when the preferred default route is on
  a virtual adapter *and* the internet really is unreachable at that moment; otherwise it only
  reports. Breaking routes is much easier than breaking a proxy setting.
- **`-FixDns` is very conservative.** It only handles DNS servers that are loopback addresses with
  nothing listening on port 53 locally, or private-range addresses that are completely unreachable —
  and only on adapters set to obtain DNS automatically. Public DNS servers (like `8.8.8.8`) and any
  static DNS you configured yourself are never touched.
- **Driver-level interception is out of scope.** A few clients hook traffic via LSP/WFP. That isn't
  the system proxy, so none of this applies.
- **Windows only** (Windows 10 / 11; Windows 8.1 and later should work in theory but haven't been
  tested).

## 11. Development

**Nothing to install.** The project deliberately avoids Pester and every third-party module, so that
"download and run" stays true.

```powershell
# Convention check: encodings, BOM, ASCII-only .cmd files, syntax
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Conventions.ps1

# Behaviour test: the full decision matrix on a shadow registry key (never touches your real settings)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyGuard.ps1

# Build a release zip
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 -Version 1.0.0
```

Both test scripts report through their **exit code**: `0` = all passed, otherwise the number of
failures.

`Test-ProxyGuard.ps1`:

- creates a temporary key under `HKCU\Software\ProxyGuardTest` and deletes it afterwards;
- opens its own local TCP listener to play the part of a "live proxy", so results are reproducible on
  any machine and in any CI environment.

Code conventions, project layout and commit style are in [CONTRIBUTING.md](CONTRIBUTING.md).
Version history is in [CHANGELOG.md](CHANGELOG.md).

## 12. Contributing and license

- Issues and PRs are welcome. When reporting a bug, please include the output of `一键体检.cmd` —
  see [CONTRIBUTING.md](CONTRIBUTING.md).
- Licensed under the [MIT license](LICENSE): free to use, modify and redistribute, as long as you
  keep the copyright notice.

### Disclaimer

This tool modifies Windows **system proxy settings** (plus the DNS / hosts / WinHTTP repairs you
explicitly opt into). Every change is backed up first and by default only proxies that are
demonstrably dead are touched, but changing system settings always carries some risk. Judge for
yourself; the author is not liable for any consequences of using it.

The tool contains **no networking code at all**: it never uploads, downloads or collects anything,
and you can read every line yourself.
