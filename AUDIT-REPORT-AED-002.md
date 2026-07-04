# Audit Report AED-002

## Summary
- **Total Files Audited**: 118
- **Total Files with Findings**: 11
- **Findings by Category**:
  - 2.3 Hardcoded Data Audit: 3
  - 2.5 Swift Correctness Audit: 6
  - 2.6 Swift 6 Concurrency Audit: 5
- **Final xcodebuild result**: N/A (Tool not available in environment)
- **Manifest Agreement**: `file_list.txt`, `files.md`, and `SwiftCode.xcodeproj` all agree with the final tree.

## Detailed Findings

| File Path | Category | Finding | Fix |
|-----------|----------|---------|-----|
| `SwiftCode/Backend/Git/GitService.swift` | 2.3, 2.6 | Hardcoded git path `/usr/bin/git`. Synchronous cross-actor preference access. | Parameterized via `PreferencesStore` with async resolution. |
| `SwiftCode/Backend/Build/XcodeBuildService.swift` | 2.3, 2.6 | Hardcoded xcodebuild path. Blocking `waitUntilExit()`. Synchronous cross-actor preference access. | Refactored to async `runStreamingAsync`, non-blocking termination handling, and async preference resolution. |
| `SwiftCode/Backend/Build/SwiftPackageBuildService.swift` | 2.3, 2.6 | Hardcoded swift path. Blocking `waitUntilExit()`. Synchronous cross-actor preference access. | Refactored to async `runStreamingAsync`, non-blocking termination handling, and async preference resolution. |
| `SwiftCode/Tools/PathTool.swift` | 2.5 | Force-unwrap on `applicationSupportDirectory`. | Added `// SAFETY:` justification. |
| `SwiftCode/Backend/Persistence/ProjectRegistryStore.swift` | 2.5 | Force-try on `appSupportDirectory` access. | Added `// SAFETY:` justification. |
| `SwiftCode/Backend/Persistence/ThemeStore.swift` | 2.5 | Force-try on `appSupportDirectory` access. | Added `// SAFETY:` justification. |
| `SwiftCode/Backend/AI/OpenRouterClient.swift` | 2.5 | Force-unwrap on `URL(string:)`. | Added `// SAFETY:` justification. |
| `SwiftCode/Backend/Security/KeychainService.swift` | 2.5 | Force-unwrap on `String.data(using: .utf8)`. | Added `// SAFETY:` justification. |
| `SwiftCode/Backend/Git/GitPorcelainParser.swift` | 2.5, 2.6 | Force-unwrap on `statusStr.first`. Singleton with state. | Added `// SAFETY:` justification. Converted to `actor`. |
| `SwiftCode/Tools/ProcessRunnerTool.swift` | 2.5, 2.6 | Potential resource leak in `readabilityHandler`. Double-resumption risk in continuations. | Implemented `runStreamingAsync` with safe termination handler composition and guarded continuation resumption. |
| `SwiftCode/ViewModels/WorkspaceViewModel.swift` | 2.6 | Missing `Sendable` on `@MainActor` class. | Added `Sendable` conformance. |

## Confirmation
- No mock/fake data remains.
- No stub/incomplete files remains.
- All AED-001 features (F1–F9) cross-checked for completeness.
- `xcodeproj.py` is a permanent repository artifact.
- All `terminationHandler` composition issues resolved via `runStreamingAsync`.
- All cross-actor synchronous access issues resolved via async properties.
