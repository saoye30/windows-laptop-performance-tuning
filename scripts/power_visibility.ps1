# power_visibility.ps1 - 「高级电源设置」里隐藏项的显示状态：查看、备份、恢复
# 配合 Power Settings Explorer（PSE）使用：用 PSE 显示隐藏项之前先 Backup，想还原时 Restore。
# 用法:
#   查看（L0，不需管理员）: powershell -NoProfile -ExecutionPolicy Bypass -File power_visibility.ps1 [-Subgroup Processor|All]
#   备份（L0，只写文件）  : ... -Mode Backup
#   恢复（L2，需管理员）  : Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<本文件>" -Mode Restore -BackupFile "<备份 csv>" -LogPath "C:\Users\Public\power_visibility_log.txt"'
# 只读写各设置项下的 Attributes 值（是否在界面显示），不改任何 AC/DC 电源数值。无 pause、无交互。
param(
  [ValidateSet("Status", "Backup", "Restore")]
  [string]$Mode = "Status",
  [ValidateSet("Processor", "All")]
  [string]$Subgroup = "Processor",
  [string]$BackupFile = "",
  [string]$LogPath = ""
)
$ErrorActionPreference = "Stop"
$Root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
$ProcessorGuid = '54533251-82be-4824-96c1-47b60b740d00'

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  Write-Output $line
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 }
}

function Get-FriendlyName($path) {
  $n = (Get-ItemProperty -LiteralPath $path -Name FriendlyName -ErrorAction SilentlyContinue).FriendlyName
  if ($n) { return ($n -split ',')[-1].Trim() }
  return ""
}

function Get-Settings {
  $groups = if ($Subgroup -eq "Processor") { @(Get-Item -LiteralPath (Join-Path $Root $ProcessorGuid)) } else { @(Get-ChildItem -LiteralPath $Root) }
  foreach ($g in $groups) {
    foreach ($s in (Get-ChildItem -LiteralPath $g.PSPath -ErrorAction SilentlyContinue)) {
      if ($s.PSChildName -notmatch '^[0-9a-fA-F-]{36}$') { continue }
      $attr = (Get-ItemProperty -LiteralPath $s.PSPath -Name Attributes -ErrorAction SilentlyContinue).Attributes
      [pscustomobject]@{
        Subgroup   = $g.PSChildName
        Setting    = $s.PSChildName
        Attributes = if ($null -eq $attr) { "-" } else { [string]$attr }
        Hidden     = ($null -ne $attr -and ($attr -band 1))
        Name       = Get-FriendlyName $s.PSPath
      }
    }
  }
}

try {
  switch ($Mode) {
    "Status" {
      $all = @(Get-Settings)
      $hidden = @($all | Where-Object Hidden)
      "范围: $Subgroup；设置项 $($all.Count) 个，其中隐藏 $($hidden.Count) 个"
      "--- 隐藏项（PSE 里设为 On 后，会出现在「控制面板 → 电源选项 → 更改高级电源设置」）---"
      $hidden | Sort-Object Name | Format-Table Setting, Attributes, Name -AutoSize | Out-String -Width 220
    }
    "Backup" {
      if ($BackupFile) {
        $file = $BackupFile
        New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null
      } else {
        $dir = Join-Path ([Environment]::GetFolderPath("Desktop")) "PowerVisibility_Backup"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $file = Join-Path $dir ("attributes_{0}.csv" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
      }
      $Subgroup = "All"
      $rows = @(Get-Settings)
      $rows | Select-Object Subgroup, Setting, Attributes, Name | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8
      Log "已备份 $($rows.Count) 个设置项的显示状态: $file"
    }
    "Restore" {
      $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
      if (-not $isAdmin) { Log "[停止] 需要管理员权限"; exit 1 }
      if (-not $BackupFile -or -not (Test-Path -LiteralPath $BackupFile)) { Log "[停止] 找不到备份文件: $BackupFile"; exit 1 }
      $rows = Import-Csv -LiteralPath $BackupFile
      $n = 0; $skip = 0
      foreach ($r in $rows) {
        if ($r.Subgroup -notmatch '^[0-9a-fA-F-]{36}$' -or $r.Setting -notmatch '^[0-9a-fA-F-]{36}$') { $skip++; continue }
        $p = Join-Path (Join-Path $Root $r.Subgroup) $r.Setting
        if (-not (Test-Path -LiteralPath $p)) { $skip++; continue }
        $cur = (Get-ItemProperty -LiteralPath $p -Name Attributes -ErrorAction SilentlyContinue).Attributes
        $curS = if ($null -eq $cur) { "-" } else { [string]$cur }
        if ($curS -eq $r.Attributes) { continue }
        if ($r.Attributes -eq "-") { Remove-ItemProperty -LiteralPath $p -Name Attributes -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -LiteralPath $p -Name Attributes -Type DWord -Value ([int]$r.Attributes) }
        $n++
      }
      Log "已恢复 $n 项（$skip 项在本机不存在或格式不对，已跳过）。重新打开「高级电源设置」窗口即可看到"
    }
  }
} catch {
  Log ("[停止] 异常: {0} (行 {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
  exit 1
}
