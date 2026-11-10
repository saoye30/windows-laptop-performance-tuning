# 通用 PPKG 1.44 支持的 CPU

来源：包内 `customizations.xml` 的 Targets 段，以及 `ReleaseNote.txt` 的 Support list。所有目标还要求 PowerPlatformRole 为 2（笔记本）或 8（平板），台式机不命中。

CPU 家族和型号取自 `Get-CimInstance Win32_Processor` 的 Description，例如 `AMD64 Family 25 Model 117 Stepping 2`。

| 厂商 | Family | Model | 代号 | 典型型号 | Release Note 级别 | 包内变体组 |
|---|---|---|---|---|---|---|
| Intel | 6 | 189 | Lunar Lake (LNL) | Core Ultra 2xxV | 原生支持 | A |
| Intel | 6 | 198 | Arrow Lake-HX | Core Ultra 2xxHX | 原生支持 | B |
| Intel | 6 | 183 | Raptor Lake-HX / Refresh | 13xxxHX、14xxxHX | 原生支持 | B |
| Intel | 6 | 186、191 | Raptor Lake-H/P | 13xxxH、13xxxP | 原生支持 | C |
| Intel | 6 | 151、154 | Alder Lake | 12xxxH/P/HX | 仅兼容 | C |
| Intel | 6 | 197、181 | Arrow Lake-H | Core Ultra 2xxH | 原生支持 | D |
| Intel | 6 | 170、172、181 | Meteor Lake | Core Ultra 1xxH | 原生支持 | D |
| AMD | 25 | 112、116、120 | Phoenix (PHX) | 7x40U/H/HS | 原生支持 | E |
| AMD | 25 | 96、97 | Dragon Range / Rembrandt | 7x45HX、6000 系列 | 仅兼容 | E |
| AMD | 26 | 64、68 | Fire Range (FRR) | 9955HX 等 | 原生支持 | E |
| AMD | 25 | 117 | Hawk Point (HPT1) | 8x45H/HS/U | 原生支持 | E |
| AMD | 25 | 124 | Hawk Point (HPT2) | 8x40U 等 | 原生支持 | F |
| AMD | 26 | 32、36 | Strix Point (STP/STX) | Ryzen AI 9 HX 370 等 | 原生支持 | F |
| AMD | 26 | 96 | Krackan Point (KRK) | Ryzen AI 7 350 等 | 原生支持 | G |

变体组含义见 `ppkg-1.44-settings.md`。

说明：

- Release Note 写的“Intel TGL or later”和“AMD RMB or later”属于兼容范围，但 Tiger Lake 等更早 CPU 不在 Targets 里，只会拿到通用部分的设置。
- 包里定义了 `FRG2CCD`（Fire Range 的 Ryzen 9）和 `DRG2CCD`（Dragon Range，不限平台角色）两个目标，但没有任何变体引用它们，实际没有效果。
- Model 181 同时出现在 Arrow Lake 和 Meteor Lake 两组，两组的变体设置相同，不冲突。
- 型号举例仅供参考，以 Family/Model 匹配结果为准。
