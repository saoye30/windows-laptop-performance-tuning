# Vendored read-only evidence subset

## Provenance and byte preservation

- Repository: https://github.com/Feng23-feng/pc-hardware-workbench
- Pinned commit: `dc5a46891f36b50028f04c492f1e08e94d17604b`.
- Source checkout: a clean Windows Git checkout with HEAD verified at the pinned commit.
- Runtime, asset and test source prefix: `skill/pc-hardware-workbench/`.
- [LICENSE](LICENSE) is copied from the **repository root**, not the skill directory: MIT, Copyright (c) 2026 Feng23-feng.
- The 19 upstream files listed in [upstream-manifest.json](upstream-manifest.json) are unmodified byte-for-byte copies of that local checkout. The manifest records relative destination, source path, byte length, SHA-256 and Git blob ID.
- Upstream Git attributes store normalized LF blobs but check out `*.ps1` and `*.cs` as CRLF. Checkout SHA-256 therefore describes the supplied source bytes, not raw commit-blob bytes. Each source file's attribute-normalized Git hash was separately checked against the pinned commit. No re-encoding, line-ending conversion or source patch was applied.
- This provenance note, the manifest and the [integration runner](../../tests/run-readonly-module-tests.ps1) are local additions, not upstream files. Hashes detect accidental changes; the manifest itself is not an independent signature or trust anchor.

## Runtime dependency closure

| File | Required by / purpose |
| --- | --- |
| [scripts/collect-windows.ps1](scripts/collect-windows.ps1) | Windows inventory entry point; not executed during integration |
| [scripts/device-identity.ps1](scripts/device-identity.ps1) | Collector identity assessment, formatting and redaction |
| [scripts/inventory-context.ps1](scripts/inventory-context.ps1) | Collector permission/context, battery, memory, monitor and GPU field interpretation |
| [scripts/local-path-safety.ps1](scripts/local-path-safety.ps1) | Shared local input/output path validation and non-overwriting output helper |
| [scripts/system-native.cs](scripts/system-native.cs) | Collector topology, firmware, memory and power status query fallbacks |
| [scripts/storage-native.cs](scripts/storage-native.cs) | Collector disk descriptor and volume mapping query fallbacks |
| [scripts/display-native.cs](scripts/display-native.cs) | Collector active-display, HDR and DXGI query fallbacks |
| [scripts/run-evidence-pipeline.ps1](scripts/run-evidence-pipeline.ps1) | Existing local baseline/candidate CSV evidence pipeline |
| [scripts/analyze-telemetry.ps1](scripts/analyze-telemetry.ps1) | Statistics and chart data; invoked by pipeline, normalizer and CSV renderer |
| [scripts/normalize-telemetry.ps1](scripts/normalize-telemetry.ps1) | Pipeline normalized telemetry and provenance output |
| [scripts/render-telemetry-chart.ps1](scripts/render-telemetry-chart.ps1) | Pipeline SVG charts; accepts normalized JSON or local CSV |
| [assets/evidence-card-template.html](assets/evidence-card-template.html) | Pipeline self-contained HTML evidence-card template |

Dependency paths were reviewed from both entry points and their helpers. Identity/context/path helpers have no further vendored dependencies. The native sources use Windows system APIs and framework types, not external packages. The analyzer loads the framework `Microsoft.VisualBasic` assembly. The pipeline and normalizer explicitly launch existing Windows `powershell.exe`; Windows PowerShell 5.1 and built-in .NET/framework assemblies are required. No dependency installer is included or invoked.

## Boundaries and exclusions

This is a **subset**, not a complete upstream Skill or drop-in distribution. No upstream Skill instructions, tuning guides, overclocking helpers, live LHM adapter, RAG/network tooling, doctor, hardware-case manager, portable launcher, installers, repository automation, full-repository validator, collector smoke test or run-all entry point is included.

“Read-only” means no system/hardware configuration changes, not zero file writes. The unchanged collector compiles the native query sources, may create then remove a temporary `powercfg /batteryreport` XML file, and writes a report only when requested. If `nvidia-smi` is already available it may read GPU identity, power limits and one instantaneous telemetry sample. It neither installs that tool nor changes its limits; it does not run a stress workload. Collection still requires a separate intentional invocation and may expose identifiers; review/redact reports before sharing. No live collector execution was performed for this integration.

The pipeline reads existing local files and creates a new evidence directory containing JSON, SVG, HTML and Markdown. Normalization may create temporary conversion files. It does not record live sensors, start a workload, modify the supplied CSV, tune hardware, or install software. The normalizer's upstream offline snapshot-JSON support is retained because upstream source bytes are preserved, but no live adapter is included. The upstream pipeline fixture's `Change` text is only a synthetic label, not a tuning action. Results are evidence, not proof of stability, safety or causation.

## Repeatable offline checks

Run from the containing skill root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-readonly-module-tests.ps1
```

The local runner checks all 19 upstream hashes and lengths, parses vendored PowerShell (including the collector without executing it), compiles the three C# helpers without invoking native probe methods, then runs only these six reviewed upstream suites in isolated Windows PowerShell processes:

- [tests/run-device-identity-tests.ps1](tests/run-device-identity-tests.ps1): in-memory identity/redaction/formatting fixtures.
- [tests/run-inventory-context-tests.ps1](tests/run-inventory-context-tests.ps1): in-memory context, inventory and unit/field fixtures.
- [tests/run-telemetry-analysis-tests.ps1](tests/run-telemetry-analysis-tests.ps1): synthetic CSV statistics, column mapping and windows.
- [tests/run-telemetry-normalization-tests.ps1](tests/run-telemetry-normalization-tests.ps1): synthetic local CSV/JSON normalization and rendering.
- [tests/run-telemetry-chart-tests.ps1](tests/run-telemetry-chart-tests.ps1): synthetic CSV chart data, downsampling, gaps and output formatting.
- [tests/run-evidence-pipeline-tests.ps1](tests/run-evidence-pipeline-tests.ps1): synthetic baseline/candidate comparison, baseline-only output, missing workload and disjoint metrics.

Fixtures/output are created beneath GUID-named temporary directories and cleaned by the upstream tests. No real device inventory, user telemetry, network access, software installation or performance workload is needed. Compilation checks do not establish runtime driver/API availability, and offline fixtures do not establish actual hardware compatibility. The tests validate this selected module closure, not the entire upstream repository or the host skill's tuning scripts.
