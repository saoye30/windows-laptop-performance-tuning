---
name: windows-laptop-performance-tuning
description: Windows 11 笔记本电源与性能调优，涵盖通用 PPKG 1.44（Tongfang）安装、校验与回滚，显示隐藏电源设置，调整 NVIDIA、Windows、浏览器和 Steam 配置，以及华硕/联想厂商控制软件替换。用户提到 PPKG、预配包、电源模式、Tongfang、游戏模式 CPU 调度、笔记本续航与性能调优、get-provisioningpackage、安装 Power Settings Explorer 显示隐藏电源设置、NVIDIA 电源管理/着色器缓存、关闭 Windows 搜索、暂停更新、关闭浏览器和 Steam 硬件加速，或者要把华硕奥创（Armoury Crate）换成 G-Helper、把联想 Legion Zone/联想电脑管家/Vantage 换成 Lenovo Legion Toolkit 时使用。
---

# Windows 笔记本电源与性能调优

## 这个 skill 做什么

把 `assets/Tongfang.ppkg`（通用 PPKG 1.44）安全地装到用户的 Windows 11 笔记本上，并且能完整撤销。安全框架沿用 doubao-pc-optimizer：先识别环境和硬件，再只读扫描，给出方案并征得许可，执行后汇报并提供回滚。

安装预配包属于 **L2 系统修改**：它改写的是 Windows 电源管理里处理器策略的默认值，不删文件、不改 BIOS、不改电压功耗墙。但它影响整机的调度和续航，所以必须逐项说明、备份、确认后再做。

另外负责一项配套工作：厂商控制软件会动态改写电源设置，把 PPKG 的效果盖掉。在华硕天选/TUF/ROG 上把奥创换成 G-Helper，在联想拯救者/LOQ 上把 Legion Zone、联想电脑管家、Vantage 换成 Lenovo Legion Toolkit（LLT）。流程见下文「厂商控制软件替换」。

不处理的事情：磁盘清理、驱动更新、超频、BIOS 设置、其他厂商的 PPKG 改写或重新打包、华硕/联想以外品牌的控制软件替换。

## 预配包内容（已拆包核实）

详细数值见 `references/ppkg-1.44-settings.md`，适用 CPU 见 `references/supported-cpus.md`。要点：

- 包名 `Tongfang`，版本 1.44，OwnerType OEM，Rank 0，SHA256 `6EF9F98C3BAED89F6BD2DA4F6EF20B6F72D9D529380DA6271705FA671D988E87`
- 只包含 `Power/Policy/Settings/Processor/SchemePersonality` 设置，没有命令行、没有可执行文件、没有证书或 Wi-Fi 等其他配置
- 修改对象是“平衡”方案（381b4222-…）、“最佳能效”叠加层（BetterBatteryLifeOverlay）和“最佳性能”叠加层（MaxPerformanceOverlay）里，各个 PPM 场景配置（Default、GameMode、Constrained、Eco、Multimedia、LowLatency、Utility）的 EPP、核心停放、调度策略和电池模式下的频率上限
- 只对 **笔记本/平板**（PowerPlatformRole = 2 或 8）且 CPU 型号命中目标表的机器生效；台式机和未列出的 CPU 只会应用通用部分
- 主要效果：插电游戏时把 EPP 压到 0（全力性能）、延长核心降频等待时间；电池模式下限制频率、偏向能效核，换续航

## 核心流程

0. **判断运行环境**：确认命令作用于用户本机。执行 `Get-CimInstance Win32_OperatingSystem`，如果拿到的不是 Windows 11 或者根本不是 Windows，说明在沙箱或错误的机器上，只交付脚本和说明，不要报告“已安装”。
1. **只读扫描（L0）**：运行 `scripts/scan_power.ps1`。它报告系统版本、CPU 家族/型号、平台角色、是否命中目标表、当前电源方案、已安装的预配包、正在运行的厂商电源管理软件。
2. **校验安装包（L0）**：运行 `scripts/inspect_ppkg.ps1`，核对 SHA256 并确认包里只有电源策略。用户给的是别的文件或哈希对不上时，先停下来告诉用户，不要安装。
2.5 **厂商控制软件（华硕/联想，可选）**：扫描显示奥创、Legion Zone、联想电脑管家或 Vantage 在运行时，运行 `scripts/oem_switch.ps1` 扫描，并在方案里提出替换建议。用户同意后，先替换、重启，再装 PPKG。用户不想换就跳过，照常提醒效果可能被覆盖。
3. **给出方案并征得许可**：说明适配结论、会改什么、预期影响、冲突项、怎么撤销。等用户明确同意。
4. **安装（L2，一条命令完成）**：以管理员运行 `scripts/install_ppkg.ps1`。它按顺序自动做完：
   1. 建还原点，导出电源注册表、活动方案、`powercfg /qh`
   2. **安装 Power Settings Explorer 并显示隐藏电源项**（`setup_pse.ps1`，见下文）
   3. 生成 `undo.ps1`
   4. 安装 PPKG，配置电源模式
   5. **系统性能项**（`tune_system.ps1`，见下文）：NVIDIA、Windows 搜索、Windows 更新、浏览器、Steam
   - 所有备份都在同一个 `PowerPPKG_Backup_<时间>` 目录，`undo.ps1` 一次全部撤销
   - 可选参数：`-SkipPse` 跳过 PSE；`-SkipTune` 跳过系统性能项；`-TuneOnly "Nvidia,Steam"` 只做部分；`-CloseSteam` 允许脚本正常退出正在运行的 Steam
   - 先跑 `-DryRun` 把完整计划给用户看，用户同意后再正式执行
5. **重启后校验**：提醒用户重启。重启后运行 `scripts/verify_ppkg.ps1 -BackupDir <备份目录>`，确认包状态，并对比安装前后的处理器电源设置。
6. **汇报**：改了什么、备份目录和 `undo.ps1` 在哪里、哪些情况下效果不明显。

## 配置电源模式前：Power Settings Explorer（自动）

Windows 默认把大部分处理器电源设置藏起来。本机处理器组 96 项里有 89 项是隐藏的，PPKG 改的 EPP、核心停放、调度策略等都在其中。安装 PPKG 前，`install_ppkg.ps1` 会自动调用 `scripts/setup_pse.ps1`：

1. 下载固定版本 PSE v0.2.0 到 `%LOCALAPPDATA%\Programs\PowerSettingsExplorer\`，SHA256 必须等于 `EA980776B9434F8956787BE6EEE3FD263BFEE87C99A1736B57F68E4B4DFC6E1A`（GitHub Release 公布的 digest），否则停止，不装 PPKG。并建开始菜单快捷方式。
2. 把所有电源设置的显示状态备份到 `power_visibility_before.csv`。
3. 把处理器组的隐藏项全部设为显示。PSE 只有图形界面、没有命令行参数，所以这一步由脚本调用 `PowerWriteSettingAttributes`（powrprof.dll）完成，和 PSE 里选 **On** 是同一个 API、同一个值。
4. 之后在「控制面板 → 电源选项 → 更改高级电源设置」或 PSE 里都能看到这些项，以及 PPKG 写入后的值。

工具情况（已核实）：
- 地址 https://github.com/WtekSupport/PowerSettingsExplorer ，MIT 开源，Rust 编写，GitHub Actions 从源码构建发布
- **没有数字签名**，项目 2026 年 10 月才创建，关注的人很少。方案里必须告诉用户；Windows SmartScreen 打开它时可能提示
- 只改设置项的 `Attributes`（显示/隐藏），不改任何插电/电池数值

撤销：`undo.ps1` 会按备份恢复显示状态，并删除本流程安装的 PSE（用户自己装的保留）。单独查看隐藏项：`scripts/power_visibility.ps1`（`-Subgroup All` 看全部）。

## 配置电源模式后：系统性能项（自动）

PPKG 装好后，`install_ppkg.ps1` 自动调用 `scripts/tune_system.ps1`。每一项改动前把原值记到 `tune_state.json`，已是目标值的项跳过不记。

| 项目 | 改成 | 实现方式 |
|---|---|---|
| NVIDIA 电源管理模式 | 最高性能优先 | NVIDIA 官方 NvAPI 驱动设置接口（`NvDrs.cs`），写全局 3D 设置 `PREFERRED_PSTATE` = 1 |
| NVIDIA 着色器缓存 | 关闭 | 同上，`PS_SHADERDISKCACHE` = 0，缓存大小 = 0 |
| Windows 搜索 | 关闭 | 停止并禁用索引服务 WSearch；开始菜单搜索不联网（关闭必应建议） |
| Windows 更新 | 暂停到 2099-12-31 | 写「设置 → Windows 更新 → 暂停」用的 `UX\Settings` 暂停时间，并调大允许的暂停天数 |
| Edge / Chrome / Brave | 关闭开机自启、关闭后台运行、关闭硬件加速；Edge 关闭启动加速 | 浏览器企业策略（`HKLM\SOFTWARE\Policies\...`）；删掉 Run 里浏览器的自启项 |
| Firefox | 关闭硬件加速 | Firefox 企业策略 |
| Steam 硬件加速 | 关闭网页视图 GPU 加速、关闭硬件视频解码 | `HKCU\Software\Valve\Steam` 的 `GPUAccelWebViewsV3`、`H264HWAccel` |
| Steam 着色器预缓存 | 关闭 | `config.vdf` 的 `ShaderCacheManager` 里 `DisableShaderCache`=1、`EnableShaderBackgroundProcessing`=0（键名取自 steamclient64.dll），改前备份原文件 |

必须在方案里告诉用户的影响：
- **关闭着色器缓存（NVIDIA 和 Steam）**：每次进游戏都要重新编译着色器，加载更慢，首次进入场景可能卡顿。省下的是磁盘空间和后台编译占用的 CPU。
- **关闭浏览器硬件加速**：网页和视频改由 CPU 渲染，看高清视频时 CPU 占用和耗电会上升。
- **关闭 Steam 硬件视频解码**：Steam 直播、录像、远程畅玩改用 CPU 解码。
- **关闭 Windows 搜索索引**：开始菜单和资源管理器仍能搜索，但搜文件内容会很慢。
- **暂停更新到 2099**：安全补丁也一起停了，有安全风险。建议用户隔一段时间手动更新一次；`undo.ps1` 可以恢复。
- **浏览器策略**：Edge/Chrome 会显示「由你的组织管理」，这是写入企业策略的正常提示。
- Steam 正在运行时，退出时会覆盖配置。脚本默认跳过 Steam 并提示；用户同意时加 `-CloseSteam`，脚本用 `steam.exe -shutdown` 正常退出它。
- NVIDIA 电源管理改成最高性能后，笔记本插电时显卡功耗和发热更高；用电池时影响较小，因为独显通常不工作。

撤销：`undo.ps1` 会调用 `tune_system.ps1 -Mode Undo`，按记录逆序恢复：注册表原来没有的值会删除，WSearch 恢复原启动类型，NVIDIA 恢复原值或驱动默认值，`config.vdf` 用备份覆盖。

## 适配判断（第 1 步结果怎么用）

| 扫描结论 | 处理 |
|---|---|
| Windows 10 或 Build < 22000 | 不装。readme 明确不支持 Win10 |
| 平台角色不是 2/8（台式机、工作站） | 不装。目标条件不会命中，装了只剩通用部分，收益不明确 |
| CPU 命中「原生支持」 | 可以装 |
| CPU 命中「仅兼容」（ADL、DRG、RMB 及更早） | 可以装，但要告诉用户收益可能很小 |
| CPU 不在表里（如 Intel 11 代及更早、AMD 5000 系列及更早） | 默认不装；用户坚持时说明只有通用部分生效，再加 `-AllowUnsupported` |
| 已装其他厂商 PPKG | 先停。告诉用户两个包会叠加冲突，由用户决定是否先删除旧包（设置 → 账户 → 访问工作或学校帐户 → 添加或删除预配包），不要代为删除 OEM 包 |
| 运行着 Armoury Crate、Lenovo Vantage/Legion Zone、荣耀/华为电脑管家、MSI Center、OMEN Gaming Hub、Dragon Center 等 | 可以装，但必须告知：这些软件会动态改写电源方案或叠加层，PPKG 的效果可能被覆盖。readme 原文：「荣耀或联想部分机器是动态修改，如果安装品牌管家之类的程序确实无法生效。AMD 机型提升较小。」 华硕和联想机器可以按「厂商控制软件替换」流程，经用户确认后替换；其他品牌只提醒，不卸载、不禁用 |
| 当前活动方案不是系统「平衡」（如 G-Helper 自建方案） | 告知用户 PPKG 改的是系统平衡方案的默认值，自定义方案未必继承；安装后可切回「平衡」方案再测 |

## 厂商控制软件替换（华硕 / 联想）

### 为什么要换

奥创、Legion Zone、联想电脑管家、Vantage 会在后台按自己的规则切换电源方案和叠加层，PPKG 写进去的默认值会被覆盖。G-Helper 和 LLT 只在你切换模式时调用 BIOS 里厂商预设的模式和 Windows 电源模式，不常驻服务，不跟 PPKG 抢设置。

两者都是社区开源软件，不是厂商官方软件，作者都声明不提供担保。要告诉用户：厂商客服排查问题时可能要求先装回官方软件；官方软件独有的功能（如联想的云服务、华硕部分外设联动）会没有。不要对保修做任何承诺。

### 通用步骤

1. **扫描（L0）**：`scripts/oem_switch.ps1`。输出机型、品牌、可替换的软件清单（带 Id）、必需组件是否存在、官方下载地址。
2. **给出方案**：列出要卸载的每一项、会保留的组件、替换后少掉的功能、怎么装回。等用户确认。
3. **用户自己下载** 替换软件和工具（地址见下），下载后运行 `oem_switch.ps1 -Mode CheckFile -File <文件>` 校验签名，签名无效就不运行。
4. **先装好替换软件，再卸载**，避免卸完之后没有工具调模式和风扇。
5. **卸载（L2，管理员）**：见下方分品牌说明。脚本会先在桌面建 `OEMSwitch_Backup_<时间>` 目录，保存软件清单、服务状态、装回说明，并创建还原点。
6. **重启**，再扫描一次，确认残留进程已经没有了，然后继续 PPKG 流程。

### 华硕（天选 / TUF / ROG）：奥创 → G-Helper

- 下载：G-Helper https://github.com/seerge/g-helper/releases/latest （单个 exe，免安装）；官方卸载工具 https://dlcdnets.asus.com/pub/ASUS/mb/14Utilities/Armoury_Crate_Uninstall_Tool.zip
- 必须保留：**ASUS System Control Interface**（G-Helper 靠它控制硬件，缺了就从华硕官网装 V3 版）。MyASUS 可以保留。
- 扫描清单里的非奥创华硕软件（如 ASUS Smart Display Control）可以用 `-Mode Uninstall -Ids` 卸载；清单里出现奥创组件时脚本会拒绝，必须走官方工具。
- 卸载奥创只用官方工具：解压后以管理员运行 `oem_switch.ps1 -Mode RunAsusTool -File "<Armoury Crate Uninstall Tool.exe>"`。脚本会核对 ASUSTeK 签名、备份，然后启动工具，由用户在窗口里点完。
- G-Helper 官方说明里 ASUS Smart Display Control 也会和它抢刷新率，可以卸载。
- G-Helper 的「Extra → Asus Services → Stop」可以停掉剩余的华硕服务，能随时点 Start 恢复。这一步由用户在 G-Helper 里自己操作，脚本不停服务。
- 装回：华硕官网机型支持页或 Microsoft Store 重新安装奥创，装回前先退出 G-Helper。

### 联想（拯救者 / LOQ / R、Y 系列）：Legion Zone、联想电脑管家、Vantage → LLT

- 下载：https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/releases/latest 。原作者仓库已归档，现在由 LenovoLegionToolkit-Team 维护，不要从其他网盘下载。
- LLT 只支持拯救者、Legion Go、IdeaPad Gaming、LOQ、Lenovo Slim、ThinkBook 这些机型，其他联想机器不要换。LLT 需要管理员账户。
- 必须保留：**Lenovo Energy Management** 和 **Lenovo Vantage Gaming Feature Driver**（Gen 10 及更新机型不需要，也不用补装）。
- **首选「禁用」而不是卸载**：装好 LLT 后，在 LLT 设置里禁用 Vantage、Legion Zone、Hotkeys。这一步可以随时恢复，由用户在 LLT 里操作。
- 用户坚持卸载时：以管理员运行 `oem_switch.ps1 -Mode Uninstall -Ids "<扫描结果里的 Id>"`。它只接受扫描清单里的 Id，会调用每个软件自带的卸载程序（可能弹窗，需要用户点完）。Vantage 要连同 Lenovo Vantage Service、System Interface Foundation 一起卸载，否则 LLT 仍会提示 Vantage 在运行；残留的 ImController 进程按联想官方说明 https://support.lenovo.com/us/en/solutions/HT506070 处理。
- 联想电脑管家不只管性能模式，还有驱动更新、清理等功能，卸载前要告诉用户这些功能会一起没有。
- 装回：联想官网机型驱动页或联想应用商店装回 Legion Zone / 电脑管家；Microsoft Store 装回 Vantage。

### 替换后和 PPKG 的配合

- G-Helper：在「Fans + Power」里让三个模式分别对应 Windows 电源模式（Silent → 最佳能效，Balanced → 平衡，Turbo → 最佳性能），活动电源方案保持系统「平衡」。
- LLT：按 LLT 推荐用 Windows 电源模式加唯一的「平衡」方案，在 LLT 设置里把 Quiet / Balance / Performance 分别对应到最佳能效 / 平衡 / 最佳性能。
- 这样 PPKG 写进「平衡」方案和两个叠加层的设置都能用上。

## 风险分级

| 级别 | 本 skill 中的操作 | 许可要求 |
|---|---|---|
| L0 只读 | scan_power、inspect_ppkg、verify_ppkg、`Get-ProvisioningPackage`、`powercfg /q` | 直接做 |
| L2 系统修改 | 安装 PPKG、卸载 PPKG、导入电源注册表备份、切换活动电源方案 | 逐项说明影响和撤销方式，用户明确确认 |
| L2 显示隐藏项 | `setup_pse.ps1` 安装 PSE 并显示处理器隐藏项；`power_visibility.ps1 -Mode Restore` | 和 PPKG 安装一起说明，告诉用户 PSE 没有签名 |
| L2 系统性能项 | `tune_system.ps1`：NVIDIA、Windows 搜索、更新暂停到 2099、浏览器、Steam | 在方案里逐项列出改什么、上面列的副作用、怎么撤销，用户确认 |
| L2 手动改电源数值 | 在「高级电源设置」里改 EPP、频率上限、核心停放等 | 逐项说明，先导出方案，用户确认 |
| L2 软件替换 | 华硕：运行官方 Armoury Crate Uninstall Tool；联想：卸载 Legion Zone / 联想电脑管家 / Vantage | 列出要卸载的每一项、保留的驱动、装回方法，用户明确确认 |
| L2 高影响 | `powercfg -restoredefaultschemes`（会删除所有自定义电源方案，包括 G-Helper 等软件建的方案） | 只作为最后手段，单独确认 |
| L3 禁止 | 见下 | 用户坚持也不做 |

### L3 黑名单

- 修改或重新打包 PPKG、往包里加命令或脚本；安装来源不明、哈希不符的 PPKG
- 用 `-ForceInstall` 绕过已有 OEM 包的冲突检查（除非用户已自行删除旧包后重试）
- 代删其他厂商的预配包；卸载或停用华硕/联想替换清单以外的厂商软件、服务和驱动
- 卸载 ASUS System Control Interface、Lenovo Energy Management、Lenovo Vantage Gaming Feature Driver 等驱动（G-Helper 和 LLT 依赖它们）
- 不用华硕官方卸载工具，自己逐个删奥创的文件、服务或注册表
- 替用户下载并运行 G-Helper、LLT 或卸载工具；只给官方下载地址，由用户自己下载，下载后用 `oem_switch.ps1 -Mode CheckFile` 校验签名
- `bcdedit` 写操作、超频、改电压或功耗墙、刷 BIOS/EC
- 关闭内存完整性、Defender 或其他安全防护来“提升性能”
- 修改 `HKLM\SYSTEM\CurrentControlSet\Control\Power` 下除备份导入、`Attributes` 显示状态以外的任何值
- 下载 PSE 时不核对哈希，或使用 v0.2.0 以外未核实的版本；PSE 以外的任何第三方 exe 都不代为下载运行
- 在 `tune_system.ps1` 以外关停其他服务（如 Windows Update 服务、Defender、BITS），或删除系统组件来「提升性能」
- 下载并运行第三方“电源优化器”exe

## 回滚

安装脚本会在 `%USERPROFILE%\Desktop\PowerPPKG_Backup_<时间>` 里留下：

- `power.reg`：安装前的 `HKLM\SYSTEM\CurrentControlSet\Control\Power` 完整导出
- `active_scheme.pow`：安装前活动电源方案导出
- `before_qh.txt`：安装前活动方案的全部设置（`powercfg /qh`），用于对比
- `install_log.txt`、`ppkg_logs\`：安装日志
- `undo.ps1`：撤销脚本

撤销顺序（`undo.ps1` 已按此写好）：

1. `Uninstall-ProvisioningPackage -PackageId <id>` 卸载预配包
2. `reg import power.reg` 写回安装前的电源设置
3. 重启，然后跑 `verify_ppkg.ps1 -BackupDir <备份目录>` 确认处理器设置已与 `before_qh.txt` 一致
4. 仍不一致时，可以用系统还原点；`powercfg -restoredefaultschemes` 只作为最后手段，事先说明它会清掉所有自定义方案

注意：`reg import` 只会写回备份里有的值，不会删除安装后新增的值。所以第 3 步的对比是必须的，不能只看命令有没有报错。

## 脚本规范

- 所有 `.ps1` 保存为 UTF-8 BOM；用 `powershell -NoProfile -ExecutionPolicy Bypass -File "<完整路径>"` 运行
- agent 直接执行的脚本里不能有 `pause`、`Read-Host`。交付给用户双击的版本才在结尾加 pause
- 需要管理员权限时：`Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<脚本>" -LogPath "<日志>"'`，提前告诉用户 UAC 弹窗点“是”，执行后读日志确认结果
- `install_ppkg.ps1 -DryRun` 不需要管理员，可先跑一遍给用户看计划；非管理员时读不到已装预配包，正式安装时会重新检查
- 脚本字符串里不要用中文弯引号 “”，PowerShell 会把它们当成字符串引号导致语法错误，用「」代替
- PowerShell 5.1 不支持 `&&`；不用 `wmic`；不要用 `cmd /c` 拼内联命令
- 改了脚本先跑 `scripts/selfcheck.ps1`（检查 BOM、语法和禁用写法）
- 脚本失败就停：读报错的文件和行号，修好再跑。扫描没成功不能声称已有扫描结果，更不能跳过扫描直接安装

## 与用户沟通

- 用普通话汇报：“你的 CPU 是 Ryzen 7 8845H，属于原生支持的 Hawk Point，可以装”，不要贴整段命令输出
- 不承诺具体帧率或续航数字。说“插电玩游戏时 CPU 会更积极地保持高频；用电池时会限制频率换续航”
- 安装后一定要说：需要重启；装完等几分钟再用 `Get-ProvisioningPackage` 检查，如果显示失败，readme 建议再等五分钟后重查
- 结束时给出：做了什么、备份目录和撤销方法、厂商软件可能覆盖效果的提醒
- 用户使用的是第三方分发的包（例如通过聊天工具转发的文件），要说明包来源是同方（Tongfang）OEM 预配包，本 skill 只核实了它的内容，不代表厂商对用户机型的支持承诺
