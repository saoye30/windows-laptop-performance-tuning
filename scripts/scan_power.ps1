# scan_power.ps1 - L0 只读扫描：判断本机是否适合安装通用 PPKG 1.44
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File scan_power.ps1 [-Json]
# 不修改任何东西；无 pause、无交互，agent 可直接调用。部分项目需要管理员权限才能读到，读不到会标注。
param([switch]$Json)
$ErrorActionPreference = "Stop"

# 目标表与 PPKG customizations.xml 的 Targets 一一对应（修改时必须同步 references/supported-cpus.md）
$targets = @(
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(189);          Name="Intel Lunar Lake";            Level="原生支持" },
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(197);          Name="Intel Arrow Lake-H";          Level="原生支持" },
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(198);          Name="Intel Arrow Lake-HX";         Level="原生支持" },
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(183);          Name="Intel Raptor Lake-HX/HX Refresh"; Level="原生支持" },
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(186,191);      Name="Intel Raptor Lake-H/P";       Level="原生支持" },
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(170,172,181);  Name="Intel Meteor Lake (181 也匹配 Arrow Lake 组)"; Level="原生支持" },
  @{ Vendor="GenuineIntel"; Family=6;  Models=@(151,154);      Name="Intel Alder Lake";            Level="仅兼容" },
  @{ Vendor="AuthenticAMD"; Family=26; Models=@(96);           Name="AMD Krackan Point";           Level="原生支持" },
  @{ Vendor="AuthenticAMD"; Family=26; Models=@(32,36);        Name="AMD Strix Point";             Level="原生支持" },
  @{ Vendor="AuthenticAMD"; Family=26; Models=@(64,68);        Name="AMD Fire Range";              Level="原生支持" },
  @{ Vendor="AuthenticAMD"; Family=25; Models=@(117);          Name="AMD Hawk Point (HPT1)";       Level="原生支持" },
  @{ Vendor="AuthenticAMD"; Family=25; Models=@(124);          Name="AMD Hawk Point (HPT2)";       Level="原生支持" },
  @{ Vendor="AuthenticAMD"; Family=25; Models=@(112,116,120);  Name="AMD Phoenix";                 Level="原生支持" },
  @{ Vendor="AuthenticAMD"; Family=25; Models=@(96,97);        Name="AMD Dragon Range / Rembrandt"; Level="仅兼容" }
)

# 会动态改写电源方案的厂商软件（只报告，不处理）
$oemPattern = 'ArmouryCrate|ArmourySocketServer|LenovoVantage|LegionZone|Lenovo\.Modern|LenovoPcManager|LenovoPCManager|LegionSpace|ImController|HONOR|MSI\.CentralServer|MSI_Center|OmenCommandCenter|HPOmen|DragonCenter|AlienwareCommandCenter|AWCC|ControlCenter|GCUService|Clevo|RazerCentral|AcerPredatorSense|PredatorSense|NitroSense'

$r = [ordered]@{}
$warn = New-Object System.Collections.ArrayList

$os = Get-CimInstance Win32_OperatingSystem
$r.OS = $os.Caption
$r.Build = [int]$os.BuildNumber
$r.IsWin11 = ($r.Build -ge 22000)
if (-not $r.IsWin11) { [void]$warn.Add("不是 Windows 11（Build $($r.Build)），readme 明确不支持，不要安装") }

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$r.CPU = $cpu.Name.Trim()
$r.CPUVendor = $cpu.Manufacturer
$r.CPUDescription = $cpu.Description
$fam = $null; $mod = $null
if ($cpu.Description -match 'Family (\d+) Model (\d+)') { $fam = [int]$Matches[1]; $mod = [int]$Matches[2] }
$r.Family = $fam; $r.Model = $mod

$hit = $targets | Where-Object { $_.Vendor -eq $cpu.Manufacturer -and $_.Family -eq $fam -and ($_.Models -contains $mod) } | Select-Object -First 1
if ($hit) { $r.Target = $hit.Name; $r.SupportLevel = $hit.Level }
else { $r.Target = $null; $r.SupportLevel = "不在目标表"; [void]$warn.Add("CPU 不在 PPKG 目标表中，只会应用通用部分，默认不建议安装") }
if ($hit -and $hit.Level -eq "仅兼容") { [void]$warn.Add("CPU 属于「仅兼容」档，收益可能很小") }

# 平台角色: 用 powrprof 的 PowerDeterminePlatformRoleEx，与 PPKG 的 PowerPlatformRole 条件同源
try {
  Add-Type -Namespace PpkgScan -Name Pow -MemberDefinition '[DllImport("powrprof.dll")] public static extern int PowerDeterminePlatformRoleEx(uint version);' -ErrorAction Stop
  $r.PowerPlatformRole = [PpkgScan.Pow]::PowerDeterminePlatformRoleEx(2)
} catch {
  $r.PowerPlatformRole = $null
}
$roleNames = @{0="未指定";1="台式机";2="笔记本(Mobile)";3="工作站";4="企业服务器";5="SOHO 服务器";6="家电 PC";7="性能服务器";8="平板(Slate)"}
$r.PowerPlatformRoleName = if ($r.PowerPlatformRole -ne $null) { $roleNames[[int]$r.PowerPlatformRole] } else { "读取失败" }
$cs = Get-CimInstance Win32_ComputerSystem
$r.Manufacturer = $cs.Manufacturer; $r.MachineModel = $cs.Model
if ($r.PowerPlatformRole -ne $null -and $r.PowerPlatformRole -notin 2,8) { [void]$warn.Add("平台角色不是笔记本/平板，PPKG 的机型条件不会命中") }

$hasBattery = [bool](Get-CimInstance Win32_Battery)
$r.HasBattery = $hasBattery
$r.OnAC = $null
try { Add-Type -AssemblyName System.Windows.Forms; $r.OnAC = ([System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Online') } catch {}

$active = (powercfg /getactivescheme) -join ' '
$r.ActiveScheme = $active
$r.ActiveIsStockBalanced = ($active -match '381b4222-f694-41f0-9685-ff5bb260df2e')
if (-not $r.ActiveIsStockBalanced) { [void]$warn.Add("当前活动方案不是系统「平衡」方案，PPKG 改的是平衡方案默认值，自定义方案未必继承") }

$overlay = $null
try { $overlay = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction Stop).ActiveOverlayAcPowerScheme } catch {}
$r.ActiveOverlayAc = $overlay

$r.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
try {
  $pk = @(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop)
  $r.InstalledPackages = @($pk | ForEach-Object { "{0} v{1} ({2}, {3}, Id={4})" -f $_.PackageName, $_.Version, $_.OwnerType, $_.Result, $_.PackageID })
  $r.TongfangInstalled = [bool]($pk | Where-Object { $_.PackageID -eq '9e3b0e54-ceb9-4656-a2ce-54c92f07469d' })
  $others = @($pk | Where-Object { $_.PackageID -ne '9e3b0e54-ceb9-4656-a2ce-54c92f07469d' })
  if ($others.Count -gt 0) { [void]$warn.Add("已安装其他预配包，需用户决定是否先删除: " + (($others | ForEach-Object PackageName) -join ', ')) }
} catch {
  $r.InstalledPackages = "读取失败（通常需要管理员权限）: $($_.Exception.Message)"
  $r.TongfangInstalled = $null
}

$oem = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $oemPattern } | Select-Object -ExpandProperty Name -Unique)
$r.OemPowerTools = $oem
$r.ReplacementTools = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^GHelper$|Lenovo Legion Toolkit' } | Select-Object -ExpandProperty Name -Unique)
if ($r.ReplacementTools.Count -gt 0) { [void]$warn.Add("正在使用 " + ($r.ReplacementTools -join ', ') + "：请把它的模式对应到 Windows 电源模式，活动方案保持系统「平衡」，见 SKILL.md「替换后和 PPKG 的配合」") }
if ($oem.Count -gt 0) { [void]$warn.Add("检测到厂商或第三方电源/性能管理软件（" + ($oem -join ', ') + "），可能覆盖 PPKG 效果；华硕/联想可按 oem_switch 流程在用户确认后替换") }

$r.Warnings = @($warn)
$blocking = (-not $r.IsWin11) -or ($r.PowerPlatformRole -ne $null -and $r.PowerPlatformRole -notin 2,8)
$r.Verdict = if ($blocking) { "不建议安装" } elseif (-not $hit) { "默认不装（不在目标表）" } elseif ($hit.Level -eq "仅兼容") { "可装，收益可能小" } else { "可装" }

if ($Json) { $r | ConvertTo-Json -Depth 4 }
else {
  "=== 电源模式 PPKG 适配扫描 ==="
  foreach ($k in $r.Keys) { if ($k -ne 'Warnings') { "{0,-24}: {1}" -f $k, (($r[$k]) -join '; ') } }
  "--- 提示 ---"
  if ($warn.Count -eq 0) { "（无）" } else { $warn | ForEach-Object { "- $_" } }
}
