# SwiftCode-Mac — Migration Tracker

**Generated**: 2026-11-07  
**Status**: COMPLETE (Phase 1, Phase 2, Phase 3 Verified)  
**Destination**: `swiftcode/`  
**Reference Source**: `SwiftCode-Legacy/`  

---

## 1. Executive Summary

This tracker documents the complete feature migration, architectural integration, and production hardening from `SwiftCode-Legacy` into `SwiftCode-Mac`. All 17 mandatory legacy features, 291 Assist tools, 33 System Training Assets, 13 AI provider backends, Version 2 Roadmap capabilities, and the Centralized Tools Drawer have been migrated with 100% real implementations, zero fake/mock flags, and zero synthetic facades.

---

## 2. Mandatory Feature Migration Ledger

| ID | Mandatory Feature | Legacy Reference | Production Destination | Architecture & UI Adaptation | Status |
|:---|:---|:---|:---|:---|:---|
| F01 | `.xcstrings` Localization Catalog UI | `SwiftCode-Legacy/.../Localizations/` | `swiftcode/Sources/SwiftCodeUI/Editor/StringCatalogEditorController.swift` | Automatic file-routing on `.xcstrings` open; table/split localization editor | VERIFIED |
| F02 | Info.plist Viewer and Editor | `SwiftCode-Legacy/.../PlistEditor/` | `swiftcode/Sources/SwiftCodeUI/Editor/PlistEditorController.swift` | Automatic file-routing on `Info.plist` open; structured dictionary/array key-value editor | VERIFIED |
| F03 | `.xcodeproj` Project Viewer | `SwiftCode-Legacy/.../XcodeProjViewer/` | `swiftcode/Sources/SwiftCodeUI/Editor/XcodeProjViewerController.swift` | Automatic file-routing on `.xcodeproj` open; target/build phase hierarchy tree | VERIFIED |
| F04 | Artboards | `SwiftCode-Legacy/.../ArtboardView.swift` | `swiftcode/Sources/SwiftCodeUI/Editor/PreviewArtboardRuntime.swift` | Multi-device simultaneous canvas preview with interactive rotation and scale | VERIFIED |
| F05 | Integrated Terminal | `SwiftCode-Legacy/.../Terminal/` | `swiftcode/Sources/SwiftCodeUI/Terminal/` | Embedded PTY terminal emulator integrated into IDE debug/bottom pane | VERIFIED |
| F06 | IPA Packaging & Signing | `SwiftCode-Legacy/.../IPABuildView.swift` | `swiftcode/Sources/SwiftCodeUI/Deploy/IPABuildView.swift` | Real `xcodebuild -exportArchive` pipeline, code-signing identities, provisioning | VERIFIED |
| F07 | Full Source Control Workspace | `SwiftCode-Legacy/.../Git/` | `swiftcode/Sources/SwiftCodeUI/SourceControl/` | Staging, visual diff inspector, branch management, stash, commit history | VERIFIED |
| F08 | CI Visual Workflows | `SwiftCode-Legacy/.../CI/` | `swiftcode/Sources/SwiftCodeUI/GitHub/GitHubWorkflowsSidebarView.swift` | Visual GitHub Actions workflow builder, run status, matrix execution | VERIFIED |
| F09 | Simulators & Previews | `SwiftCode-Legacy/.../Simulator/` | `swiftcode/Sources/SwiftCodeUI/Window/DeviceConnect/`, `SwiftCodePreviews` | Real `simctl` discovery, boots, live canvas rendering, SwiftUI preview engine | VERIFIED |
| F10 | Visual UI Builder | `SwiftCode-Legacy/.../UIBuilder/` | `swiftcode/Sources/SwiftCodeUI/Editor/InterfaceBuilderController.swift` | Visual Canvas, layout constraints, nib/storyboard parser & serializer | VERIFIED |
| F11 | SF Symbols Browser | `SwiftCode-Legacy/.../Symbols/` | `swiftcode/Sources/SwiftCodeUI/Symbols/SymbolsBrowserView.swift` | Category filtering, search, variable color rendering, symbol export | VERIFIED |
| F12 | Device Connect | `SwiftCode-Legacy/.../DeviceConnect/` | `swiftcode/Sources/SwiftCodeUI/Window/DeviceConnect/DevicesController.swift` | Hardware pairing, network discovery, device telemetry, camera, triggers | VERIFIED |
| F13 | Virtualization | `SwiftCode-Legacy/.../Virtualization/` | `swiftcode/Sources/SwiftCodeUI/Virtualization/` | Real Apple Virtualization framework bindings, disk images, VM lifecycle | VERIFIED |
| F14 | Database Management | `SwiftCode-Legacy/.../Database/` | `swiftcode/Sources/SwiftCodeUI/Database/DatabaseDashboard.swift` | SQLite / CoreData schema inspector, SQL console, table visualizer | VERIFIED |
| F15 | Coding Dictionary | `SwiftCode-Legacy/.../Dictionary/` | `swiftcode/Sources/SwiftCodeUI/Dictionary/CodingDictionaryView.swift` | Swift/Apple API syntax lookup, symbol definitions, code examples | VERIFIED |
| F16 | All Scaffold Templates (10) | `SwiftCode-Legacy/.../Templates/` | `swiftcode/Sources/SwiftCodeProject/Templates/` | CommandLineTool, DocumentApp, Framework, GameMetal, GameSpriteKit, MultiplatformApp, SafariExtension, StaticLibrary, SwiftMacro, SwiftPackage | VERIFIED |
| F17 | SwiftCode Project Archive | `SwiftCode-Legacy/.../Archive/` | `swiftcode/Sources/SwiftCodeWorkspace/ProjectArchive.swift` | Self-contained project zip export/import, dependency bundling, manifest | VERIFIED |

---

## 3. Assist System Realignment

| Subsystem | Requirement | Implementation Target | Verification Result |
|:---|:---|:---|:---|
| AI Providers (13) | Retain existing model infrastructure intact | `swiftcode/Sources/SwiftCodeAssistant/Providers/` | All 13 providers (Anthropic, OpenAI, Gemini, Ollama, Bedrock, Mistral, Perplexity, OpenRouter, Hermes, Groq, Codex, OpenCode, AFM) active |
| Legacy Tools (291) | Register all 291 legacy Assist tools | `swiftcode/Sources/SwiftCodeAssistant/AssistToolRegistry.swift` | 291 tools registered with input schema validation |
| System Training Assets (33) | Bundle 33 Markdown training files | `swiftcode/Sources/SwiftCodeAssistant/Resources/System Assets/`, `SystemIndex.swift` | 33 assets loaded into agent context index |
| MCP Exclusivity | Restrict tools and system instructions to legacy set | `swiftcode/Sources/SwiftCodeMCP/` | `assistExclusivityMode` strictly limits tool dispatch and context injection |

---

## 4. Version 2 Roadmap Features

| Feature | Target Component | Production Implementation | Verification |
|:---|:---|:---|:---|
| `simctl reboot` | `SimctlService.swift`, `SimulatorCommand.swift` | Executes `/usr/bin/xcrun simctl reboot <udid>` via async process executor | Passed |
| Coding Assistant `editHistory` | `SwiftCodeAssistant/Diff/AssistEditHistory.swift` | Persistent transactional diff ledger tracking line-by-line hunks across conversation turns | Passed |
| Device Hub Interactions | `DevicesController.swift` | Real triggers for Shake (`notify_post ShakeDevice`), Memory Pressure (`notify_post MemoryWarning`), Slow Animations, and Standby | Passed |
| App Skills (`.skillsbundle`) | `SwiftCodeProject/SkillsBundle.swift` | Validator and template matching `specs/formats/skills-bundle.md` (front-matter validation, max 10k chars, folder naming rules) | Passed |
| Icon Composer Viewer | `SwiftCodeUI/Editor/IconComposerController.swift` | Dedicated `.icon` viewer using `SwiftCodeIcon`, layer rendering, platform & appearance selectors | Passed |

---

## 5. Production Hardening

- **Zero Mock/Simulation Flags**: Removed `simulate_api_failures` and `simulate_deployment_errors` from `DeveloperFeatureFlags.swift` and `FeatureFlagsView.swift`.
- **Real Subsystems**: Replaced fake data seeds with real underlying services (Apple Virtualization, SourceKit-LSP, LLDB-DAP, Git, simctl).
- **Comment Policy Compliance**: Unconditional removal of all comments; strict max 2-line comment rule on all new code.
