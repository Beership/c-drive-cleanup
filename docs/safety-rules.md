# 安全规则

这是本技能的"护栏"。任何删除决策都先过这张表。

---

## 一、唯一判断标准

> **删掉之后，应用下次启动能不能自动重建？**

- 能重建 → 可删（缓存、临时文件、缩略图、着色器、更新包）
- 不能重建 → 不能删（配置、登录态、许可证、用户数据、程序本体）

第二问：**这个是别人电脑上的吗？** 是的话把标准再提高一档——不确定的一律不删，先列出来问。

---

## 二、删除白名单

以下内容可以放心删除，不需要逐项确认。

### 缓存类

| 模式 | 位置示例 |
|---|---|
| `*\Cache\*` / `*\cache\*` | 浏览器、Electron 应用 |
| `*\Code Cache\*` | Chromium 系应用 |
| `*\GPUCache\*` | Chromium 系应用 |
| `*\Temp\*` / `*\tmp\*` | 系统和应用临时文件 |
| `*\DXCache\*` / `*\GLCache\*` | NVIDIA / AMD 着色器缓存 |
| `%\D3DSCache%` | DirectX 着色器缓存 |
| `*\ShaderCache\*` | Intel |
| `*\*-updater\*` | Electron 自动更新暂存 |

### 诊断类

- `%LOCALAPPDATA%\CrashDumps`
- `%LOCALAPPDATA%\Microsoft\Windows\WER`
- `C:\Windows\Minidump`
- `C:\Windows\LiveKernelReports`
- `C:\Windows\MEMORY.DMP`

### 系统可重建类

- `C:\Windows\Temp`
- `C:\Windows\Prefetch`
- `C:\Windows\SoftwareDistribution\Download`
- `C:\Windows\SoftwareDistribution\DeliveryOptimization`
- `C:\$Recycle.Bin`

### 包管理器缓存

- `npm-cache`、`pnpm\store`、`Yarn\Cache`、`pip\Cache`、`uv\cache`、`Cargo\registry\cache`

### 升级残留

- `C:\Windows.old`
- `C:\$WINDOWS.~BT`
- `C:\$WINDOWS.~WS`
- `C:\$WinREAgent`
- `C:\$GetCurrent`

---

## 三、删除黑名单

**任何情况下都不要删。** 即使空间只剩几百 MB，也先做别的。

| 路径 | 后果 | 替代方案 |
|---|---|---|
| `C:\Windows\Installer` | 所有 MSI 软件无法卸载/修复，Office 更新失败 | PatchCleaner 清理孤立项，或直接不管 |
| `C:\Windows\WinSxS` | 组件链断裂，可能无法启动 | `Dism /Online /Cleanup-Image /StartComponentCleanup` |
| `C:\Windows\System32` / `SysWOW64` | 系统崩溃 | 无 |
| `C:\Windows\Fonts` | 全局字体异常 | 无 |
| `C:\Windows\assembly` / `Microsoft.NET` | .NET 应用全部失效 | 无 |
| `C:\Program Files\*`（整个目录） | 程序全丢 | 用卸载程序，或 junction 迁移 |
| `%APPDATA%\<应用>` | 登录态、配置、聊天记录 | 迁移，不删 |
| `C:\ProgramData\<应用>` | 许可证、数据库、服务配置 | 先确认是缓存子目录再动 |
| `pagefile.sys` / `swapfile.sys` | 内存不足时崩溃 | 系统属性 → 虚拟内存 |
| `hiberfil.sys`（直接删文件） | 无权限且不生效 | `powercfg -h off` |
| `*.vhdx` / `*.vhd` | 虚拟磁盘整体损坏 | `wsl --export` / Docker 设置 |
| `C:\System Volume Information` | 还原点 + 索引 | `vssadmin` |
| `C:\Recovery` | 恢复环境失效 | 无 |
| 桌面/文档/下载/图片/视频 | 用户数据 | 迁移到其他盘 |
| OneDrive/坚果云/百度网盘同步目录 | 云端同步删除 | 在客户端里改同步范围 |

---

## 四、灰区判断流程

遇到不在白名单也不在黑名单的目录，按这个流程走：

```
1. 这个目录属于哪个应用？
   └─ 不知道 → 不删，列出来问用户

2. 名字暗示它是缓存吗？（cache/temp/log/dump/tmp/updater）
   ├─ 是 → 打开看内容：
   │        ├─ 都是 .tmp/.log/.cache/.bin 之类 → 删
   │        └─ 有 .db/.json/.xml/.dat → 可能是配置，不删
   └─ 否 → 不删

3. 该应用还在用吗？
   ├─ 已卸载 → 整个目录可删
   └─ 在用 → 只删确认是缓存的部分

4. 删了之后应用还能正常启动吗？
   └─ 不能确定 → 不删
```

### 典型灰区案例

**`%LOCALAPPDATA%\Programs\<应用>` 4 GB**
这是应用本体，删了应用就没了。正确做法：junction 迁到 D 盘，不是删。

**`C:\ProgramData\LGHUB\depots` 1.2 GB**
罗技 G HUB 的固件包。用户在罗技外设 → 保留；不用罗技 → 可删。**先问。**

**`C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework` 4.8 GB**
下载好的驱动安装包，删了不影响已装驱动，下次更新会重下。可删。

**`C:\ProgramData\NVIDIA\NGX` 1.2 GB**
DLSS / NGX 的 AI 模型。删了部分游戏画质功能受影响，会重下但很慢。**不建议删。**

**`%LOCALAPPDATA%\Microsoft\Windows\Explorer` 200 MB**
缩略图和图标缓存，删了自动重建。可删。

**`C:\Users\X\Documents\WeChat Files` 20 GB**
聊天记录和文件，**绝对不能删**。引导用户在微信里改存储路径。

---

## 五、操作纪律

### 远程操作额外规则

1. **不在一台看不到的机器上做分区、`/ResetBase`、`WSL --unregister` 这类不可逆操作**——远程一旦断连就没人能救。
2. **每一步都让操作者看到输出**，不要把十几条命令打包成一大段粘贴（远程剪贴板容易截断，导致 PowerShell 卡在 `>>` 续行符）。
3. **先做只读扫描，把结果截图存档**，再动手。

### 权限

- L0 清理不需要管理员
- L1 及以上需要管理员
- 脚本应检查权限，不足时明确提示，而不是静默失败

### 可逆性

按可逆程度选择手段：

| 手段 | 可逆性 |
|---|---|
| 删缓存 | 完全可逆（自动重建） |
| 回收站清空 | 不可逆 |
| 停服务再删缓存 | 可逆 |
| `powercfg -h off` | 可逆（`-h on`） |
| 删还原点 | 不可逆 |
| 删 Windows.old | 不可逆 |
| junction 迁移 | 可逆（删链接、移回原处） |
| 分区调整 | 高风险，可能丢数据 |

**原则：能用可逆手段解决的，不用不可逆手段。**

---

## 六、脚本自身的安全设计

`scripts/` 下的脚本遵守以下约定：

1. **`-DryRun` 先看后做** —— 所有清理脚本都支持干跑
2. **不删自己所在目录** —— 防止脚本把自己删掉导致中断
3. **`-LiteralPath`** —— 避免路径里的 `[` `]` 被当成通配符
4. **先改名再删** —— `migrate-appdata.ps1` 把源目录改名 `.premove`，junction 验证通过才删
5. **字节数比对** —— 迁移前后比对文件数和总字节，不达标就回滚
6. **失败即中止** —— 关键步骤失败时 `exit` 而不是继续
7. **报告每一项** —— 不只报总数，用户要知道每一项释放了多少
