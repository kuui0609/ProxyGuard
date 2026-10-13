# 怎么参与

## 提 issue

报 bug 的时候，最有用的东西是**「一键体检」的输出**。双击 `一键体检.cmd`，把结果整段贴上来。
它会把系统代理、PAC、WinHTTP、DNS、默认路由、hosts 这九项都列一遍，而且只读不写，跑一下没风险。
没有这段信息的话，基本只能靠猜。

再顺手带上这几样：

- Windows 版本（`winver`）
- 你用的客户端名字和版本，比如 Watt Toolkit 3.0.0 / Clash Verge Rev 2.0.3
- 什么操作之后出的问题
- `%LOCALAPPDATA%\ProxyGuard\logs\proxyguard.log` 的尾部

如果问题是"这工具改了我本来不想改的东西"，先别卸载，把 `logs\backup\` 里的文件一起发过来。

## 改代码

```bash
git clone https://github.com/<你的用户名>/ProxyGuard.git
cd ProxyGuard
git checkout -b fix/pac-detection
# 改……
git add .
git commit -m "fix: 修正 PAC 地址解析"
git push origin fix/pac-detection
```

然后网页上点 Compare & pull request。提交信息前面加 `feat:` `fix:` `docs:` `test:` 之类的前缀就行，
中文英文都可以。

## 本地跑测试

不用装任何东西：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Conventions.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyGuard.ps1
```

第一个查编码和语法，第二个跑行为判定。退出码 0 是通过，非 0 是失败条数。两个都绿了再提 PR，
CI 里跑的是同样的东西。

## 几条硬性约定

这几条不是风格偏好，是踩过坑之后定下来的。

**1. `.ps1` 必须存成 UTF-8 with BOM。**

Windows PowerShell 5.1 读没有 BOM 的 UTF-8 文件时按系统 ANSI 代码页解码，中文变乱码，
然后语法解析失败、脚本根本跑不起来。最坑的是它静默失败：本地 PowerShell 7 测一切正常，
到用户机器（5.1）上直接什么都不发生。仓库里的 `.editorconfig` 已经设好了，
CI 也会拦。你手动改文件的时候注意别让编辑器存成"UTF-8 无 BOM"。

**2. `.cmd` / `.bat` 的内容必须是纯 ASCII。**

文件名可以是中文（双击友好），内容不行。否则在非中文代码页的 Windows 上会显示乱码。

**3. 必须兼容 Windows PowerShell 5.1。**

这是 Windows 10/11 自带的版本，不能用 7.x 才有的语法：

- 没有三元运算符 `? :`
- 没有空合并 `??` / `??=`
- 没有 `-Parallel`
- 数组 splat（`@('a','b')`）是**按位置**传参的，要传具名参数得用哈希表 splat

**4. 不引第三方依赖。**

不要求用户装模块，不用 Pester，不联网下载。所有功能都用系统自带的东西做。
"下载解压双击就能用"是这个项目的基本盘。

**5. 不新增联网行为。**

除了对代理端口做一次 TCP 连接探测，不要发任何网络请求，不要上报数据。

**6. 会改系统设置的功能，必须有三层设计。**

默认只报告不修改 → 有智能判定（确定是坏的才动手）→ 有显式开关才真的改，而且改前备份。
这条是这个项目能让人放心的原因，别破坏它。

**7. 改了用户能看到的行为，就顺手更新 README、README.en.md 和 CHANGELOG.md。**

## 代码大概长什么样

运行文件都在 `src/` 里，测试在 `tests/`，打包脚本在 `tools/`。

`Reset-Proxy.ps1` 是核心，上半部分是各种 `Get-*` 和体检报告，下半部分是修复动作，
最底下是主流程，从「主流程」那个注释往后看就能看懂。

`Watch-Proxy.ps1` 只是个循环，反复调核心脚本。

`Install-ProxyGuard.ps1` 负责部署、注册自启、生成那些双击用的 `.cmd`。

## 最后

互相客气点就行。另外这个项目不接受任何用来监控或劫持别人流量的用途。
