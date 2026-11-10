[CmdletBinding()]
param()

# Local integration runner. Only synthetic fixtures and compile/parse checks.
# Never invokes collect-windows, hardware probes, installers, or live workloads.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vendor = Join-Path $root 'vendor/pc-hardware-workbench'
$scripts = Join-Path $vendor 'scripts'
$tests = Join-Path $vendor 'tests'
$windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source

$manifest = Get-Content -Raw -LiteralPath (Join-Path $vendor 'upstream-manifest.json') -Encoding UTF8 | ConvertFrom-Json
if ($manifest.commit -ne 'dc5a46891f36b50028f04c492f1e08e94d17604b' -or @($manifest.files).Count -ne 19) {
    throw 'Unexpected upstream provenance manifest.'
}
foreach ($entry in $manifest.files) {
    $file = Join-Path $vendor $entry.path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing vendored dependency: $($entry.path)" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw "Upstream bytes changed: $($entry.path)"
    }
    if ((Get-Item -LiteralPath $file).Length -ne $entry.bytes) { throw "Length mismatch: $($entry.path)" }
}
Write-Host 'Pinned upstream checkout integrity: PASS (19 files)'

# Parsing is not execution: collector is deliberately included only here.
$psFiles = @(Get-ChildItem -LiteralPath $scripts -File -Filter '*.ps1') +
    @(Get-ChildItem -LiteralPath $tests -File -Filter '*.ps1') + @(Get-Item -LiteralPath $PSCommandPath)
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "Syntax errors in $($file.Name): $($errors -join '; ')" }
}
Write-Host "PowerShell syntax: PASS ($($psFiles.Count) files; collector not executed)"

# Compile the three standalone source dependencies together. Do not call Read()
# or any other native method; this validates compilation, not hardware support.
if (-not ('CodexActiveDisplayReader' -as [type])) {
    Add-Type -Path @(
        (Join-Path $scripts 'system-native.cs'),
        (Join-Path $scripts 'storage-native.cs'),
        (Join-Path $scripts 'display-native.cs')
    ) -ErrorAction Stop
}
Write-Host 'Native helper compile only: PASS (no probe methods invoked)'

$cases = @(
    @{ Name = 'device-identity'; File = 'run-device-identity-tests.ps1'; Arguments = @('-HelperPath', (Join-Path $scripts 'device-identity.ps1')) },
    @{ Name = 'inventory-context'; File = 'run-inventory-context-tests.ps1'; Arguments = @('-HelperPath', (Join-Path $scripts 'inventory-context.ps1')) },
    @{ Name = 'analysis'; File = 'run-telemetry-analysis-tests.ps1'; Arguments = @('-AnalyzerPath', (Join-Path $scripts 'analyze-telemetry.ps1')) },
    @{ Name = 'normalization'; File = 'run-telemetry-normalization-tests.ps1'; Arguments = @('-AdapterPath', (Join-Path $scripts 'normalize-telemetry.ps1'), '-RendererPath', (Join-Path $scripts 'render-telemetry-chart.ps1')) },
    @{ Name = 'chart'; File = 'run-telemetry-chart-tests.ps1'; Arguments = @('-AnalyzerPath', (Join-Path $scripts 'analyze-telemetry.ps1'), '-RendererPath', (Join-Path $scripts 'render-telemetry-chart.ps1')) },
    @{ Name = 'pipeline'; File = 'run-evidence-pipeline-tests.ps1'; Arguments = @('-PipelinePath', (Join-Path $scripts 'run-evidence-pipeline.ps1')) }
)
foreach ($case in $cases) {
    Write-Host "Running offline fixture suite: $($case.Name)"
    $arguments = $case.Arguments
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tests $case.File) @arguments
    if ($LASTEXITCODE -ne 0) { throw "Offline suite $($case.Name) failed with exit code $LASTEXITCODE" }
}
Write-Host 'Read-only module integration: PASS (6 offline suites; no live collection or stress test)'
