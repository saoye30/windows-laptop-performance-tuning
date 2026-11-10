# uninstall_ppkg.ps1 - L2：在没有 undo.ps1（例如用户手动双击安装过）时卸载通用 PPKG 1.44
# 用法（需管理员，用户确认后才运行）:
#   Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<本文件完整路径>" -LogPath "C:\Users\Public\ppkg_uninstall_log.txt"'
# 参数: -BackupDir 若有 install_ppkg.ps1 的备份目录，会一并导入 power.reg | -DryRun 只报告不修改
# 注意: 没有备份时只能卸载预配包，电源值是否回到默认要重启后用 verify_ppkg.ps1 和 powercfg 检查。
#       powercfg -restoredefaultschemes 会删掉所有自定义方案（含 G-Helper 等软件建的方案），本脚本不会自动执行。
param([string]$BackupDir = "", [switch]$DryRun, [string]$LogPath = "")
$ErrorActionPreference = "Stop"
$PackageId = "9e3b0e54-ceb9-4656-a2ce-54c92f07469d"
function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  Write-Output $line
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 }
}
try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { Log "[停止] 需要管理员权限"; exit 1 }
  $pk = Get-ProvisioningPackage -AllInstalledPackages | Where-Object { $_.PackageID -eq $PackageId }
  if (-not $pk) { Log "Tongfang 预配包未安装，无需卸载" }
  elseif ($DryRun) { Log "[预演] 将卸载 $($pk.PackageName) v$($pk.Version)" }
  else { Uninstall-ProvisioningPackage -PackageId $PackageId | Out-Null; Log "已卸载 $($pk.PackageName) v$($pk.Version)" }

  if ($BackupDir) {
    $reg = Join-Path $BackupDir "power.reg"
    if (-not (Test-Path -LiteralPath $reg)) { Log "[跳过] 备份目录里没有 power.reg" }
    elseif ($DryRun) { Log "[预演] 将导入 $reg" }
    else {
      & reg.exe import $reg
      if ($LASTEXITCODE -eq 0) { Log "已导入安装前电源注册表备份" } else { Log "[失败] 导入备份退出码 $LASTEXITCODE" }
    }
  } else { Log "[提示] 未提供备份目录，只卸载了预配包" }
  Log "完成。请重启后运行 verify_ppkg.ps1 检查"
} catch { Log ("[停止] 异常: {0} (行 {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber); exit 1 }
