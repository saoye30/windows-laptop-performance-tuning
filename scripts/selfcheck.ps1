# selfcheck.ps1 - 静态自检：BOM、语法、禁用写法
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File selfcheck.ps1
$ErrorActionPreference = "Stop"
$fail = 0
$files = Get-ChildItem -Path $PSScriptRoot -Filter *.ps1
foreach ($f in $files) {
  $isSelf = ($f.Name -eq 'selfcheck.ps1')
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) { "[失败] $($f.Name): 不是 UTF-8 BOM"; $fail++ }
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
  foreach ($e in $errs) { "[失败] $($f.Name):$($e.Extent.StartLineNumber) 语法: $($e.Message)"; $fail++ }
  $code = ($tokens | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object Text) -join ' '
  # tune_system.ps1 只允许对 WSearch 停服务/改启动类型（撤销时按记录恢复）
  if ($f.Name -eq 'tune_system.ps1') { $code = $code -replace 'Stop-Service -Name WSearch','' -replace 'Set-Service -Name WSearch','' -replace 'Set-Service -Name \$r \. Name','' }
  if (-not $isSelf) { foreach ($p in @('\bpause\b', 'Read-Host', '\bwmic\b', '&&', 'bcdedit', '-ForceInstall', 'restoredefaultschemes', 'Remove-ProvisioningPackage', 'Stop-Service', 'Set-Service')) {
    if ($code -match $p) { "[失败] $($f.Name): 含禁用写法 $p"; $fail++ }
  } }
}
if ($fail -eq 0) { "自检通过: $($files.Count) 个脚本" } else { "自检失败: $fail 项"; exit 1 }
