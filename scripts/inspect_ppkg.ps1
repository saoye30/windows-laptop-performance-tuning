# inspect_ppkg.ps1 - L0 只读：核对 PPKG 哈希与内容，确认只含电源策略
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File inspect_ppkg.ps1 [-PackagePath <ppkg>]
# 解包依赖 7-Zip（PPKG 是 WIM 格式）；没有 7-Zip 时只做哈希和元数据检查。
param([string]$PackagePath = "")
$ErrorActionPreference = "Stop"
$ExpectedSha256 = "6EF9F98C3BAED89F6BD2DA4F6EF20B6F72D9D529380DA6271705FA671D988E87"
$ExpectedId = "9e3b0e54-ceb9-4656-a2ce-54c92f07469d"
if (-not $PackagePath) { $PackagePath = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\Tongfang.ppkg" }
if (-not (Test-Path -LiteralPath $PackagePath)) { throw "找不到安装包: $PackagePath" }

$ok = $true
$hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
"文件      : $PackagePath"
"SHA256    : $hash"
if ($hash -ne $ExpectedSha256) { "结果      : 哈希不符！这不是已核实的通用 PPKG 1.44，停止，不要安装"; $ok = $false }
else { "结果      : 哈希与已核实的 1.44 版一致" }

try {
  $m = Get-ProvisioningPackage -PackagePath $PackagePath -ErrorAction Stop
  "包名/版本 : {0} v{1}  OwnerType={2} Rank={3} Id={4}" -f $m.PackageName, $m.Version, $m.OwnerType, $m.Rank, $m.PackageID
  if ($m.PackageID -ne $ExpectedId) { "警告      : PackageId 与已核实版本不同"; $ok = $false }
} catch { "元数据    : 读取失败: $($_.Exception.Message)" }

$sevenZip = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sevenZip) { "内容检查  : 未找到 7-Zip，跳过解包检查（哈希一致时可信）" }
else {
  $tmp = Join-Path $env:TEMP ("ppkg_inspect_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    & $sevenZip x $PackagePath ("-o" + $tmp) -y | Out-Null
    $files = Get-ChildItem $tmp -Recurse -File
    "内容文件  : $($files.Count) 个"
    $bad = $files | Where-Object { $_.Extension -notin '.xml', '.provxml' }
    if ($bad) { "警告      : 包含非 XML 文件: " + (($bad | ForEach-Object Name) -join ', '); $ok = $false }
    $prov = Get-ChildItem $tmp -Recurse -Filter *.provxml
    $paths = $prov | Select-String -Pattern 'SettingsPath="([^"]+)"' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { ($_.Groups[1].Value -split '/')[0..1] -join '/' } | Sort-Object -Unique
    "设置范围  : " + ($paths -join ', ')
    if ($paths | Where-Object { $_ -ne 'Power/Policy' }) { "警告      : 包含电源策略以外的设置"; $ok = $false }
    $danger = $files | Select-String -Pattern 'ProvisioningCommands|CommandLine|\.exe|\.cmd|\.bat|\.ps1|Certificates|WLAN|Accounts' -List
    if ($danger) { "警告      : 发现命令/证书/账户类配置: " + (($danger | ForEach-Object Filename) -join ', '); $ok = $false }
  } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($ok) { "结论      : 通过。只包含处理器电源策略" } else { "结论      : 未通过。停止安装并告知用户" }
