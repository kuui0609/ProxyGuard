# 贡献指南

感谢你愿意花时间改进 ProxyGuard！无论是报 bug、提建议还是改代码，都非常欢迎。

English speakers: contributions are welcome — feel free to open an issue or PR in English.

---

## 一、报告问题（最有用的贡献方式）

这类工具的问题几乎都和**具体环境**有关，所以信息越全越好。提 issue 时请附上：

1. **体检报告**（这个最关键）
   双击 `一键体检.cmd`，把输出的全部内容贴进 issue。
   它包含系统代理、PAC、WinHTTP、DNS、默认路由、hosts、权限共 9 项结论，且**不会做任何修改**。

2. **运行日志**
   `%LOCALAPPDATA%\ProxyGuard\logs\proxyguard.log`（如果装过的话）。

3. **环境信息**
   - Windows 版本（`winver` 截图或版本号，例如 Windows 11 24H2 / 26100）
   - 你用的客户端名称和版本（Watt Toolkit / Clash Verge / v2rayN / 自建 VPN 客户端……）
   - 是否以管理员身份运行过

4. **复现步骤**：做什么操作之后出现的问题（例如"用 XX 加速器后直接关机，再开机就不能上网"）。

> 如果问题涉及"工具误改了我不该改的设置"，请**先别急着卸载**，把日志和备份
> （`%LOCALAPPDATA%\ProxyGuard\logs\backup\`）一并附上，这样能快速定位。

---

## 二、提交代码

```bash
# 1. Fork 本仓库，然后克隆你自己的 fork
git clone https://github.com/<你的用户名>/ProxyGuard.git
cd ProxyGuard

# 2. 建一个分支（名字随意，建议能说明意图）
git checkout -b fix/pac-detection

# 3. 改代码，然后本地跑测试（见下一节）

# 4. 提交并推送
git add .
git commit -m "fix: 修正 PAC 地址解析"
git push origin fix/pac-detection
```

然后在 GitHub 上点 **Compare & pull request**。

提交信息建议用 `feat:` / `fix:` / `docs:` / `test:` / `refactor:` 这类前缀，中文英文都可以。

---

## 三、本地跑测试

不需要安装任何东西（**本项目有意不依赖 Pester 或任何第三方模块**，保持"下载即用"）：

```powershell
# 规范检查：编码、BOM、.cmd 是否纯 ASCII、语法能否解析
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Conventions.ps1

# 行为测试：在影子注册表项上跑完整判定矩阵（不会碰你真实的代理设置）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyGuard.ps1
```

两个脚本都会返回退出码：**0 = 全部通过**，非 0 = 失败数量。

`Test-ProxyGuard.ps1` 会在 `HKCU\Software\ProxyGuardTest` 下建一个临时项，
跑完自动删除；并且会自己开一个本地监听端口当"活代理"，所以任何机器上都能跑。

---

## 四、代码约定（重要）

这几条是这个项目的硬性要求，CI 会检查其中的前三条：

1. **`.ps1` 必须保存为 UTF-8 with BOM。**
   Windows PowerShell 5.1 读取「无 BOM 的 UTF-8」时会按系统 ANSI 代码页解码，
   中文变乱码 → 直接语法解析失败 → 脚本完全跑不起来。仓库里的 `.editorconfig` 已帮你设置好编码。

2. **`.cmd` / `.bat` 的内容必须是纯 ASCII。**
   文件名可以用中文（双击友好），但文件内容不能有非 ASCII 字符，否则在非中文代码页的 Windows 上会乱码。

3. **必须兼容 Windows PowerShell 5.1**（Windows 10/11 自带的版本），不能使用 7.x 专有语法：
   - 不能用三元运算符 `? :`
   - 不能用空合并 `??` / `??=`
   - 不能用 `-Parallel`、`Get-ChildItem -FollowSymlink` 等新参数
   - 数组 splat（`@('a','b')`）是**按位置**传参的；要传具名参数请用哈希表 splat

4. **不引入第三方依赖**：不要求用户装模块、不用 Pester、不联网下载。所有功能只用系统自带能力实现。

5. **不新增网络行为**：除了"对代理端口做一次 TCP 连接探测"，不要发起任何网络请求、不要上报数据。

6. **危险操作要有闸门**：凡是会改系统设置的功能，必须有「智能判定 → 只报告不修改 → 显式开关」这三层设计，
   并且改前备份。这条是本项目的立身之本。

7. 改动用户可见行为时，请同步更新 `README.md`、`README.en.md` 和 `CHANGELOG.md`。

---

## 五、代码结构

| 文件 | 说明 |
| --- | --- |
| `Reset-Proxy.ps1` | 核心。体检（`Get-*` / `Write-Report`）+ 修复（`Set-CleanProxyState` / `Invoke-*Fix`） |
| `Watch-Proxy.ps1` | 常驻监视，循环调用核心脚本（用哈希表 splat 传具名参数） |
| `Install-ProxyGuard.ps1` | 安装/卸载，部署编码校验、自启注册、生成启动器 |
| `tests/` | 不依赖第三方库的测试 |
| `tools/Build-Release.ps1` | 打包 zip |

核心脚本的入口在文件末尾的「主流程」一节，体检报告由 `Write-Report` 统一输出。

---

## 六、行为准则

- 对事不对人，保持友善。
- 拒绝任何把本工具用于监控、劫持他人流量的用途。
