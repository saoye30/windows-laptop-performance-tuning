# verify_ppkg.ps1 - L0 只读：重启后确认 PPKG 状态，并与安装前的处理器设置对比
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File verify_ppkg.ps1 [-BackupDir <备份目录>]
# 读取已安装预配包通常需要管理员权限；没有权限时只做设置对比。无 pause、无交互。
param([string]$BackupDir = "")
$ErrorActionPreference = "Stop"
$PackageId = "9e3b0e54-ceb9-4656-a2ce-54c92f07469d"

"=== PPKG 状态 ==="
try {
  $pk = Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop | Where-Object { $_.PackageID -eq $PackageId }
  if ($pk) {
    "已安装: {0} v{1}  IsInstalled={2}  Result={3}  安装时间={4}" -f $pk.PackageName, $pk.Version, $pk.IsInstalled, $pk.Result, $pk.LastInstallTime
    if ("$($pk.Result)" -match '^(0|Success)' -or $pk.IsInstalled) { "判定: 安装成功（readme 要求 True / Success / 0）" }
    else { "判定: 结果不是成功。readme 建议等五分钟后再查；仍失败就检查是否装过其他厂商 PPKG" }
  } else { "未安装 Tongfang 预配包" }
} catch { "读取预配包失败（通常需要管理员权限）: $($_.Exception.Message)" }

"=== 当前活动方案 ==="
powercfg /getactivescheme

if ($BackupDir) {
  $before = Join-Path $BackupDir "before_qh.txt"
  if (-not (Test-Path -LiteralPath $before)) { "找不到 $before，跳过对比"; return }
  "=== 与安装前对比（powercfg /qh 中发生变化的行）==="
  $now = powercfg /qh
  $old = Get-Content -LiteralPath $before -Encoding UTF8
  $diff = Compare-Object -ReferenceObject $old -DifferenceObject $now
  if (-not $diff) { "活动方案设置与安装前完全一致（撤销后应是这个结果；刚安装时一致说明效果被覆盖或尚未生效，可切回系统「平衡」方案后再查）" }
  else {
    $diff | ForEach-Object { "{0} {1}" -f $(if ($_.SideIndicator -eq '=>') { '现在' } else { '之前' }), $_.InputObject.Trim() }
  }
  "说明: PPKG 主要改的是各场景（游戏模式、电池等）的处理器配置，部分设置不在 powercfg /qh 的活动方案视图里，没有差异不一定代表未生效"
}
