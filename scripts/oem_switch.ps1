# oem_switch.ps1 - 厂商控制软件替换：华硕 奥创(Armoury Crate) → G-Helper；联想 Legion Zone/联想电脑管家/Vantage → Lenovo Legion Toolkit
# 用法:
#   扫描（L0，默认，不改任何东西）:
#     powershell -NoProfile -ExecutionPolicy Bypass -File oem_switch.ps1
#   校验用户下载的文件签名（L0）:
#     powershell -NoProfile -ExecutionPolicy Bypass -File oem_switch.ps1 -Mode CheckFile -File "<exe 或 zip 解压后的 exe>"
#   卸载用户已确认的条目（L2，需管理员；只接受扫描结果里的 Id）:
#     Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<本文件>" -Mode Uninstall -Ids "L1,L3" -LogPath "C:\Users\Public\oem_switch_log.txt"'
#   华硕奥创的卸载只走官方 Armoury Crate Uninstall Tool:
#     ... -Mode RunAsusTool -File "<解压后的 Armoury Crate Uninstall Tool.exe>"
# 规则: 本脚本不下载任何文件；不停止/禁用服务；不碰驱动和 ASUS System Control Interface / Lenovo Energy Management 等必需组件。
#       厂商卸载程序有图形界面时需要用户在弹窗里点完，脚本会等待它结束。无 pause、无 Read-Host。
param(
  [ValidateSet("Scan", "CheckFile", "Uninstall", "RunAsusTool")]
  [string]$Mode = "Scan",
  [string]$Ids = "",
  [string]$File = "",
  [string]$LogPath = ""
)
$ErrorActionPreference = "Stop"

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  Write-Output $line
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 }
}

# 允许替换的厂商控制软件（按显示名匹配）
$asusRemovable   = 'ARMOURY CRATE|Armoury Crate|ROG Live Service|ASUS Framework Service|AURA lighting effect add-on|ASUS Smart Display Control|奥创'
$lenovoRemovable = 'Legion Zone|拯救者工具箱|Lenovo Legion Space|联想电脑管家|Lenovo PC Manager|Lenovo Vantage|Lenovo Hotkeys|System Interface Foundation|Lenovo Service Bridge'
# 必须保留（任何情况下不卸载，即使名字同时命中上面的规则）
$protected = 'System Control Interface|Energy Management|Gaming Feature Driver|Driver|驱动|Chipset|Firmware|BIOS|Audio|Realtek|Intel|AMD|NVIDIA|Dolby|Wireless|Bluetooth|Smart Gesture|Precision Touchpad|MyASUS|ASUS Optimization|Lenovo System Update|Lenovo Commercial Vantage'
# 可移除的 Appx（应用商店版）
$appxRemovable = 'LenovoCompanion|LenovoVantage|LenovoUtility|LegionZone|ArmouryCrate'

$links = [ordered]@{
  "G-Helper 官方下载"                 = "https://github.com/seerge/g-helper/releases/latest"
  "ASUS System Control Interface V3"  = "https://dlcdnets.asus.com/pub/ASUS/nb/Image/CustomComponent/ASUSSystemControlInterfaceV3/ASUSSystemControlInterfaceV3.exe"
  "Armoury Crate Uninstall Tool"      = "https://dlcdnets.asus.com/pub/ASUS/mb/14Utilities/Armoury_Crate_Uninstall_Tool.zip"
  "Lenovo Legion Toolkit 官方下载"     = "https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/releases/latest"
  "联想 System Interface Foundation 卸载说明" = "https://support.lenovo.com/us/en/solutions/HT506070"
}

function Get-Brand {
  $cs = Get-CimInstance Win32_ComputerSystem
  $m = "$($cs.Manufacturer) $($cs.Model)"
  if ($m -match 'ASUS') { return "ASUS" }
  if ($m -match 'LENOVO') { return "Lenovo" }
  return "Other"
}

function Get-InstalledApps {
  $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
  Get-ItemProperty $roots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    Select-Object DisplayName, DisplayVersion, Publisher, UninstallString, QuietUninstallString, PSPath
}

function Get-Candidates($brand) {
  $list = New-Object System.Collections.ArrayList
  $pattern = if ($brand -eq "ASUS") { $asusRemovable } elseif ($brand -eq "Lenovo") { $lenovoRemovable } else { $null }
  if (-not $pattern) { return @() }
  $i = 0
  foreach ($a in (Get-InstalledApps | Sort-Object DisplayName -Unique)) {
    if ($a.DisplayName -match $pattern -and $a.DisplayName -notmatch $protected) {
      $i++
      [void]$list.Add([pscustomobject]@{ Id = ("{0}{1}" -f $brand.Substring(0,1), $i); Kind = "Win32"; Name = $a.DisplayName; Version = $a.DisplayVersion; Publisher = $a.Publisher; Uninstall = $a.UninstallString })
    }
  }
  foreach ($p in (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $appxRemovable })) {
    $i++
    [void]$list.Add([pscustomobject]@{ Id = ("{0}{1}" -f $brand.Substring(0,1), $i); Kind = "Appx"; Name = $p.Name; Version = "$($p.Version)"; Publisher = $p.Publisher; Uninstall = $p.PackageFullName })
  }
  return $list
}

function Show-Scan {
  $brand = Get-Brand
  $cs = Get-CimInstance Win32_ComputerSystem
  "=== 厂商控制软件扫描 ==="
  "机型          : $($cs.Manufacturer) $($cs.Model)"
  "品牌判定      : $brand"
  $apps = Get-InstalledApps
  $procs = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique
  if ($brand -eq "ASUS") {
    $gh = $procs | Where-Object { $_ -match '^GHelper$' }
    $sci = $apps | Where-Object { $_.DisplayName -match 'System Control Interface' }
    $sciDrv = Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%System Control Interface%'" -ErrorAction SilentlyContinue
    "G-Helper      : " + $(if ($gh) { "正在运行" } else { "未运行（G-Helper 是单个 exe，免安装）" })
    "ASUS System Control Interface: " + $(if ($sci -or $sciDrv) { "已安装（G-Helper 必需，保留）" } else { "未找到！G-Helper 需要它，先从华硕官网安装" })
    "奥创相关进程  : " + (($procs | Where-Object { $_ -match 'Armoury|ArmourySocket|ROGLive|AsusCertService|LightingService' }) -join ', ')
    "卸载方式      : 只用华硕官方 Armoury Crate Uninstall Tool（会一并清理奥创服务和组件）"
  } elseif ($brand -eq "Lenovo") {
    $llt = $apps | Where-Object { $_.DisplayName -match 'Lenovo Legion Toolkit' }
    $em = $apps | Where-Object { $_.DisplayName -match 'Energy Management' }
    $gfd = Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%Gaming Feature%'" -ErrorAction SilentlyContinue
    "Lenovo Legion Toolkit: " + $(if ($llt) { "已安装 $($llt[0].DisplayVersion)" } else { "未安装" })
    "Lenovo Energy Management: " + $(if ($em) { "已安装（LLT 在 Gen 10 之前的机型上需要，保留）" } else { "未找到（Gen 10 及更新机型不需要）" })
    "Vantage Gaming Feature Driver: " + $(if ($gfd) { "已安装（保留）" } else { "未找到（Gen 10 及更新机型不需要）" })
    "联想相关进程  : " + (($procs | Where-Object { $_ -match 'Vantage|ImController|LegionZone|LenovoPcManager|LenovoTray|LegionSpace' }) -join ', ')
    "推荐方式      : 先在 LLT 设置里用「禁用 Vantage / Legion Zone / Hotkeys」（可随时恢复），确有需要再卸载"
  } else {
    "不是华硕或联想机器，本流程不适用"
    return
  }
  "--- 可替换的厂商控制软件（卸载时用 Id；华硕的奥创组件只能走官方卸载工具）---"
  $c = Get-Candidates $brand
  if (-not $c -or $c.Count -eq 0) { "（没有检测到）" } else { $c | Format-Table Id, Kind, Name, Version, Publisher -AutoSize | Out-String -Width 200 }
  "--- 官方下载/说明 ---"
  foreach ($k in $links.Keys) { "{0}: {1}" -f $k, $links[$k] }
}

function Check-File($path) {
  if (-not (Test-Path -LiteralPath $path)) { throw "找不到文件: $path" }
  $sig = Get-AuthenticodeSignature -LiteralPath $path
  $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  "文件     : $path"
  "SHA256   : $hash"
  "签名状态 : $($sig.Status)"
  "签名者   : $($sig.SignerCertificate.Subject)"
  if ($sig.Status -ne 'Valid') { "结论     : 签名无效或没有签名，不要运行，请从官方地址重新下载"; return }
  "结论     : 签名有效。请核对签名者：G-Helper 应为 SignPath Foundation；奥创卸载工具应为 ASUSTeK；LLT 为项目证书（安装包和程序都签名）"
}

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { Log "[停止] 需要管理员权限"; exit 1 }
}

function New-Backup($brand) {
  $dir = Join-Path ([Environment]::GetFolderPath("Desktop")) ("OEMSwitch_Backup_" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  New-Item -ItemType Directory -Path $dir | Out-Null
  Get-InstalledApps | Sort-Object DisplayName | Format-Table DisplayName, DisplayVersion, Publisher -AutoSize | Out-String -Width 300 | Out-File (Join-Path $dir "installed_apps.txt") -Encoding UTF8
  Get-Service | Where-Object { $_.DisplayName -match 'ASUS|Armoury|ROG|Lenovo|Legion|联想|ImController' } | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize | Out-String -Width 300 | Out-File (Join-Path $dir "oem_services.txt") -Encoding UTF8
  $restore = @"
# 如何恢复厂商软件
- 华硕奥创：从华硕官网本机型支持页或 Microsoft Store 重新安装 Armoury Crate（G-Helper 作者说明：卸载后随时可以装回）。装回前先退出 G-Helper。
- 联想 Legion Zone / 联想电脑管家：从联想官网本机型驱动页或联想应用商店重新安装。
- Lenovo Vantage：Microsoft Store 搜索 Lenovo Vantage 安装。装回前先在 LLT 里恢复或退出 LLT。
- 卸载前的软件清单：installed_apps.txt；厂商服务状态：oem_services.txt。
"@
  [System.IO.File]::WriteAllText((Join-Path $dir "restore.md"), $restore, (New-Object System.Text.UTF8Encoding($true)))
  try { Checkpoint-Computer -Description "Before OEM software switch" -RestorePointType APPLICATION_UNINSTALL -ErrorAction Stop; Log "已创建系统还原点" }
  catch { Log "[提示] 还原点未创建: $($_.Exception.Message)" }
  Log "备份目录: $dir"
  return $dir
}

try {
  switch ($Mode) {
    "Scan" { Show-Scan }
    "CheckFile" { Check-File $File }
    "RunAsusTool" {
      Assert-Admin
      if ((Get-Brand) -ne "ASUS") { Log "[停止] 不是华硕机器"; exit 1 }
      $sig = Get-AuthenticodeSignature -LiteralPath $File
      if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'ASUSTeK') { Log "[停止] 卸载工具签名不是有效的 ASUSTeK 签名: $($sig.Status) $($sig.SignerCertificate.Subject)"; exit 1 }
      [void](New-Backup "ASUS")
      Log "启动华硕官方 Armoury Crate Uninstall Tool，请在弹出的窗口里按提示完成卸载"
      $p = Start-Process -FilePath $File -Wait -PassThru
      Log "卸载工具已退出，退出码 $($p.ExitCode)。请按工具提示重启，重启后再运行本脚本扫描确认"
    }
    "Uninstall" {
      Assert-Admin
      $brand = Get-Brand
      if ($brand -notin "ASUS", "Lenovo") { Log "[停止] 不是华硕或联想机器"; exit 1 }
      $want = @($Ids -split '[,\s]+' | Where-Object { $_ })
      if ($want.Count -eq 0) { Log "[停止] 没有指定 -Ids"; exit 1 }
      $cands = Get-Candidates $brand
      $sel = @($cands | Where-Object { $want -contains $_.Id })
      $missing = @($want | Where-Object { $cands.Id -notcontains $_ })
      if ($missing.Count -gt 0) { Log "[停止] 这些 Id 不在扫描结果里: $($missing -join ', ')。请重新扫描"; exit 1 }
      if ($brand -eq "ASUS" -and ($sel | Where-Object { $_.Name -match 'Armoury|ARMOURY|奥创|ROG Live|Framework Service|AURA' })) {
        Log "[停止] 奥创及其组件请用 -Mode RunAsusTool 走华硕官方卸载工具，不逐个卸载"; exit 1
      }
      [void](New-Backup $brand)
      foreach ($c in $sel) {
        if ($c.Name -match $protected) { Log "[跳过] $($c.Name) 属于必须保留的组件"; continue }
        Log "卸载: $($c.Name) $($c.Version)"
        if ($c.Kind -eq "Appx") {
          Remove-AppxPackage -Package $c.Uninstall
          Log "  已移除应用商店版 $($c.Name)"
          continue
        }
        $u = "$($c.Uninstall)".Trim()
        if (-not $u) { Log "  [跳过] 没有卸载命令，请到「设置 → 应用」手动卸载"; continue }
        if ($u -match '(?i)msiexec(\.exe)?\s+/[IX]\s*(\{[0-9A-F-]+\})') {
          $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($Matches[2])" -Wait -PassThru
        } elseif ($u -match '^"([^"]+)"\s*(.*)$') {
          $p = Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -Wait -PassThru
        } elseif ($u -match '^(\S+\.exe)\s*(.*)$') {
          $p = Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -Wait -PassThru
        } else { Log "  [跳过] 无法识别卸载命令: $u"; continue }
        Log "  卸载程序退出码 $($p.ExitCode)"
      }
      Log "完成。请重启，然后在 LLT 里确认没有「Vantage/Legion Zone 仍在运行」的提示；残留 ImController 进程见联想 HT506070 说明"
    }
  }
} catch {
  Log ("[停止] 异常: {0} (行 {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
  exit 1
}
