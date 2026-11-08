# Windows C 盘完整清理方案

> 一份从"为什么满"到"怎么根治"的完整手册。适用于 Windows 10 / 11。
> 所有命令均可用 `powershell -ExecutionPolicy Bypass -File <脚本>` 直接运行。

---

## 一、先理解：C 盘为什么会反复爆满

C 盘不是"用着用着自然满了"，而是有明确的三个来源：

### 1. 可再生缓存（会无限增长）

应用把中间产物存在系统盘，**但从不主动清理**。典型：

| 缓存 | 增长原因 | 单次清理收益 |
|---|---|---|
| GPU 着色器缓存（`NVIDIA\DXCache`、`D3DSCache`） | 每玩一个新游戏/新驱动就重新编译着色器，旧的不删；单个 `.nvph` 文件上限 4 GB | 5~20 GB |
| Windows 更新缓存（`SoftwareDistribution\Download`） | 每次补丁下载后不自动删 | 2~10 GB |
| `*-updater` 目录 | Electron 应用每次自更新都留一份安装包 | 1~5 GB |
| 浏览器 Cache | 网页缓存滚动覆盖，但异常退出会残留 | 1~5 GB |
| 崩溃转储 / WER | 程序崩溃就写一份 | 0.5~5 GB |

**特征**：删了立刻重建，零风险，但过几周又长回来。

### 2. 一次性沉积（装完就忘）

| 项目 | 何时产生 | 大小 |
|---|---|---|
| `Windows.old` | 系统大版本升级后 | 10~30 GB |
| `$WINDOWS.~BT` | 升级准备文件 | 3~10 GB |
| `hiberfil.sys` | 休眠功能（默认开） | 内存的 40%~100% |
| 系统还原点 | 装驱动/更新时自动创建 | 最多磁盘 10% |
| `Windows\Installer` | 每次 MSI 安装 | 2~10 GB |

**特征**：不会自己长大，但也不会自己消失。

### 3. 应用数据默认落盘（持续增长）

这是**根本原因**。Windows 的默认约定是：

- 应用配置 → `%APPDATA%`（C 盘）
- 应用缓存 → `%LOCALAPPDATA%`（C 盘）
- 程序本体 → `C:\Program Files`（C 盘）
- 聊天文件 → `%USERPROFILE%\Documents`（C 盘）

而现代应用的数据量早已超过系统盘能承受的范围：

| 应用 | 默认位置 | 典型大小 |
|---|---|---|
| 微信 / 企业微信 | `Documents\WeChat Files`、`%APPDATA%\Tencent` | 5~50 GB |
| QQ | `Documents\Tencent Files` | 3~20 GB |
| WPS | `%APPDATA%\kingsoft` | 3~10 GB |
| 本地大模型（LM Studio / Ollama） | `%USERPROFILE%\.lmstudio`、`.ollama` | 5~100 GB |
| Docker / WSL | `%LOCALAPPDATA%\Docker`、WSL 发行版 vhdx | 5~50 GB |
| Steam 游戏 | `C:\Program Files (x86)\Steam` | 单游戏 30~150 GB |
| Android SDK / AVD | `C:\android-sdk`、`%USERPROFILE%\.android` | 5~20 GB |

**特征**：清了缓存还会继续长，必须**迁移**才能根治。

---

## 二、判断模型：什么能删，什么不能删

### 唯一可靠的判断标准

> **删掉之后，应用下次启动能不能自动重建？**
> 能 → 可删。不能 → 不能删。

### 白名单（可删）

- 名字里带 `Cache`、`cache`、`Temp`、`tmp`、`Temporary` 的目录内容
- `*-updater` 结尾的目录（更新暂存，本体在别处）
- `CrashDumps`、`WER`、`Minidump`、`MEMORY.DMP`
- `SoftwareDistribution\Download`
- `C:\$Recycle.Bin`
- GPU 驱动厂商的着色器缓存目录
- 包管理器缓存：`npm-cache`、`pnpm\store`、`Yarn\Cache`、`pip\Cache`、`uv\cache`
- `Windows.old`、`$WINDOWS.~BT`（升级残留）

### 黑名单（绝对不删）

| 路径 | 删除后果 |
|---|---|
| `C:\Windows\Installer` | 所有 MSI 软件无法卸载/修复，Office 可能无法更新 |
| `C:\Windows\WinSxS` | 系统组件链断裂，可能无法启动 |
| `C:\Windows\System32` | 立即蓝屏 |
| `C:\Windows\Fonts` | 所有程序字体异常 |
| `%APPDATA%\<应用>` | 登录态丢失、配置重置、聊天记录可能丢失 |
| `C:\ProgramData\<应用>` | 许可证、数据库、服务配置 |
| `pagefile.sys` / `swapfile.sys` | 内存不足时系统崩溃；只能通过系统设置调整 |
| 任何 `.vhdx` / `.vhd` | 虚拟磁盘整体损坏 |
| 桌面 / 文档 / 下载 / 图片 / 视频 | 用户数据 |
| OneDrive / 坚果云 / 网盘同步目录 | 本地删除会同步到云端 |

### 灰区（必须逐个判断）

- `%LOCALAPPDATA%\Programs\<应用>` —— 是程序本体。删了应用就没了，但可以用 junction 迁走
- `C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework` —— 驱动安装包缓存，可删，下次更新会重新下
- `C:\ProgramData\LGHUB\{cache,depots}` —— 罗技 G HUB 的固件包。用罗技外设时建议保留
- `%LOCALAPPDATA%\Microsoft\Windows\Explorer` —— 缩略图缓存，可删，会重建
- `C:\Windows\Prefetch` —— 可删，重建后前几次启动略慢

---

## 三、分级清理清单

> 原则：按风险从低到高推进，**每层跑完看一次剩余空间，够用就停**。

### L0：零风险，不需要管理员（预计 5~25 GB）

| # | 项目 | 命令 / 路径 |
|---|---|---|
| 1 | GPU 着色器缓存 | `%LOCALAPPDATA%\NVIDIA\DXCache`、`GLCache`、`%LOCALAPPDATA%\D3DSCache`、AMD/Intel 对应目录 |
| 2 | 用户临时文件 | `%LOCALAPPDATA%\Temp` |
| 3 | 崩溃转储 | `%LOCALAPPDATA%\CrashDumps`、`%LOCALAPPDATA%\Microsoft\Windows\WER` |
| 4 | 缩略图缓存 | `%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db` |
| 5 | Electron 更新暂存 | `%LOCALAPPDATA%\*-updater` |
| 6 | NVIDIA 驱动包 | `C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework` |
| 7 | 回收站 | `Clear-RecycleBin -Force` |
| 8 | 浏览器缓存 | Edge/Chrome/Brave/360/Firefox 的 `Cache`、`Code Cache`、`GPUCache` |
| 9 | 包管理器缓存 | `npm-cache`、`pnpm\store`、`Yarn\Cache`、`pip\Cache`、`uv\cache` |

一键执行：`scripts/clean-safe.ps1`

### L1：系统级，需要管理员（预计 3~15 GB）

| # | 项目 | 说明 |
|---|---|---|
| 1 | `C:\Windows\SoftwareDistribution\Download` | 先停 `wuauserv`/`bits` 再删 |
| 2 | `C:\Windows\SoftwareDistribution\DeliveryOptimization` | 更新 P2P 缓存 |
| 3 | `C:\Windows\Temp` | 系统临时文件 |
| 4 | `C:\Windows\Prefetch` | 预读记录 |
| 5 | `C:\Windows\LiveKernelReports`、`Minidump`、`MEMORY.DMP` | 崩溃转储 |
| 6 | `Dism /Online /Cleanup-Image /StartComponentCleanup` | WinSxS 组件清理，5~20 分钟，**保留卸载能力** |

一键执行：`scripts/clean-admin.ps1`

### L2：有代价，必须征得同意

| 项目 | 命令 | 收益 | 代价 |
|---|---|---|---|
| 关闭休眠 | `powercfg -h off` | 8~32 GB | 失去休眠和快速启动；`powercfg -h on` 可恢复 |
| 删除还原点 | `vssadmin delete shadows /for=C: /all /quiet` | 最多磁盘 10% | 失去系统回滚能力 |
| 删除 Windows.old | 见 `clean-admin.ps1 -RemoveWindowsOld` | 10~30 GB | 无法退回旧版 Windows |
| WinSxS 深度压缩 | `... /StartComponentCleanup /ResetBase` | 额外 1~3 GB | 无法卸载已安装更新 |

### L3：根治 —— 迁移应用数据

见下一节。

### L4：极端手段（仅剩空间 < 1 GB 时考虑）

- 临时把页面文件移到其他盘（系统属性 → 高级 → 性能 → 虚拟内存）
- 用 `Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase`
- 卸载不用的软件（`Get-Package` 或设置里的应用列表）
- 重装系统（最后手段，务必先备份）

---

## 四、逐应用迁移手册

### 4.1 优先用应用自己的设置（最稳）

| 应用 | 路径 | 操作 |
|---|---|---|
| 微信 4.x | 头像 → 设置 → 文件管理 → 更改 | 改到 `D:\WeChat`，会提示重启并迁移 |
| 微信 3.x | 设置 → 文件管理 → 更改 | 同上 |
| 企业微信 | 设置 → 通用 → 文件存储位置 | 改到 D 盘 |
| QQ | 设置 → 基本设置 → 文件保存位置 | 改到 D 盘 |
| WPS | 设置 → 备份中心 → 备份路径；另在"配置工具"里改缓存目录 | 两处都要改 |
| Steam | 设置 → 存储 → 添加驱动器 | 新建 `D:\SteamLibrary`，可"移动"已装游戏 |
| Chrome / Edge | 设置 → 下载内容 → 位置 | 改下载目录（缓存不能改，只能用 junction） |
| Docker Desktop | Settings → Resources → Advanced → Disk image location | 改到 D 盘后 Apply & restart |
| Android Studio | SDK Manager 里改 SDK 路径；AVD 里改虚拟设备路径 | 环境变量 `ANDROID_HOME` 同步改 |

### 4.2 用 junction 迁移（无原生设置时）

适用：`%APPDATA%\<应用>`、`%LOCALAPPDATA%\<应用>`、`%LOCALAPPDATA%\Programs\<应用>`、`.lmstudio`、`.ollama`、`.android` 等。

```powershell
# 干跑，确认路径和大小
scripts\migrate-appdata.ps1 -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat -DryRun

# 执行
scripts\migrate-appdata.ps1 -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat
```

手动版等价命令（理解原理用）：

```powershell
robocopy "C:\源目录" "D:\目标目录" /E /R:1 /W:1      # 1. 复制
# 2. 核对两边文件数和字节数一致
Rename-Item "C:\源目录" "源目录.premove"              # 3. 改名（不删）
cmd /c mklink /J "C:\源目录" "D:\目标目录"            # 4. 建目录联接
# 5. 打开应用验证正常，再删除 .premove
```

**为什么用 junction 而不是符号链接**：junction 对应用完全透明，不需要管理员权限也不需要开发者模式，且兼容老旧程序。

**风险点**：
- 应用更新时可能重建真实目录覆盖 junction（少见，遇到就重做一次）
- 目标盘断开（移动硬盘）会导致应用报错
- 部分安全软件会把 junction 当可疑行为

### 4.3 WSL / Docker 的特殊处理

WSL 发行版的磁盘是 `ext4.vhdx`，不能直接 junction，要导出再导入：

```powershell
wsl --list --verbose
wsl --export Ubuntu D:\wsl\ubuntu.tar
wsl --unregister Ubuntu
wsl --import Ubuntu D:\wsl\Ubuntu D:\wsl\ubuntu.tar --version 2
```

Docker Desktop 直接用设置里的 Disk image location 改。

### 4.4 已迁移目录的管理

```powershell
# 查看所有 junction
Get-ChildItem $env:APPDATA, $env:LOCALAPPDATA -Force | Where-Object LinkType -eq 'Junction' |
    Select-Object FullName, @{n='Target';e={$_.Target -join '; '}}

# 撤销某个 junction（先确认目标盘数据已备份）
cmd /c rmdir "C:\Users\你\AppData\Roaming\Tencent"
Move-Item "D:\AppData\Tencent" "C:\Users\你\AppData\Roaming\Tencent"
```

---

## 五、防复发

1. **开启存储感知**
   `Win+I` → 系统 → 存储 → 存储感知 → 打开，配置"每周清理临时文件""回收站 30 天自动清空"

2. **定期清 GPU 缓存**
   把 `clean-safe.ps1` 挂到任务计划程序，每月一次：

   ```powershell
   schtasks /create /tn "C盘缓存清理" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File D:\c-drive-cleanup\scripts\clean-safe.ps1" /sc monthly /d 1 /rl highest
   ```

3. **监控阈值**
   可用空间低于 **15%** 或 **15 GB**（取较大者）时提醒自己清理。

4. **装软件时养成习惯**
   安装向导里凡是有"安装位置"的都改到 D 盘；便携软件直接放 D 盘。

5. **别把用户目录整体搬到 D 盘**
   `Desktop`/`Documents` 可以用系统"位置"设置改，但 `AppData` 不能整体搬——大量应用硬编码了路径，会出各种诡异问题。要搬就逐个应用搬。

---

## 六、故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 扫描显示某目录 0 GB，但顶层显示很大 | 权限不足，读不到子目录 | 用管理员权限重跑 |
| `vssadmin` 报"找不到满足查询的项目" | 没有还原点或系统保护关闭 | 正常，跳过还原点清理 |
| 删除时大量"文件正在使用" | 进程占用 | 先退出相关应用/服务，或用 `clean-admin.ps1` 停服务 |
| `gci` 报错提示绑定到 `Get-Process` | 别名被第三方软件篡改 | 改用完整命令名 `Get-ChildItem` |
| PowerShell 卡在 `>>` | 多行粘贴被截断，有未闭合括号 | `Ctrl+C` 数次，或关窗口重开 |
| 脚本运行到一半就退出 | 脚本自己所在目录被自己删了 | 别把脚本放在被清理的目录里运行 |
| DISM 报错 0x800f0806 | 组件存储损坏 | `Dism /Online /Cleanup-Image /RestoreHealth` |
| 迁移后应用打不开 | junction 未生效或数据不全 | 删 junction，把 `.premove` 改回原名 |
| 迁移后空间没减少 | 源目录还在（复制未完成或未删原件） | 检查 `.premove` 目录是否残留 |

---

## 七、记录模板

每次清理后记录一行，便于追踪复发周期：

```
日期        清理前    清理后    释放     主要项目
2026-10-16  7.5 GB   69.8 GB   62.3 GB  Ubisoft 补丁 17G + 迁移 13G + updater 3G
2026-11-03  18.7 GB  40.5 GB   21.9 GB  DXCache 11.6G + D3DSCache 7.2G + uv 2.6G
2026-11-08  30.0 GB  42.5 GB   12.5 GB  DXCache 4.3G + D3DSCache 3.0G + NVIDIA 驱动包 4.8G
```

**看出规律了吗**：GPU 着色器缓存和 NVIDIA 驱动包是这台机器的固定复发项。每台机器的复发项不同，记录三次就能定位。
