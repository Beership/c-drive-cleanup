# C Drive Cleanup Kit

Windows C 盘清理工具包 + 可复用的 AI Agent 技能。

不是又一个"一键清理"软件。它的核心是**先给证据、再分层动手、最后迁移根治**，每一步都说明为什么。

```
扫描 → 判断 → 分层清理 → 迁移应用数据 → 复盘防复发
```

---

## 它能解决什么

| 场景 | 做法 |
|---|---|
| C 盘只剩几个 G，打不开更新 | L0/L1 清缓存，几分钟见 10~30 GB |
| 清完过两周又满了 | 定位复发项（通常是 GPU 缓存），挂计划任务定期清 |
| 微信/QQ/模型文件吃掉几十 G | 用原生设置或 junction 迁到其他盘 |
| 帮朋友远程清电脑 | 只读扫描先截图，按分级清单一条条来 |
| 想搞清楚空间到底去哪了 | `scan.ps1` 输出每项的路径、大小、处置建议 |

---

## 快速开始

### 1. 诊断（只读，不删任何东西）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/scan.ps1
```

输出按类别分组，每项带 `Verdict`：

| Verdict | 含义 |
|---|---|
| `SAFE` | 可再生缓存，可直接清 |
| `REVIEW` | 需要逐个判断 |
| `DISM` | 只能用 DISM 处理 |
| `KEEP` | 不该删 |
| `NEVER` | 删了会坏系统 |

完整扫描（含 `C:\Windows`）：加 `-Full`。机器可读：加 `-Json`。

### 2. 清零风险缓存（不需要管理员）

```powershell
# 先干跑看清要删什么
powershell -ExecutionPolicy Bypass -File scripts/clean-safe.ps1 -DryRun

# 确认后执行
powershell -ExecutionPolicy Bypass -File scripts/clean-safe.ps1
```

覆盖 GPU 着色器缓存、用户临时文件、崩溃转储、错误报告、缩略图、`*-updater` 暂存、NVIDIA 驱动包、回收站。

可选：`-IncludeBrowserCache`、`-IncludeNpmCache`

### 3. 清系统级缓存（管理员）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean-admin.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/clean-admin.ps1
```

默认只做保守项。带代价的选项必须显式打开：

| 开关 | 收益 | 代价 |
|---|---|---|
| `-DisableHibernate` | 8~32 GB | 失去休眠/快速启动（`powercfg -h on` 可恢复） |
| `-DeleteRestorePoints` | 最多磁盘 10% | 失去系统回滚 |
| `-RemoveWindowsOld` | 10~30 GB | 无法退回旧版 Windows |
| `-ResetBase` | 额外 1~3 GB | 无法卸载已安装的更新 |

### 4. 迁移应用数据（根治）

```powershell
# 干跑
powershell -ExecutionPolicy Bypass -File scripts/migrate-appdata.ps1 `
  -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat -DryRun

# 执行
powershell -ExecutionPolicy Bypass -File scripts/migrate-appdata.ps1 `
  -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat
```

六道保险：拒绝已是 junction 的源 → 检查目标盘空间 → 停进程 → robocopy → **比对文件数与字节数** → 先改名再建链接、验证通过才删原件。任一步失败自动回滚。

---

## 安全边界

**绝不删除**：`C:\Windows\Installer`、`C:\Windows\WinSxS`（手删）、`System32`、`%APPDATA%\<应用>`、`C:\ProgramData\<应用>`、任何 `.vhdx`、用户文档、网盘同步目录。

完整的白名单/黑名单/灰区判断流程见 [docs/safety-rules.md](docs/safety-rules.md)。

所有清理脚本都支持 `-DryRun`，先看后做。

---

## 作为 AI Agent 技能安装

本仓库根目录就是一个 ZCode / Claude Code 兼容的技能（`SKILL.md` + `scripts/` + `docs/`）。

```bash
# 个人级安装（所有项目可用）
git clone https://github.com/<your-name>/c-drive-cleanup.git ~/.zcode/skills/c-drive-cleanup

# 或项目级
git clone https://github.com/<your-name>/c-drive-cleanup.git .agents/skills/c-drive-cleanup
```

装好后，直接说"C 盘又满了，帮我清一下"或"帮我朋友清理电脑"，技能会自动触发，按扫描 → 分层清理 → 迁移的流程走。

---

## 仓库结构

```
c-drive-cleanup/
├── SKILL.md                  # 技能主文件（Agent 读取的入口）
├── README.md
├── LICENSE
├── scripts/
│   ├── scan.ps1              # 只读诊断
│   ├── clean-safe.ps1        # 用户级缓存清理（免管理员）
│   ├── clean-admin.ps1       # 系统级清理（管理员）
│   └── migrate-appdata.ps1   # 目录迁移 + junction（带回滚）
└── docs/
    ├── cleanup-plan.md       # 完整清理方案（分级清单 + 逐应用迁移手册）
    └── safety-rules.md       # 删除白名单/黑名单/灰区判断
```

---

## 一个真实案例

同一台 159 GB 的机器，三次清理记录：

| 日期 | 清理前 | 清理后 | 释放 | 主要原因 |
|---|---|---|---|---|
| 10-16 | 7.5 GB | 69.8 GB | 62.3 GB | Ubisoft 17 GB 补丁缓存 + 迁移 13 GB + updater 3 GB |
| 11-03 | 18.7 GB | 40.5 GB | 21.9 GB | DXCache 11.6 GB + D3DSCache 7.2 GB + uv 2.6 GB |
| 11-08 | 30.0 GB | 42.5 GB | 12.5 GB | DXCache 4.3 GB + D3DSCache 3.0 GB + NVIDIA 驱动包 4.8 GB |

看规律：**GPU 着色器缓存是这台机器的固定复发项**。每台机器的复发项不同，记录三次就能定位——这是本工具最有价值的部分，比任何"一键清理"都管用。

---

## 环境要求

- Windows 10 / 11
- PowerShell 5.1（系统自带）或 PowerShell 7+
- 无需安装任何第三方软件

## License

MIT
