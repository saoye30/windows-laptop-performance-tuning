# tune_system.ps1 - 配置电源模式后的系统性能项（L2，需管理员，用户确认后运行）
# 内容: NVIDIA 全局 3D 设置 / Windows 搜索 / Windows 更新暂停 / 浏览器自启与硬件加速 / Steam 硬件加速与着色器缓存
# 用法:
#   预演: powershell -NoProfile -ExecutionPolicy Bypass -File tune_system.ps1 -DryRun
#   执行: Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<本文件>" -BackupDir "<备份目录>" -CloseSteam -LogPath "C:\Users\Public\tune_log.txt"'
#   撤销: ... -Mode Undo -BackupDir "<备份目录>"
# 参数:
#   -Only        只做其中几项，逗号分隔: Nvidia,Search,Update,Browser,Steam（默认全部）
#   -CloseSteam  Steam 正在运行时先用 steam.exe -shutdown 正常退出（Steam 退出时会覆盖配置，必须先退出）
#   -BackupDir   备份目录；不传则在桌面新建 SystemTune_Backup_<时间>
# 每一项改动前都记录原值到 tune_state.json，Undo 按原样恢复（原来不存在的值会删除）。无 pause、无交互。
param(
  [ValidateSet("Apply", "Undo")]
  [string]$Mode = "Apply",
  [string]$Only = "Nvidia,Search,Update,Browser,Steam",
  [string]$BackupDir = "",
  [switch]$CloseSteam,
  [switch]$DryRun,
  [string]$LogPath = ""
)
$ErrorActionPreference = "Stop"
$parts = @($Only -split '[,\s]+' | Where-Object { $_ })
function Want($name) { return $parts -contains $name }

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  Write-Output $line
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 }
}

$state = New-Object System.Collections.ArrayList
function Save-State { if (-not $DryRun) { $state | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $BackupDir "tune_state.json") -Encoding UTF8 } }

# ---------- 注册表 ----------
function Get-RegRecord($path, $name) {
  $rec = [ordered]@{ Kind = "Reg"; Path = $path; Name = $name; Exists = $false; Type = $null; Value = $null }
  if (Test-Path -LiteralPath $path) {
    $key = Get-Item -LiteralPath $path
    if ($key.GetValueNames() -contains $name) {
      $rec.Exists = $true
      $rec.Type = "$($key.GetValueKind($name))"
      $rec.Value = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
    }
  }
  return $rec
}
function Set-Reg($path, $name, $type, $value, $label) {
  $old = Get-RegRecord $path $name
  $oldText = if ($old.Exists) { "$($old.Value)" } else { "（无）" }
  if ($old.Exists -and "$($old.Value)" -eq "$value") { Log "  [不变] $label 已是 $value"; return }
  if ($DryRun) { Log "  [预演] $label：$oldText -> $value"; return }
  [void]$state.Add($old); Save-State
  if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -LiteralPath $path -Name $name -PropertyType $type -Value $value -Force | Out-Null
  Log "  [完成] $label：$oldText -> $value"
}
function Remove-Reg($path, $name, $label) {
  $old = Get-RegRecord $path $name
  if (-not $old.Exists) { return }
  if ($DryRun) { Log "  [预演] 删除 $label（$($old.Value)）"; return }
  [void]$state.Add($old); Save-State
  Remove-ItemProperty -LiteralPath $path -Name $name -Force
  Log "  [完成] 已删除 $label"
}

# ---------- 撤销 ----------
if ($Mode -eq "Undo") {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { Log "[停止] 需要管理员权限"; exit 1 }
  $f = Join-Path $BackupDir "tune_state.json"
  if (-not (Test-Path -LiteralPath $f)) { Log "[停止] 找不到 $f"; exit 1 }
  $items = @(Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json)
  [array]::Reverse($items)
  foreach ($r in $items) {
    try {
      switch ($r.Kind) {
        "Reg" {
          if ($r.Exists) {
            if (-not (Test-Path -LiteralPath $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            $v = $r.Value; if ($r.Type -eq "MultiString") { $v = [string[]]$r.Value }
            New-ItemProperty -LiteralPath $r.Path -Name $r.Name -PropertyType $r.Type -Value $v -Force | Out-Null
          } else { Remove-ItemProperty -LiteralPath $r.Path -Name $r.Name -Force -ErrorAction SilentlyContinue }
          Log "已恢复 $($r.Path)\$($r.Name)"
        }
        "Service" { Set-Service -Name $r.Name -StartupType $r.StartType; if ($r.Status -eq "Running") { Start-Service -Name $r.Name }; Log "已恢复服务 $($r.Name)：$($r.StartType)" }
        "File" { Copy-Item -LiteralPath $r.Backup -Destination $r.Path -Force; Log "已恢复文件 $($r.Path)" }
        "Nvidia" {
          Add-Type -Path (Join-Path $PSScriptRoot "NvDrs.cs")
          [NvDrs]::Open()
          try {
            if ($null -eq $r.Value) { [NvDrs]::RestoreDefault([uint32]$r.Id) } else { [NvDrs]::Set([uint32]$r.Id, [uint32]$r.Value) }
            [NvDrs]::Save()
          } finally { [NvDrs]::Close() }
          Log "已恢复 NVIDIA 设置 $($r.Label)"
        }
      }
    } catch { Log "[失败] 恢复 $($r.Kind) $($r.Name)$($r.Label): $($_.Exception.Message)" }
  }
  Log "撤销完成。Steam、浏览器重新打开后生效；NVIDIA 设置可在控制面板确认"
  exit 0
}

# ---------- 执行 ----------
try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin -and -not $DryRun) { Log "[停止] 需要管理员权限"; exit 1 }
  if (-not $BackupDir) { $BackupDir = Join-Path ([Environment]::GetFolderPath("Desktop")) ("SystemTune_Backup_" + (Get-Date -Format "yyyyMMdd-HHmmss")) }
  if (-not $DryRun) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $old = Join-Path $BackupDir "tune_state.json"
    if (Test-Path -LiteralPath $old) { $state.AddRange(@(Get-Content -LiteralPath $old -Raw -Encoding UTF8 | ConvertFrom-Json)) }
  }
  Log "=== 系统性能项 $(if($DryRun){'(预演)'}) 备份目录: $BackupDir ==="

  # 1. NVIDIA 全局 3D 设置
  if (Want "Nvidia") {
    Log "[NVIDIA]"
    if (-not (Test-Path "$env:windir\System32\nvapi64.dll")) { Log "  [跳过] 没有 NVIDIA 驱动" }
    else {
      Add-Type -Path (Join-Path $PSScriptRoot "NvDrs.cs")
      [NvDrs]::Open()
      try {
        # ID 与取值来自 NVIDIA 官方 NvApiDriverSettings.h
        $nv = @(
          @{ Id = 0x1057EB71; Value = 1; Label = "电源管理模式 = 最高性能优先（PREFERRED_PSTATE_PREFER_MAX）" },
          @{ Id = 0x00198FFF; Value = 0; Label = "着色器缓存 = 关闭（PS_SHADERDISKCACHE_OFF）" },
          @{ Id = 0x00AC8497; Value = 0; Label = "着色器缓存大小 = 0（禁用）" }
        )
        $changed = $false
        foreach ($n in $nv) {
          $cur = [NvDrs]::Get([uint32]$n.Id)
          $curText = if ($null -eq $cur) { "驱动默认" } else { "$cur" }
          if ($cur -eq $n.Value) { Log "  [不变] $($n.Label)"; continue }
          if ($DryRun) { Log "  [预演] $($n.Label)：当前 $curText"; continue }
          [void]$state.Add([ordered]@{ Kind = "Nvidia"; Id = $n.Id; Value = $cur; Label = $n.Label }); Save-State
          [NvDrs]::Set([uint32]$n.Id, [uint32]$n.Value); $changed = $true
          Log "  [完成] $($n.Label)：$curText -> $($n.Value)"
        }
        if ($changed) { [NvDrs]::Save() }
      } finally { [NvDrs]::Close() }
    }
  }

  # 2. Windows 搜索
  if (Want "Search") {
    Log "[Windows 搜索]"
    $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
    if (-not $svc) { Log "  [跳过] 没有 WSearch 服务" }
    elseif ($svc.StartType -eq "Disabled" -and $svc.Status -ne "Running") { Log "  [不变] 索引服务 WSearch 已停用" }
    elseif ($DryRun) { Log "  [预演] 停止并禁用索引服务 WSearch（当前 $($svc.Status)/$($svc.StartType)）" }
    else {
      [void]$state.Add([ordered]@{ Kind = "Service"; Name = "WSearch"; StartType = "$($svc.StartType)"; Status = "$($svc.Status)" }); Save-State
      Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue
      Set-Service -Name WSearch -StartupType Disabled
      Log "  [完成] 已停止并禁用索引服务 WSearch"
    }
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' DWord 1 "开始菜单搜索不联网（关闭必应建议）"
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' DWord 0 "关闭必应网页搜索"
  }

  # 3. Windows 更新暂停到 2099-12-31
  if (Want "Update") {
    Log "[Windows 更新]"
    $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $end = [datetime]::new(2099, 12, 31, 0, 0, 0, [DateTimeKind]::Utc)
    $now = [datetime]::UtcNow
    $days = [int][math]::Ceiling(($end - $now).TotalDays) + 1
    $s = $now.ToString("yyyy-MM-ddTHH:mm:ssZ"); $e = $end.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $curMax = (Get-RegRecord $ux 'FlightSettingsMaxPauseDays').Value
    if ($null -eq $curMax -or [int]$curMax -lt $days) { Set-Reg $ux 'FlightSettingsMaxPauseDays' DWord $days "允许的最长暂停天数" }
    else { Log "  [不变] 允许的最长暂停天数 $curMax" }
    $curEnd = (Get-RegRecord $ux 'PauseUpdatesExpiryTime').Value
    if ($curEnd -eq $e) { Log "  [不变] 已暂停到 $e" }
    else {
      foreach ($n in 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesStartTime') { Set-Reg $ux $n String $s $n }
      foreach ($n in 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesExpiryTime') { Set-Reg $ux $n String $e $n }
    }
  }

  # 4. 浏览器: 自启 / 后台运行 / 硬件加速（企业策略，浏览器里会显示「由你的组织管理」）
  if (Want "Browser") {
    Log "[浏览器]"
    $chromium = @(
      @{ Name = "Edge";   Exe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; Policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Extra = @{ StartupBoostEnabled = 0 } },
      @{ Name = "Chrome"; Exe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe";        Policy = 'HKLM:\SOFTWARE\Policies\Google\Chrome'; Extra = @{} },
      @{ Name = "Brave";  Exe = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"; Policy = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'; Extra = @{} }
    )
    foreach ($b in $chromium) {
      if (-not (Test-Path -LiteralPath $b.Exe)) { continue }
      Set-Reg $b.Policy 'BackgroundModeEnabled' DWord 0 "$($b.Name) 关闭后不在后台运行"
      Set-Reg $b.Policy 'HardwareAccelerationModeEnabled' DWord 0 "$($b.Name) 关闭硬件加速"
      foreach ($k in $b.Extra.Keys) { Set-Reg $b.Policy $k DWord $b.Extra[$k] "$($b.Name) 关闭启动加速（开机预加载）" }
    }
    if (Test-Path -LiteralPath "$env:ProgramFiles\Mozilla Firefox\firefox.exe") {
      Set-Reg 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' 'HardwareAcceleration' DWord 0 "Firefox 关闭硬件加速"
    }
    # 开机自启项（只删浏览器的）
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Path -LiteralPath $run) {
      $key = Get-Item -LiteralPath $run
      foreach ($n in $key.GetValueNames()) {
        $v = "$($key.GetValue($n))"
        if ($n -match '^MicrosoftEdgeAutoLaunch' -or $v -match '(?i)\\(msedge|chrome|brave|firefox|opera|vivaldi)\.exe') { Remove-Reg $run $n "开机自启 $n" }
      }
    }
  }

  # 5. Steam: 硬件视频解码 / 网页视图 GPU 加速 / 着色器预缓存
  if (Want "Steam") {
    Log "[Steam]"
    $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $sp) { Log "  [跳过] 没有安装 Steam" }
    else {
      $sp = $sp -replace '/', '\'
      $running = Get-Process -Name steam -ErrorAction SilentlyContinue
      if ($running -and -not $DryRun) {
        if (-not $CloseSteam) { Log "  [跳过] Steam 正在运行，退出时会覆盖设置。请先退出 Steam，或加 -CloseSteam" ; $sp = $null }
        else {
          Start-Process -FilePath (Join-Path $sp "steam.exe") -ArgumentList "-shutdown"
          $t = 0; while ((Get-Process -Name steam -ErrorAction SilentlyContinue) -and $t -lt 60) { Start-Sleep -Seconds 2; $t += 2 }
          if (Get-Process -Name steam -ErrorAction SilentlyContinue) { Log "  [跳过] Steam 60 秒内没有退出"; $sp = $null } else { Log "  Steam 已正常退出" }
        }
      }
      if ($sp) {
        Set-Reg 'HKCU:\Software\Valve\Steam' 'GPUAccelWebViewsV3' DWord 0 "Steam 网页视图 GPU 加速渲染"
        Set-Reg 'HKCU:\Software\Valve\Steam' 'H264HWAccel' DWord 0 "Steam 硬件视频解码"
        # 着色器预缓存在 config.vdf 的 ShaderCacheManager 块里（键名取自 steamclient64.dll）
        $cfg = Join-Path $sp "config\config.vdf"
        if (-not (Test-Path -LiteralPath $cfg)) { Log "  [跳过] 找不到 $cfg" }
        else {
          $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $cfg -Encoding UTF8)
          $i = $lines.FindIndex([Predicate[string]]{ param($l) $l.Trim() -eq '"ShaderCacheManager"' })
          if ($i -lt 0 -or $lines[$i + 1].Trim() -ne '{') { Log "  [跳过] config.vdf 里没有 ShaderCacheManager 块，请在 Steam 设置里手动关闭着色器预缓存" }
          else {
            $indent = ($lines[$i] -replace '[^\t].*$', '') + "`t"
            $want = [ordered]@{ DisableShaderCache = "1"; EnableShaderBackgroundProcessing = "0" }
            $plan = @()
            foreach ($k in $want.Keys) {
              $j = $i + 2; $found = -1; $depth = 0
              while ($j -lt $lines.Count) {
                $tl = $lines[$j].Trim()
                if ($tl -eq '{') { $depth++ } elseif ($tl -eq '}') { if ($depth -eq 0) { break } else { $depth-- } }
                elseif ($depth -eq 0 -and $tl -match ('^"' + $k + '"\s')) { $found = $j; break }
                $j++
              }
              $plan += @{ Key = $k; Line = $found; Value = $want[$k] }
            }
            $todo = @($plan | Where-Object { $_.Line -lt 0 -or $lines[$_.Line] -notmatch ('"' + $_.Value + '"\s*$') })
            if ($todo.Count -eq 0) { Log "  [不变] 着色器预缓存已关闭" }
            elseif ($DryRun) { Log "  [预演] config.vdf：DisableShaderCache=1，EnableShaderBackgroundProcessing=0（关闭着色器预缓存和后台处理）" }
            else {
              $bak = Join-Path $BackupDir "steam_config.vdf"
              Copy-Item -LiteralPath $cfg -Destination $bak -Force
              [void]$state.Add([ordered]@{ Kind = "File"; Path = $cfg; Backup = $bak }); Save-State
              foreach ($p in ($todo | Sort-Object { $_.Line } -Descending)) {
                $text = $indent + '"' + $p.Key + '"' + "`t`t" + '"' + $p.Value + '"'
                if ($p.Line -ge 0) { $lines[$p.Line] = $text } else { $lines.Insert($i + 2, $text) }
              }
              [System.IO.File]::WriteAllLines($cfg, $lines, (New-Object System.Text.UTF8Encoding($false)))
              Log "  [完成] 已关闭着色器预缓存和 Vulkan 着色器后台处理（config.vdf 原文件已备份）"
            }
          }
        }
      }
    }
  }

  if ($DryRun) { Log "=== 预演结束，未做任何修改 ===" }
  else {
    Log "=== 完成。撤销: 以管理员运行 tune_system.ps1 -Mode Undo -BackupDir `"$BackupDir`" ==="
    Log "浏览器需重启生效；Steam 下次启动后请在「设置」里确认硬件加速和着色器预缓存已关闭"
  }
} catch {
  Log ("[停止] 异常: {0} (行 {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
  exit 1
}
