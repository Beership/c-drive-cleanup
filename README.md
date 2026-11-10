# C Drive Cleanup Kit

> 给 C 盘反复爆满的人用的一套诊断 + 清理 + 迁移工具。也是可以直接装给 AI Agent 用的技能。

[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)](https://github.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 这个工具解决什么问题

C 盘满了，大多数人会做三件事之一：装个"清理大师"、手动删几个看得见的文件夹、或者干脆重装系统。这三种做法分别对应三个问题：

| 做法 | 问题 |
|---|---|
| 一键清理软件 | 你不知道它删了什么；有些会误删 `C:\Windows\Installer`，导致所有软件无法卸载 |
| 手动删文件夹 | 删错一个目录，某个软件就再也起不来 |
| 重装系统 | 治标，三个月后又满 |

**真正的原因是三个**，而它们需要三种不同的处理方式：

| 原因 | 表现 | 处理 |
|---|---|---|
| **可再生缓存** | 删了立刻重建，但会无限增长 | 定期清（`clean-safe.ps1`） |
| **一次性沉积** | 装完系统/软件后留下的垃圾，永不消失 | 清一次（`clean-admin.ps1`） |
| **应用数据默认落 C 盘** | 微信、模型、Docker 全在 C 盘 | 迁移到其他盘（`migrate-appdata.ps1`） |

这套工具做的就是：**先用 `scan.ps1` 找到证据 → 按风险分层清理 → 把顽固的大户迁移走**。

---

## 和"一键清理"的区别

- **先看后删**：扫描是独立的一步，输出每一项的路径、大小、处置建议。不扫描不删除。
- **每一项都给判定**：`SAFE` / `REVIEW` / `DISM` / `KEEP` / `NEVER`，不是笼统的"垃圾文件"。
- **干跑模式**：所有清理脚本都支持 `-DryRun`，先看清单再执行。
- **破坏性操作要显式打开**：关休眠、删还原点、删 Windows.old 这些有代价的操作默认不执行。
- **迁移带回滚**：复制后比对文件数和字节数，不达标自动回滚，原件不删。

---

## 三种使用方式

### 方式一：作为 AI Agent 技能（推荐）

仓库根目录就是一个 ZCode / Claude Code 兼容的技能。

**安装：**

```bash
# 个人级：所有项目都能用
git clone https://github.com/<your-name>/c-drive-cleanup.git ~/.zcode/skills/c-drive-cleanup

# 项目级：只在当前仓库可用
git clone https://github.com/<your-name>/c-drive-cleanup.git .agents/skills/c-drive-cleanup
```

**怎么用：** 装好之后直接用日常语言说需求，技能会自动触发：

> "我 C 盘只剩 5 个 G 了，帮我看看怎么回事"
>
> "C 盘又红了，按老规矩清一下"
>
> "帮我把微信的文件目录挪到 D 盘"
>
> "我朋友电脑 100G 的盘只剩 400M，远程怎么清"

Agent 会按 `SKILL.md` 里的流程走：扫描 → 给出判断 → 分层清理 → 询问是否迁移 → 出报告。它知道哪些能删、哪些碰不得，不会像通用助手那样给你一堆模糊建议。

**技能包含的判断逻辑：**
- 白名单（可直接删）/ 黑名单（删了会坏）/ 灰区（逐个判断）
- 每类目录的典型大小和判断依据
- 各软件的正确迁移方式（哪些用原生设置、哪些用 junction）
- 远程帮别人清电脑时的操作纪律

### 方式二：命令行直接跑（不需要 AI）

```powershell
# 1. 诊断（只读，不删任何东西）
powershell -ExecutionPolicy Bypass -File scripts/scan.ps1

# 2. 清零风险缓存（不需要管理员）
powershell -ExecutionPolicy Bypass -File scripts/clean-safe.ps1 -DryRun   # 先看
powershell -ExecutionPolicy Bypass -File scripts/clean-safe.ps1           # 再删

# 3. 清系统级缓存（需要管理员）
powershell -ExecutionPolicy Bypass -File scripts/clean-admin.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/clean-admin.ps1

# 4. 迁移大户到其他盘
powershell -ExecutionPolicy Bypass -File scripts/migrate-appdata.ps1 `
  -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat -DryRun
```

### 方式三：只读文档，手动操作

如果你的环境不允许跑脚本，直接看文档也能用：

- [docs/cleanup-plan.md](docs/cleanup-plan.md) —— 完整方案：为什么满、五级清理清单、逐应用迁移手册、防复发、故障排查
- [docs/safety-rules.md](docs/safety-rules.md) —— 什么能删、什么不能删、灰区怎么判断

文档里的每个 Windows 内置操作（存储感知、`cleanmgr`、`powercfg`、`vssadmin`、DISM）都写了具体命令或点击路径。

---

## 四个脚本

### `scan.ps1` — 只读诊断

```powershell
scripts/scan.ps1              # 快速扫描（不含 C:\Windows 内部）
scripts/scan.ps1 -Full        # 完整扫描，含每个顶层目录
scripts/scan.ps1 -Json        # 输出 JSON，便于程序处理
```

输出分区：磁盘容量、根目录系统文件、旧系统残留、已知缓存、更新暂存、顶层目录、AppData/ProgramData/Program Files、**已有 junction**。

每一项带判定：

| Verdict | 含义 | 动作 |
|---|---|---|
| `SAFE` | 可再生缓存 | 可直接清 |
| `REVIEW` | 应用数据或系统目录 | 需要判断 |
| `DISM` | 只能通过 DISM 处理 | 不能手删 |
| `KEEP` | 不该删 | 跳过 |
| `NEVER` | 删了会坏系统 | 绝对不碰 |

### `clean-safe.ps1` — 用户级缓存（免管理员）

```powershell
scripts/clean-safe.ps1 -DryRun                          # 干跑
scripts/clean-safe.ps1                                  # 执行
scripts/clean-safe.ps1 -IncludeBrowserCache             # 加清浏览器缓存
scripts/clean-safe.ps1 -IncludeBrowserCache -IncludeNpmCache   # 再加包管理器缓存
```

覆盖：GPU 着色器缓存（NVIDIA / AMD / Intel / DirectX）、用户临时文件、崩溃转储、错误报告、缩略图、`*-updater` 更新暂存、NVIDIA 驱动包、回收站。

特性：
- 自动**跳过位于 junction 下的路径**（那是别的盘的数据，删了不省 C 盘）
- 自动跳过脚本自身所在目录（防止删掉自己）
- 每项单独报告释放量和状态

### `clean-admin.ps1` — 系统级（需管理员）

```powershell
scripts/clean-admin.ps1 -DryRun                         # 干跑
scripts/clean-admin.ps1                                 # 保守清理
scripts/clean-admin.ps1 -SkipDism                       # 跳过耗时的 DISM
```

默认只做保守项：Windows 更新下载缓存、传递优化、`C:\Windows\Temp`、Prefetch、内核报告、minidump、MEMORY.DMP，以及**保留卸载能力**的 DISM 组件清理。

有代价的开关必须显式打开：

| 开关 | 收益 | 代价 |
|---|---|---|
| `-DisableHibernate` | 8~32 GB（删除 `hiberfil.sys`） | 失去休眠和快速启动，`powercfg -h on` 可恢复 |
| `-DeleteRestorePoints` | 最多磁盘的 10% | 失去系统还原能力 |
| `-RemoveWindowsOld` | 10~30 GB | 无法退回旧版 Windows |
| `-ResetBase` | 额外 1~3 GB | 无法卸载已安装的 Windows 更新 |

### `migrate-appdata.ps1` — 迁移目录（带回滚）

```powershell
scripts/migrate-appdata.ps1 -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat -DryRun
scripts/migrate-appdata.ps1 -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat
```

六道保险：

1. 拒绝源目录已经是 junction 或 reparse point
2. 检查目标盘剩余空间 ≥ 源目录 × 1.1
3. 停止指定进程
4. `robocopy` 复制
5. **比对文件数和总字节数**，不达标直接中止（原件不动）
6. 源目录先改名为 `.premove` → 建 junction → 验证可读 → 才删除副本

任何一步失败自动回滚。迁移后应用看到的还是原路径，但数据已经在别的盘。

---

## 三个典型场景

### 场景 1：C 盘只剩 3 GB，先救急

```powershell
scripts/scan.ps1          # 30 秒看清谁最大
scripts/clean-safe.ps1    # 通常能出 5~20 GB
```

如果还不够，再考虑 `clean-admin.ps1 -DisableHibernate`（笔记本常见 +8~16 GB）。

### 场景 2：清完两周又满了

说明是**再生型**问题。先看上次清的是什么：

```powershell
scripts/scan.ps1 -Full
```

如果又是 `DXCache` / `D3DSCache` 最大 —— 那就是显卡着色器缓存，每玩新游戏或换驱动就重新编译，旧的从不删除。这时候别光清，挂个计划任务：

```powershell
schtasks /create /tn "C盘缓存清理" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File D:\c-drive-cleanup\scripts\clean-safe.ps1" /sc monthly /d 1 /rl highest
```

### 场景 3：微信占了 40 GB

不要删。用微信自己的设置迁移：

微信 → 设置 → 文件管理 → 更改 → 选 `D:\WeChat` → 重启微信（会自动迁移历史文件）

没有原生设置的应用（比如各种 Electron 工具的数据目录）才用 `migrate-appdata.ps1`。

---

## 输出示例

```
==================== DISK ====================
C:  total 159.28 GB | used 116.77 GB | FREE 42.52 GB (26.7%)

==================== Cache ====================
   22.21 GB  [DISM  ] C:\Windows\WinSxS
                    Only via DISM StartComponentCleanup
    3.90 GB  [NEVER ] C:\Windows\Installer
                    Deleting breaks uninstall/repair - use PatchCleaner
    1.24 GB  [KEEP  ] C:\ProgramData\NVIDIA\NGX
                    DLSS/NGX model data

==================== App:Roaming ====================
    4.39 GB  [REVIEW] C:\Users\me\AppData\Roaming\Tencent
                    Application data - check before touching

==================== EXISTING JUNCTIONS ====================
  C:\Users\me\AppData\Roaming\kingsoft -> D:\AppData\kingsoft
  C:\Users\me\AppData\Roaming\Tencent -> D:\AppData\Tencent
```

---

## 安全边界

**绝不删除**：

- `C:\Windows\Installer` —— 删了所有 MSI 软件无法卸载/修复
- `C:\Windows\WinSxS`（手删）—— 系统组件链断裂，可能无法启动
- `C:\Windows\System32`、`Fonts`、`assembly`
- `%APPDATA%\<应用>` —— 登录态、配置、聊天记录
- `C:\ProgramData\<应用>` —— 许可证、数据库、服务配置
- `pagefile.sys` / `swapfile.sys`（直接删文件）
- 任何 `.vhdx` / `.vhd` —— 虚拟磁盘会整体损坏
- 桌面 / 文档 / 下载 / 图片 / 视频
- OneDrive / 坚果云 / 百度网盘同步目录（删本地会同步删云端）

完整白名单/黑名单/灰区判断流程见 [docs/safety-rules.md](docs/safety-rules.md)。

---

## 一个真实案例

同一台 159 GB 的机器，三周内清了三次：

| 日期 | 清理前 | 清理后 | 释放 | 主要原因 |
|---|---|---|---|---|
| 10-16 | 7.5 GB | 69.8 GB | 62.3 GB | Ubisoft 17 GB 补丁缓存 + 迁移 13 GB + updater 3 GB |
| 11-03 | 18.7 GB | 40.5 GB | 21.9 GB | DXCache 11.6 GB + D3DSCache 7.2 GB + uv 2.6 GB |
| 11-08 | 30.0 GB | 42.5 GB | 12.5 GB | DXCache 4.3 GB + D3DSCache 3.0 GB + NVIDIA 驱动包 4.8 GB |

**规律**：GPU 着色器缓存是这台机器的固定复发项，5 天涨 10 GB。每台机器的复发项不同，记录三次就能定位——这比任何"一键清理"都值钱。

---

## 仓库结构

```
c-drive-cleanup/
├── SKILL.md                  # Agent 技能入口（触发条件 + 工作流 + 判断逻辑）
├── README.md
├── LICENSE                   # MIT
├── scripts/
│   ├── scan.ps1              # 只读诊断
│   ├── clean-safe.ps1        # 用户级缓存清理（免管理员）
│   ├── clean-admin.ps1       # 系统级清理（管理员）
│   └── migrate-appdata.ps1   # 目录迁移 + junction（带回滚）
└── docs/
    ├── cleanup-plan.md       # 完整清理方案
    └── safety-rules.md       # 安全规则与判断流程
```

---

## 环境要求

- Windows 10 / 11
- PowerShell 5.1（系统自带）或 PowerShell 7+
- 不需要安装任何第三方软件

## 贡献

发现新的缓存路径、新的应用迁移方法，或者遇到判断错误的目录，欢迎提 issue / PR。特别欢迎**不同软件环境下的扫描结果**——每台机器的复发项都不一样，样本越多判断越准。

## License

MIT
