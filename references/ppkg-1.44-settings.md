# 通用 PPKG 1.44 的设置明细

来源：拆包后的 `Multivariant/0/customizations.xml`（与 `Prov/RunTime/*.provxml` 数值一致）。所有设置都在 `Power/Policy/Settings/Processor/SchemePersonality` 下，写入的是电源方案的默认值，不是用户当前方案的覆盖值。

## 名词

| 名词 | 含义 |
|---|---|
| SchemeAlias=Balanced | 系统“平衡”方案 381b4222-f694-41f0-9685-ff5bb260df2e |
| BetterBatteryLifeOverlay | 电源模式“最佳能效”叠加层 961cc777-2547-4f9d-8174-7d86181b8a7a |
| MaxPerformanceOverlay | 电源模式“最佳性能”叠加层 ded574b5-45a0-4f42-8737-46345c09c238 |
| ProfileAlias | PPM 场景配置。Default 平时；GameMode 游戏模式；Constrained 受限（后台/低功耗）；Eco 效率模式进程；Multimedia 视频播放；LowLatency 低延迟突发；Utility 后台工具类 |
| AcValue / DcValue | 插电 / 电池 |
| PerfEnergyPreference (EPP) | 0 = 全力性能，100 = 最省电；带 1 后缀的是第二类核心（混合架构的另一类核心）|
| MaxFrequency | 频率上限，单位 MHz；0 表示不限 |
| CPMinCores / CPMaxCores | 核心停放时最少/最多不停放的核心百分比 |
| CPIncreaseTime / CPDecreaseTime | 解除/进入核心停放前的检查周期数 |
| SchedulingPolicy / ShortSchedulingPolicy | 长/短线程优先调度到哪类核心 |
| HeteroPolicy=4 | 混合架构调度策略 4（自动）|

## 通用部分（所有机器）

### 平衡方案

| 场景 | 设置 |
|---|---|
| Multimedia | 电池：MaxFrequency 1500 / MaxFrequency1 1500，EPP 100 / 100 |
| LowLatency | EPP 插电 10，电池 60 |
| Eco | 电池：MaxFrequency 1500 / 1500，EPP 95 / 95 |
| Utility | EPP 插电 95、电池 95（两类核心相同）|
| Default | 电池：CPConcurrency 95，CPHeadroom 40，CPIncreaseTime 4，CPDecreaseTime 1，CPMaxCores 100 / 100，CpLatencyHintUnpark 0 / 0，HeteroClass0FloorPerf 0，HeteroClass1InitialPerf 0，HeteroIncrease/DecreaseTime 1，Idle Promote/Demote 0，ModuleUnparkPolicy 顺序，EPP 80 / 80，SoftParkLatency 0 |
| GameMode | 插电：CPDecreaseTime 30（游戏时核心更晚进入停放）|
| Constrained | 电池：CPConcurrency 99，CPHeadroom 40，CPIncreaseTime 4，CPDecreaseTime 1，CpLatencyHintUnpark 0 / 0，Hetero 系列同 Default，EPP 95 / 95 |

### 最佳能效叠加层

与平衡方案相同的场景，区别：

| 场景 | 与平衡方案的差异 |
|---|---|
| Eco | 电池 EPP 100 / 100 |
| Utility | EPP 100（插电和电池）|
| Default | 电池 CPConcurrency 99，MaxFrequency 2500 / MaxFrequency1 3000，EPP 95 / 95 |
| Constrained | 电池 MaxFrequency 2000 / 2500 |

## 按 CPU 的变体

| 组 | 适用 | 设置 |
|---|---|---|
| A | Lunar Lake | 平衡 Default 电池：HeteroPolicy 4，长/短线程调度“优先能效核”；Constrained 电池：调度“仅能效核”；GameMode 插电 EPP1 = 0；最佳性能叠加层 GameMode 插电 EPP1 = 0 |
| B | Arrow Lake-HX、Raptor Lake-HX | 同 A |
| C | Raptor Lake-H/P、Alder Lake | 平衡 Default 和 Constrained 电池：调度“仅能效核”；GameMode 插电 EPP1 = 0；最佳性能叠加层 GameMode 插电 EPP1 = 0 |
| D | Arrow Lake-H、Meteor Lake | 同 C |
| E | Phoenix、Dragon Range、Fire Range、Hawk Point HPT1 | 平衡 Default 电池：CPMinCores 25，EPP 95，SMT 顺序解除停放；GameMode 插电 EPP = 0；Constrained 电池：MaxFrequency 1900，EPP 95；最佳能效 Default 电池：MaxFrequency 1900，EPP 95；最佳能效 Constrained 电池：MaxFrequency 1600，EPP 100；最佳性能叠加层 GameMode 插电 EPP = 0 |
| F | Strix Point、Hawk Point HPT2 | 平衡 Default 电池：CPMinCores 0 / CPMinCores1 25，HeteroPolicy 4，EPP 95 / 95，调度“优先性能核”，SMT 顺序；Constrained 电池：调度“仅性能核”，MaxFrequency 1900；最佳能效 Default 电池 MaxFrequency 1900；最佳能效 Constrained 电池 MaxFrequency 1600、EPP 100；GameMode 插电 EPP1 = 0；最佳性能叠加层 GameMode 插电 EPP1 = 0 |
| G | Krackan Point | 与 F 相近，调度均为“优先性能核”；最佳能效 Constrained 电池：CPMinCores 25 / CPMinCores1 0，EPP 100，不限频；最佳性能叠加层 GameMode 插电 EPP 和 EPP1 都为 0 |

## 实际效果（给用户解释时用）

- **插电打游戏**：Windows 识别到游戏模式时，CPU 能效偏好被压到 0，核心更晚停放，帧率更稳。Release Note 1.44 提到修复了游戏模式下 P 核最高频率。
- **用电池**：平时 EPP 80 到 95，后台、视频、效率模式进程限频 1500 MHz 左右，混合架构偏向能效核，续航更长，但电池下性能会明显降低。
- **台式机**：完全不适用。
- 1.44 去掉了线程调度相关设置（Release Note “Remove thread scheduling”），但变体里仍保留了按核心类型调度的策略，以包内实际内容为准。

## 版本记录（摘自 ReleaseNote.txt）

| 日期 | 版本 | 变化 |
|---|---|---|
| 2025-04-01 | 1.43（文件写的是 1.43，包内版本号为 1.44）| 去掉线程调度；修复游戏模式 P 核最高频率 |
| 2024-12-25 | 1.43 | 支持 Krackan 和 Lunar Lake |
| 2024-08-30 | 1.42 | 修改 Strix Point 游戏模式设置 |
| 2024-08-23 | 1.41 | 新框架；为《永劫无间》调整游戏模式；支持最佳性能叠加层 |
| 2024-02-17 | 1.38 | 新框架制作 PPKG |
| 2023-10-16 | 1.37 | 游戏模式下所有核心保持活动 |
| 2023-10-05 | 1.36 | 首个客户版本 |
