# setup_pse.ps1 - 配置电源模式前的准备：安装 Power Settings Explorer（PSE），并显示处理器的隐藏电源设置
# 用法（需管理员，由 install_ppkg.ps1 自动调用，也可单独运行）:
#   powershell -NoProfile -ExecutionPolicy Bypass -File setup_pse.ps1 -BackupDir "<备份目录>" [-LogPath <日志>] [-DryRun]
#   撤销: ... -Mode Undo -BackupDir "<备份目录>"
# 说明:
#   - PSE 只有图形界面、没有命令行参数，所以「显示隐藏项」由本脚本调用 powrprof.dll 的 PowerWriteSettingAttributes 完成，
#     与 PSE 的 On 用同一个 API、同一个值（2）；PSE 装好后留给用户查看。
#   - 只下载固定版本，SHA256 必须与 GitHub Release 公布的 digest 一致，否则不安装。
#   - 只改处理器组设置项的显示状态（Attributes），不改任何插电/电池数值。无 pause、无交互。
param(
  [ValidateSet("Install", "Undo")]
  [string]$Mode = "Install",
  [string]$BackupDir = "",
  [string]$LogPath = "",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$PseVersion = "v0.2.0"
$PseUrl = "https://github.com/WtekSupport/PowerSettingsExplorer/releases/download/v0.2.0/power-settings-explorer.exe"
$PseSha256 = "EA980776B9434F8956787BE6EEE3FD263BFEE87C99A1736B57F68E4B4DFC6E1A"
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\PowerSettingsExplorer"
$ExePath = Join-Path $InstallDir "power-settings-explorer.exe"
$Shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Power Settings Explorer.lnk"
$ProcessorGuid = "54533251-82be-4824-96c1-47b60b740d00"
$Root = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings"

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

try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin -and -not $DryRun) { Log "[停止] 需要管理员权限"; exit 1 }
  if (-not $BackupDir) { Log "[停止] 必须指定 -BackupDir"; exit 1 }
  $visCsv = Join-Path $BackupDir "power_visibility_before.csv"
  $stateFile = Join-Path $BackupDir "pse_state.json"

  if ($Mode -eq "Undo") {
    if (Test-Path -LiteralPath $visCsv) {
      [void](Invoke-Child "power_visibility.ps1" @("-Mode", "Restore", "-BackupFile", $visCsv))
    } else { Log "[跳过] 没有显示状态备份" }
    $state = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } else { $null }
    if ($state -and $state.InstalledByUs) {
      Remove-Item -LiteralPath $ExePath -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $Shortcut -Force -ErrorAction SilentlyContinue
      if ((Test-Path $InstallDir) -and -not (Get-ChildItem $InstallDir -Force)) { Remove-Item -LiteralPath $InstallDir -Force }
      Log "已移除本流程安装的 PSE"
    } else { Log "PSE 不是本流程安装的，保留" }
    exit 0
  }

  # 1. 安装 PSE
  $installedByUs = $false
  if ((Test-Path -LiteralPath $ExePath) -and ((Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash -eq $PseSha256)) {
    Log "PSE $PseVersion 已安装: $ExePath"
  } elseif ($DryRun) {
    Log "[预演] 将下载 $PseUrl 到 $ExePath，并校验 SHA256 = $PseSha256"
  } else {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $tmp = Join-Path $env:TEMP ("pse_" + [guid]::NewGuid().ToString("N") + ".exe")
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $PseUrl -OutFile $tmp -UseBasicParsing
    $h = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    if ($h -ne $PseSha256) { Remove-Item -LiteralPath $tmp -Force; Log "[停止] PSE 哈希不符 ($h)，未安装"; exit 1 }
    Move-Item -LiteralPath $tmp -Destination $ExePath -Force
    $installedByUs = $true
    try {
      $ws = New-Object -ComObject WScript.Shell
      $lnk = $ws.CreateShortcut($Shortcut); $lnk.TargetPath = $ExePath; $lnk.WorkingDirectory = $InstallDir; $lnk.Save()
    } catch { Log "[提示] 开始菜单快捷方式未创建: $($_.Exception.Message)" }
    Log "已安装 PSE $PseVersion（哈希校验通过，无数字签名）: $ExePath"
  }
  if (-not $DryRun) { @{ InstalledByUs = $installedByUs; Path = $ExePath; Version = $PseVersion } | ConvertTo-Json | Out-File -LiteralPath $stateFile -Encoding UTF8 }

  # 2. 备份显示状态，再显示处理器组隐藏项
  $settings = Get-ChildItem -LiteralPath (Join-Path $Root $ProcessorGuid) | Where-Object { $_.PSChildName -match '^[0-9a-fA-F-]{36}$' }
  $hidden = @($settings | Where-Object { $a = (Get-ItemProperty -LiteralPath $_.PSPath -Name Attributes -ErrorAction SilentlyContinue).Attributes; $null -ne $a -and ($a -band 1) })
  if ($DryRun) { Log "[预演] 将备份显示状态，并显示处理器组 $($hidden.Count) 个隐藏项"; exit 0 }
  $rc = Invoke-Child "power_visibility.ps1" @("-Mode", "Backup", "-BackupFile", $visCsv)
  if ($rc -ne 0 -or -not (Test-Path -LiteralPath $visCsv)) { Log "[停止] 显示状态备份失败，未修改"; exit 1 }
  Add-Type -Namespace PseSetup -Name Pow -MemberDefinition '[DllImport("powrprof.dll")] public static extern uint PowerWriteSettingAttributes(ref Guid subGroup, ref Guid setting, uint attributes);'
  $sub = [guid]$ProcessorGuid
  $ok = 0; $fail = 0
  foreach ($s in $hidden) {
    $g = [guid]$s.PSChildName
    # 2 = 在高级电源设置中显示（与 PSE 的 On 相同）
    $rc = [PseSetup.Pow]::PowerWriteSettingAttributes([ref]$sub, [ref]$g, 2)
    if ($rc -eq 0) { $ok++ } else { $fail++; Log "[提示] $($s.PSChildName) 显示失败，错误码 $rc" }
  }
  Log "已显示处理器组隐藏项 $ok 个（失败 $fail 个）。在「控制面板 → 电源选项 → 更改高级电源设置」或 PSE 里可以看到"
} catch {
  Log ("[停止] 异常: {0} (行 {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
  exit 1
}
