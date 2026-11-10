# install_ppkg.ps1 - L2：备份后安装通用 PPKG 1.44，并生成撤销脚本
# 用法（需管理员，必须在用户确认方案后才运行）:
#   Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<本文件完整路径>" -LogPath "C:\Users\Public\ppkg_install_log.txt"'
# 参数:
#   -PackagePath        安装包，默认 ..\assets\Tongfang.ppkg
#   -DryRun             只做检查和备份预演，不安装
#   -AllowUnsupported   CPU 不在目标表时仍安装（用户坚持时才传）
#   -AllowOtherPackages 已有其他预配包时仍安装（仅当用户明确知道冲突风险时才传）
#   -SkipPse            不安装 Power Settings Explorer、不显示隐藏电源项
#   -SkipTune           装完 PPKG 后不做系统性能项（tune_system.ps1）
#   -TuneOnly           只做其中几项: Nvidia,Search,Update,Browser,Steam
#   -CloseSteam         Steam 在运行时先正常退出它再改配置
#   -LogPath            日志路径（提权运行时必传，agent 靠它读结果）
# 无 pause、无交互。
param(
  [string]$PackagePath = "",
  [switch]$DryRun,
  [switch]$AllowUnsupported,
  [switch]$AllowOtherPackages,
  [switch]$SkipPse,
  [switch]$SkipTune,
  [string]$TuneOnly = "Nvidia,Search,Update,Browser,Steam",
  [switch]$CloseSteam,
  [string]$LogPath = ""
)
$ErrorActionPreference = "Stop"
$ExpectedSha256 = "6EF9F98C3BAED89F6BD2DA4F6EF20B6F72D9D529380DA6271705FA671D988E87"
$PackageId = "9e3b0e54-ceb9-4656-a2ce-54c92f07469d"
$PowerKey = "HKLM\SYSTEM\CurrentControlSet\Control\Power"

function Invoke-Child($script, [string[]]$argList) {
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $script)) + $argList
  if ($LogPath) { $a += @('-LogPath', $LogPath) }
  & powershell @a | ForEach-Object { Write-Host $_ }
  return $LASTEXITCODE
}
function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  Write-Output $line
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 }
}
function Fail($msg) { Log "[停止] $msg"; exit 1 }

try {
  if (-not $PackagePath) { $PackagePath = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\Tongfang.ppkg" }
  $PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
  Log "=== 通用 PPKG 1.44 安装 $(if($DryRun){'(预演)'}) ==="

  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin -and -not $DryRun) { Fail "需要管理员权限" }

  # 1. 安装包校验
  $hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
  if ($hash -ne $ExpectedSha256) { Fail "安装包哈希不符 ($hash)，不是已核实的 1.44 版" }
  Log "安装包校验通过: $PackagePath"

  # 2. 适配检查（复用 scan_power.ps1 的结论）
  $scan = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "scan_power.ps1") -Json | Out-String | ConvertFrom-Json
  Log ("系统: {0} (Build {1}); CPU: {2}; 平台角色: {3}; 适配: {4}" -f $scan.OS, $scan.Build, $scan.CPU, $scan.PowerPlatformRoleName, $scan.SupportLevel)
  if (-not $scan.IsWin11) { Fail "不是 Windows 11，readme 明确不支持" }
  if ($scan.PowerPlatformRole -ne $null -and $scan.PowerPlatformRole -notin 2,8) { Fail "平台角色不是笔记本/平板，PPKG 机型条件不会命中" }
  if ($scan.SupportLevel -eq "不在目标表" -and -not $AllowUnsupported) { Fail "CPU 不在目标表；用户坚持安装时加 -AllowUnsupported" }
  if ($scan.TongfangInstalled) { Fail "该预配包已安装，无需重复安装。需要重装请先运行备份目录里的 undo.ps1" }

  $installed = @(Get-ProvisioningPackage -AllInstalledPackages)
  $others = @($installed | Where-Object { $_.PackageID -ne $PackageId })
  if ($others.Count -gt 0) {
    $names = ($others | ForEach-Object { "$($_.PackageName) v$($_.Version) ($($_.OwnerType))" }) -join ', '
    if (-not $AllowOtherPackages) { Fail "已安装其他预配包: $names。请用户自行在「添加或删除预配包」中决定是否删除后再试" }
    Log "[注意] 已安装其他预配包，用户已确认继续: $names"
  }
  if ($scan.OemPowerTools.Count -gt 0) { Log ("[注意] 厂商电源软件可能覆盖效果: " + ($scan.OemPowerTools -join ', ')) }

  # 3. 备份
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $desktop = [Environment]::GetFolderPath("Desktop")
  $backup = Join-Path $desktop "PowerPPKG_Backup_$stamp"
  if ($DryRun) {
    Log "[预演] 将创建备份目录: $backup"
    Log "[预演] 将创建系统还原点、导出 $PowerKey、导出活动电源方案、记录 powercfg /qh"
    if (-not $SkipPse) { [void](Invoke-Child "setup_pse.ps1" @("-BackupDir", $backup, "-DryRun")) }
    Log "[预演] 将执行: Install-ProvisioningPackage -PackagePath `"$PackagePath`" -QuietInstall"
    if (-not $SkipTune) { [void](Invoke-Child "tune_system.ps1" @("-DryRun", "-Only", $TuneOnly)) }
    Log "=== 预演结束，未做任何修改 ==="
    exit 0
  }
  New-Item -ItemType Directory -Path $backup | Out-Null
  Log "备份目录: $backup"

  try {
    Checkpoint-Computer -Description "Before PPKG Tongfang 1.44" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Log "已创建系统还原点"
  } catch {
    Log "[提示] 还原点未创建（可能 24 小时内已建过或系统保护关闭）: $($_.Exception.Message)；注册表备份仍会兜底"
  }

  & reg.exe export $PowerKey (Join-Path $backup "power.reg") /y | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "导出电源注册表失败，未安装" }
  $activeGuid = $null
  if ((powercfg /getactivescheme) -join ' ' -match '([0-9a-fA-F-]{36})') { $activeGuid = $Matches[1] }
  if ($activeGuid) { & powercfg /export (Join-Path $backup "active_scheme.pow") $activeGuid | Out-Null }
  powercfg /qh | Out-File -LiteralPath (Join-Path $backup "before_qh.txt") -Encoding UTF8
  $scan | ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $backup "scan_before.json") -Encoding UTF8
  @{ PackageId = $PackageId; PackagePath = $PackagePath; ActiveScheme = $activeGuid; Time = $stamp } | ConvertTo-Json | Out-File -LiteralPath (Join-Path $backup "meta.json") -Encoding UTF8
  Log "已备份: power.reg, active_scheme.pow, before_qh.txt"

  # 3.5 配置电源模式前的准备：安装 Power Settings Explorer，并显示处理器隐藏电源项
  if (-not $SkipPse) {
    $rc = Invoke-Child "setup_pse.ps1" @("-BackupDir", $backup)
    if ($rc -ne 0) { Fail "Power Settings Explorer 准备失败，未安装 PPKG（不需要它时加 -SkipPse）" }
  }

  # 4. 撤销脚本（先写好再安装，安装中途失败也能撤销）
  $undo = @"
# undo.ps1 - 撤销通用 PPKG 1.44（由 install_ppkg.ps1 生成于 $stamp）
# 用法: 右键「以管理员身份运行 PowerShell」，执行: powershell -NoProfile -ExecutionPolicy Bypass -File "$backup\undo.ps1"
`$ErrorActionPreference = "Continue"
`$log = Join-Path "$backup" "undo_log.txt"
function L(`$m) { `$t = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), `$m; Write-Output `$t; Add-Content -LiteralPath `$log -Value `$t -Encoding UTF8 }
`$pk = Get-ProvisioningPackage -AllInstalledPackages | Where-Object { `$_.PackageID -eq "$PackageId" }
if (`$pk) { Uninstall-ProvisioningPackage -PackageId "$PackageId"; L "已卸载预配包 Tongfang" } else { L "预配包未安装，跳过卸载" }
& reg.exe import "$backup\power.reg"
if (`$LASTEXITCODE -eq 0) { L "已导入安装前的电源注册表备份" } else { L "导入注册表备份失败，退出码 `$LASTEXITCODE" }
if (Test-Path "$backup\pse_state.json") { & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\setup_pse.ps1" -Mode Undo -BackupDir "$backup" -LogPath `$log; L "已恢复电源设置显示状态" }
if (Test-Path "$backup\tune_state.json") { & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\tune_system.ps1" -Mode Undo -BackupDir "$backup" -LogPath `$log; L "已恢复系统性能项（NVIDIA/搜索/更新/浏览器/Steam）" }
if ("$activeGuid") { & powercfg /setactive "$activeGuid"; L "已切回原活动方案 $activeGuid" }
L "完成。请重启，然后运行 verify_ppkg.ps1 -BackupDir `"$backup`" 确认设置已恢复"
"@
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText((Join-Path $backup "undo.ps1"), $undo, $utf8Bom)
  Log "已生成撤销脚本: $backup\undo.ps1"

  # 5. 安装
  $logs = Join-Path $backup "ppkg_logs"
  New-Item -ItemType Directory -Path $logs | Out-Null
  $res = Install-ProvisioningPackage -PackagePath $PackagePath -QuietInstall -LogsDirectoryPath $logs
  Log ("安装命令已返回: {0} v{1} IsInstalled={2} Result={3}" -f $res.PackageName, $res.Version, $res.IsInstalled, $res.Result)

  # 6. 配置电源模式后的系统性能项
  if (-not $SkipTune) {
    $targs = @("-BackupDir", $backup, "-Only", $TuneOnly)
    if ($CloseSteam) { $targs += "-CloseSteam" }
    $rc = Invoke-Child "tune_system.ps1" $targs
    if ($rc -ne 0) { Log "[注意] 系统性能项有失败，PPKG 已安装；详见上方日志，可单独重跑 tune_system.ps1" }
  }
  Log "=== 完成。请重启电脑；重启后运行 verify_ppkg.ps1 -BackupDir `"$backup`" 校验 ==="
  Log "撤销方法: 以管理员身份运行 $backup\undo.ps1"
} catch {
  Fail ("异常: {0} (行 {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
}
