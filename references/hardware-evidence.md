# 硬件检查与效果验证

本模块补充只读硬件清单、离线监控日志分析和调整前后对比。它不安装 PPKG、不改电压频率、不启动压力测试，也不注册管理员计划任务。仅在用户目标需要时调用；检查请求不等于允许修改。

## 1. 只读硬件检查

用户要求检查当前电脑即可视为该范围的采集授权，不重复询问。先确认命令作用于目标 Windows 本机，优先复用本次会话中仍有效的报告。硬件、驱动、供电或厂商模式改变后，旧报告必须标明时间与局限。

从项目根目录运行普通 Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\vendor\pc-hardware-workbench\scripts\collect-windows.ps1" -Format Markdown -RedactIdentifiers
```

默认推荐带 `-RedactIdentifiers`，隐藏部分设备标识，适合生成待分享的报告；它不是针对任意文本的完整隐私清理。若用户需要精确型号适配，可以说明用途后去掉该参数。两种模式均不主动上传数据、不输出序列号。数据只来自系统可读取字段，无法保证所有传感器可见。“只读”指不改变系统或硬件设置：采集器会编译本地查询代码、在临时目录生成并清理电池报告，并可能调用已存在的 NVIDIA 查询工具读取瞬时信息。

需要保存时，使用 `-OutputPath` 指定**已存在本地目录下的新文件**；不覆盖旧报告，不用网络路径。报告建议放在项目之外，避免随代码发布。例如先由用户选定本地报告目录，再传入完整的新文件路径。退出码非零时，不把部分输出当作有效报告。

汇报用户关心的 CPU/GPU、内存、磁盘、显示器、电池及读取限制。必须区分电池 `not-present` 与 `unavailable-permission` / `unavailable`。保留身份质量和来源，不从被隐藏、未知或冲突字段猜出机型。瞬时 NVIDIA 温度/功耗不能证明持续负载行为。

采集器不自行提权、不启动 UAC。需要管理员才能读取的字段先标为未读取；仅当影响用户决策且用户要求补充时，提供用户自行启动管理员 PowerShell 的命令。权限限制不能通过安装驱动、关闭防护或调整硬件来解决。

该报告不能代替 [PPKG 适配扫描](<../scripts/scan_power.ps1>)，也不能单凭配置推出“内存瓶颈”“散热不足”或“需要升级”。设备无法启动、正在抢救数据或出现物理危险时，不运行采集或建议压测。

## 2. 先约定可比条件

收集前后两份记录前，向用户用普通话明确：

- 同一电脑、同一应用/游戏版本、同一场景和画质；尽量保持环境、亮度、后台软件一致。
- 同一供电方式、充电状态、Windows 电源模式、厂商模式；如果其中一项就是被测试的变量，明确记录。
- 相同预热与记录时长，使用相同监控工具、传感器和采样间隔。
- 一轮只改变一个可解释的变量；若一次安装了多组设置，只能评估这一整组，不能归因给某个开关。
- 预先说明目标指标、停止条件和恢复方式。出现异常温度、蓝屏、重启、明显卡顿恶化等情况停止测试，保留记录并排查。

分清三件事：**计划修改什么、实际读到什么、数据能支持什么结论**。读取失败就是未知，测试中断就是未完成。一次短测试或无报错日志不证明长期稳定，也不证明所有传感器正常。

用户自行用可信的监控工具记录日常工作负载并导出 CSV。本集成不提供自动安装监控软件、开启共享内存、启动长时间负载、SMU/Curve Optimizer 写入或无人值守监督。没有前测数据时，仅描述现状或建议重新采样，不能倒推收益。

## 3. 分析一份或两份 CSV

支持 HWiNFO、PresentMon 和结构兼容的文本 CSV；实际识别取决于字段名称、单位和时间列，不能保证所有工具版本的导出都兼容。用户只提供截图时只能解释可见瞬时信息，不能把它当作时间序列或生成虚构统计。

只有一份日志：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\vendor\pc-hardware-workbench\scripts\run-evidence-pipeline.ps1" -BaselinePath "C:\Measurements\before.csv" -OutputDirectory "C:\Measurements\reports" -Workload "同一游戏固定场景" -HideFileName
```

前后对比（路径需替换成用户实际指定的本地文件）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\vendor\pc-hardware-workbench\scripts\run-evidence-pipeline.ps1" -BaselinePath "C:\Measurements\before.csv" -CandidatePath "C:\Measurements\after.csv" -OutputDirectory "C:\Measurements\reports" -Workload "同一游戏同画质固定场景，插电平衡模式" -Change "仅安装 PPKG，跳过 PSE 与系统性能项" -HideFileName
```

`-Workload` 与 `-Change` 必须反映真实记录，不能照抄示例当作已知事实。文件必须不同，输出目录使用本地目录。默认不覆盖输入日志，每次创建独立结果子目录。

如需裁掉预热，按真实日志选择 `-WarmupSeconds` 与 `-DurationSeconds`，或 `-WarmupRows` 与 `-MaxRows`，不混用时间窗口和行数窗口。不要为了产生好看结果只保留有利区间。可使用 `-FocusMetric` 指定重点指标；未被识别的字段应解释并核对，不擅自补值。

流程会校验指标名称、单位、采样间隔与窗口，生成分析 JSON、标准化数据、SVG 图、汇总和独立 HTML 报告。它不能仅靠 CSV 判断是不是同一电脑、真实游戏场景或实际生效设置，这些必须从用户信息和配置记录确认。

## 4. 解释报告

每次运行结果包括 `summary.md`、`evidence-card.html`、`evidence-package.json`，以及基线/候选分析和图表。状态含义：

| 状态 | 应如何解释 |
|---|---|
| `baseline-ready` | 已有基线；需要可比的后测才能评价变化 |
| `ready-for-review` | 找到可比指标和采样信息，可以审阅；不等于测试通过 |
| `review` | 有警告，需解释限制后决定是否重新采样 |
| `retest` | 缺少可比指标，不能据此给出改善结论 |

结合均值、峰值、P95 等信息，避免均值掩盖卡顿或温度尖峰。温度用摄氏度差值，不以摄氏温度百分比描述改善。帧率提升需要可比帧率数据；瞬时功耗下降不能直接换算续航增加。

最后用简明文字给出：可确认的变化、不可确认的部分、数据局限，以及“建议保留 / 恢复 / 重新测量 / 停止排查”。这是建议，不授权自动执行撤销或其他设置修改。PPKG 安装/撤销是否成功仍按原校验脚本和日志单独判断。

## 5. 隐私与依赖

原始日志可能包含硬件名称、路径或用户标识。`-HideFileName` 只隐藏报告中的原始文件名，不保证传感器名称或内容完全匿名。报告默认保留本地，发布或上传前检查；不将真实电脑报告、日志或备份提交到技能仓库。

模块固定在 [PC Hardware Workbench](https://github.com/Feng23-feng/pc-hardware-workbench) 提交 `dc5a46891f36b50028f04c492f1e08e94d17604b`，保留其 [MIT 许可](<../vendor/pc-hardware-workbench/LICENSE>)。本集成只调用 Windows PowerShell 自带能力及系统已有的可选只读查询工具，不包含上游超频指导、购买路线、LHM 适配器或安装流程。

实验记录原则参考 [AI-PC-Overclocking 的方法说明](https://github.com/BOBOEMS/AI-PC-Overclocking/blob/2b437d0e273ecc5cf2b87df1702541f2bf9ced4b/README.md#L160-L164)，本文件为重新撰写，不引入该仓库执行代码、预设硬件参数、第三方二进制或高权限任务。
