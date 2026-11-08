---
name: c-drive-cleanup
description: 诊断并安全清理 Windows 系统盘（通常是 C 盘）空间，可迁移应用数据到其他分区。当用户说 C 盘满了、C 盘红了、C 盘只剩几 G、磁盘空间不足、清理垃圾文件、给 C 盘腾空间、系统盘告急，或问"我的 C 盘为什么又满了""怎么清 C 盘""能不能把软件数据挪到 D 盘"时使用。也适用于帮别人远程清理电脑。即使对方没明说"清理"二字，只要在抱怨磁盘空间或想让电脑变快，也应使用本技能。
---

# C 盘清理

Windows 系统盘空间清理技能。核心思路：**先看证据，再分层清理，最后迁移根治**。

## 三条铁律

1. **先扫描，后删除。** 不扫描就删等于赌博。别人电脑上你不知道的目录一律当作用户数据。
2. **只删可再生文件。** 判断标准：删掉之后该应用下次启动能否自动重建？能 → 可删；不能 → 不能删。
3. **破坏性操作要显式授权。** 关休眠、删还原点、删 Windows.old、`/ResetBase` 都有代价，必须让用户知道代价并同意。

## 工作流

### 第 1 步：扫描（只读）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/scan.ps1
```

需要完整结果（含 `C:\Windows` 各类目）时加 `-Full`。要机器可读输出加 `-Json`。

扫描输出的 `Verdict` 列就是判断依据：

| Verdict | 含义 | 动作 |
|---|---|---|
| `SAFE` | 可再生缓存 | 可直接清 |
| `REVIEW` | 应用数据/系统目录 | 需逐个判断 |
| `DISM` | 只能通过 DISM 处理 | 不能手删 |
| `KEEP` | 不该删 | 跳过 |
| `NEVER` | 删了会坏系统或导致软件无法卸载 | 绝对不碰 |

### 第 2 步：看数字，定位主要矛盾

优先看三个数：

- **可用空间**：低于 2 GB 时 Windows 更新、页面文件、多数安装程序都会失败，属于紧急状态
- **单个最大项**：通常占 30% 以上的那 1~2 项就是全部问题所在
- **是否已有 junction**：`EXISTING JUNCTIONS` 段列出已迁移的目录，这些目录的"大小"其实是别的盘的数据，不能重复计算

常见的大户排序（经验值）：

1. GPU 着色器缓存（`DXCache` / `D3DSCache`）—— 5~20 GB，打游戏或用 3D 软件必涨
2. `hiberfil.sys` —— 内存的 40%~100%，笔记本常见 8~16 GB
3. `Windows.old` / `$WINDOWS.~BT` —— 系统升级残留，10~30 GB
4. Windows 更新缓存 —— 2~10 GB
5. 微信/QQ 文件目录 —— 5~50 GB
6. 系统还原点 —— 最多占磁盘 10%
7. Electron 应用的 `*-updater` 目录 —— 每个几百 MB

### 第 3 步：分层清理

按风险从低到高，逐层推进。**每层跑完都看一次剩余空间，够用就停。**

#### L0 无风险（不需要管理员）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean-safe.ps1 -DryRun   # 先看
powershell -ExecutionPolicy Bypass -File scripts/clean-safe.ps1           # 再删
```

覆盖 GPU 着色器缓存、用户临时文件、崩溃转储、错误报告、缩略图缓存、`*-updater` 暂存、NVIDIA 驱动包缓存、回收站。

可选开关：
- `-IncludeBrowserCache` 清浏览器 HTTP 缓存（不动书签/密码/登录态）
- `-IncludeNpmCache` 清 npm/pnpm/yarn/uv/pip 缓存

#### L1 系统级（需要管理员）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean-admin.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/clean-admin.ps1
```

默认只做保守项：Windows 更新下载缓存、`C:\Windows\Temp`、Prefetch、内核报告、minidump、MEMORY.DMP，以及**保留卸载能力**的 DISM 组件清理。

带代价的开关（**必须逐个征得同意**）：

| 开关 | 代价 | 收益 |
|---|---|---|
| `-DisableHibernate` | 失去休眠和快速启动 | 8~32 GB |
| `-DeleteRestorePoints` | 失去系统回滚 | 最多磁盘 10% |
| `-RemoveWindowsOld` | 无法退回旧版 Windows | 10~30 GB |
| `-ResetBase` | 无法卸载已安装的更新 | 额外 1~3 GB |

用户自己清理时，也可以引导他用图形界面（零学习成本，效果相同）：`Win+I` → 系统 → 存储 → 临时文件，或 `cleanmgr`。

### 第 4 步：迁移（根治）

清缓存只是止血。C 盘反复爆满的真正原因是**应用数据默认全落在系统盘**。迁移一次，长期受益。

```powershell
# 先干跑确认
powershell -ExecutionPolicy Bypass -File scripts/migrate-appdata.ps1 `
  -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat -DryRun

# 确认无误再执行
powershell -ExecutionPolicy Bypass -File scripts/migrate-appdata.ps1 `
  -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat
```

脚本内置六道保险：拒绝已是 junction 的源 → 检查目标盘空间 → 停进程 → robocopy 复制 → **比对文件数与字节数** → 先改名再建链接、验证通过才删原件。任一步失败自动回滚。

**迁移优先级**（按收益/风险比）：

| 目标 | 典型大小 | 说明 |
|---|---|---|
| `%APPDATA%\Tencent` | 4~20 GB | 微信/QQ，必须先退出客户端 |
| `%APPDATA%\kingsoft` + `%LOCALAPPDATA%\Kingsoft` | 3~10 GB | WPS |
| `%LOCALAPPDATA%\Programs\<App>` | 1~10 GB | 装在用户目录的应用本体 |
| `%USERPROFILE%\.lmstudio` / `.ollama` | 2~50 GB | 本地大模型 |
| `%LOCALAPPDATA%\Docker` / WSL 发行版 | 5~50 GB | 需要 `wsl --export/--import` 或 Docker 设置里改磁盘位置 |
| `C:\android-sdk` | 3~10 GB | Android SDK，可整体移到其他盘并改 `ANDROID_HOME` |

**有原生设置的优先用原生设置**，不要用 junction：微信（设置→文件管理→更改路径）、WPS（备份中心）、Steam（添加库文件夹）、Docker Desktop（Resources→Advanced→Disk image location）、Chrome/Edge 下载目录。原生设置更稳，不会被应用更新破坏。

**动手前的检查清单**：
- 目标盘剩余空间 ≥ 源目录 × 1.1
- 应用已完全退出（托盘图标也要退）
- 源目录不是 junction / 符号链接
- 目标盘不是移动硬盘或网络盘

### 第 5 步：复盘并防复发

清理完必须告诉用户三件事：

1. **这次清了多少，从多少到多少**
2. **哪些东西会再长回来**（GPU 缓存、更新缓存、updater）
3. **什么时候需要再清**（建议可用空间低于 15% 时）

防复发建议：

- 开启存储感知：`Win+I` → 系统 → 存储 → 存储感知，自动删临时文件和回收站
- 给 GPU 缓存目录定期清理（本技能的 `clean-safe.ps1` 可以挂到计划任务，每月一次）
- 把能迁移的大户按第 4 步迁走
- 关闭不用的开机自启程序

## 绝对不要删的东西

| 路径 | 后果 |
|---|---|
| `C:\Windows\Installer` | 所有软件无法卸载/修复/更新（这是网上最多人踩的坑） |
| `C:\Windows\WinSxS`（手删） | 系统组件损坏，无法启动；只能用 DISM |
| `C:\Windows\System32` | 系统直接崩 |
| `C:\ProgramData\<应用>`（除已知缓存） | 应用配置、许可证、数据库 |
| `%APPDATA%\<应用>` | 登录态、配置、聊天记录 |
| 桌面/文档/下载/图片/视频 | 用户数据 |
| OneDrive / 坚果云 / 百度网盘同步目录 | 删本地会同步删除云端 |
| `pagefile.sys`（直接删文件） | 系统不稳定；要改用系统设置 |
| 任何 `.vhdx`（WSL/Docker/虚拟机磁盘） | 虚拟磁盘损坏，数据全丢 |

## 特殊情况处理

**剩余空间 < 1 GB 时**：先只做 L0 的 GPU 缓存和 Temp，再关休眠（通常是最大单项），让系统恢复到可操作状态，然后才做诊断扫描——因为空间极小时 DISM、Windows 更新、甚至扫描的临时写入都可能失败。

**扫描报"访问被拒绝"**：`System Volume Information` 需要管理员才能读，普通权限读到 0 GB 不代表真的空。用 `vssadmin list shadowstorage` 查还原点真实占用。

**`gci` 等别名报错，提示绑定到 `Get-Process`**：这台机器的别名被第三方软件改过。一律改用完整命令名（`Get-ChildItem`、`Where-Object`、`ForEach-Object`），并加 `-LiteralPath`。

**PowerShell 卡在 `>>` 提示符**：上一次多行粘贴被截断，留下了未闭合的括号或引号。按 `Ctrl+C` 数次退出，或关窗口重开。远程操作时**一条一条粘**，不要一次粘多行。

## 参考文档

- `docs/cleanup-plan.md` —— 完整清理方案（分级清单、逐应用迁移路径、故障排查）
- `docs/safety-rules.md` —— 删除白名单/黑名单与判断逻辑
- `scripts/scan.ps1` —— 只读诊断
- `scripts/clean-safe.ps1` —— 用户级缓存清理
- `scripts/clean-admin.ps1` —— 系统级清理
- `scripts/migrate-appdata.ps1` —— 目录迁移 + junction

## 输出要求

清理结束后给用户一份简短报告，包含：清理前后的可用空间、每一项释放了多少、哪些项目被跳过及原因、下一步建议。不要只报一个总数，用户需要知道钱花在哪。
