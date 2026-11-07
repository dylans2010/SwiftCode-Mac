# Project: SwiftCode-Mac Complete Feature Migration & Hardening

## Architecture
SwiftCode-Mac is a clean-room independent IDE for Apple platforms, structured as a modular Swift Package (`swiftcode/Package.swift`) with 80+ targets, clean-room Apple framework reimplementations (`frameworks/`), scene composition tools (`composer/`), and external tooling (`tools/`).
- **Core Package**: `swiftcode/` (Sources: `SwiftCodeUI`, `SwiftCodeIDEShell`, `SwiftCodeIDECore`, `SwiftCodeAssistant`, `SwiftCodeMCP`, `SwiftCodeXcodebuild`, `SwiftCodeGitHub`, `SwiftCodeConnect`, `SwiftCodePreviews`, etc.)
- **Apple Frameworks**: `frameworks/` (Linux-buildable implementations of StoreKit, EventKit, Contacts, etc.)
- **Scene Composer**: `composer/`
- **Legacy Source**: `SwiftCode-Legacy/` (Reference source of functionality and tools)

## Feature Inventory
| # | Feature | Description | Phase | Milestone | Source |
|---|---------|-------------|-------|-----------|--------|
| 1 | Baseline Compiler Fixes | Fix `PeerSessionManager` public modifiers and `GitHubWorkflowsSidebarView` scope | Phase 1 | M1 | Survey baseline |
| 2 | Code Comment Removal Script | Unconditional removal of comments across 12,221 files via AST/FST | Phase 1 | M1 | R1, Master Directive §7 |
| 3 | 2-Line Commenting Policy | Enforce max 2-line comment rule on newly written/edited code | Phase 1 | M1 | R1, Master Directive §7 |
| 4 | Scaffold Templates (10) | Port CommandLineTool, DocumentApp, Framework, GameMetal, GameSpriteKit, MultiplatformApp, SafariExtension, StaticLibrary, SwiftMacro, SwiftPackage | Phase 1 | M2 | R2, F16 |
| 5 | IPA Packaging & Signing UI | Port `IPABuildView.swift` and `AppleSignInView.swift` into `SwiftCodeUI/Deploy/` | Phase 1 | M2 | R2, F06 |
| 6 | Virtualization UI & Real Disks | Wire virtualization management views into `VirtualizationWindowController` & replace mock VM seeds | Phase 1 | M2 | R2, F13 |
| 7 | Full Source Control & CI | Verify Git staging/commits/merge and CI Visual Workflows | Phase 1 | M2 | F07, F08 |
| 8 | Centralized Tools Drawer | Implement `SCToolsView.swift` and add Tools toolbar launcher button | Phase 2 | M3 | Master Directive §4 |
| 9 | .xcstrings Editor Routing | Automatic file-type routing for Localization Catalogs on open | Phase 2 | M3 | F01, Master Directive §5 |
| 10 | Info.plist Editor Routing | Automatic file-type routing for Info.plist & entitlements on open | Phase 2 | M3 | F02, Master Directive §5 |
| 11 | .xcodeproj Viewer Routing | Automatic file-type routing for .xcodeproj opening `XcodeProjViewer` | Phase 2 | M3 | F03, Master Directive §5 |
| 12 | Fallback Code Editor | Standard text/code editor routing for all normal source files | Phase 2 | M3 | Master Directive §5 |
| 13 | Assist Rebranding | Rename Assistant -> Assist while maintaining backward-compatibility typealiases | Phase 2 | M4 | R3, Master Directive §3 |
| 14 | AI Provider Preservation | Retain all 13 AI backend providers intact (`AssistantBackends`, `AssistantProvider`) | Phase 2 | M4 | R3, Master Directive §3 |
| 15 | 291 Legacy Assist Tools | Ensure all 291 tools from `SwiftCode-Legacy` are active in `AssistToolRegistry` | Phase 2 | M4 | R3, Master Directive §3 |
| 16 | 33 System Training Assets | Bundle 33 Markdown training assets and inject via `SystemIndex` | Phase 2 | M4 | R3, Master Directive §3 |
| 17 | MCP Exclusivity Restriction | Filter MCP tools to strictly 291 Legacy tools and instructions to 33 assets | Phase 2 | M4 | R3, Master Directive §3 |
| 18 | Safe Rebranding & Import Audit | Audit imports to eliminate fabricated modules (e.g. SwiftCodeUI) -> `IMPORT_AND_MODULE_AUDIT.md` | Phase 2 | M5 | Master Directive §6 |
| 19 | Experimental Features Hardening | Remove simulated fault flags in `FeatureFlags.swift` and harden 9 experimental subsystems | Phase 3 | M7 | R4, Master Directive §0 |
| 20 | V2: `simctl reboot` | Add real `reboot` verb to `SimulatorCommand.swift` and `SimctlService.swift` | Phase 3 | M6 | R5, README.md |
| 21 | V2: Coding Assistant `editHistory` | Persistent diff ledger tracking code changes across turns in `SwiftCodeAssistant` | Phase 3 | M6 | R5, README.md |
| 22 | V2: Device Hub Interactions | Shake, memory pressure, slow animations, Standby in `DevicesController.swift` | Phase 3 | M6 | R5, README.md |
| 23 | V2: App Skills (`.skillsbundle`) | Template validator matching `specs/formats/skills-bundle.md` | Phase 3 | M6 | R5, README.md |
| 24 | V2: Icon Composer Document Viewer | Dedicated `.icon` viewer in `SwiftCodeUI` using `SwiftCodeIcon` | Phase 3 | M6 | R5, README.md |
| 25 | 10 Master Directive Audit Reports | Generate all 10 required audit reports specified in MASTER_DIRECTIVE.md | Phase 3 | M7 | Master Directive §8 |
| 26 | Final E2E Test Suite & Forensic Audit | Pass `swift test` and pass Forensic Integrity Audit (`teamwork_auditor`) | Phase 3 | M7 | Project Acceptance |

## Operational Phases & Milestones
### Phase 1: Codebase Sanitization & Core Feature Migration
| # | Milestone Name | Scope | Dependencies | Status |
|---|----------------|-------|-------------|--------|
| M1 | Baseline Fix & Comment Stripping | Fix `PeerSessionManager` & `GitHubWorkflowsSidebarView`; run AST comment stripper | none | VERIFICATION_GATE |
| M2 | Legacy Features Migration | Port 10 templates, IPABuildView, AppleSignInView, Virtualization UI | M1 | PLANNED |

### Phase 2: IDE Architecture, Editor Routing & Assist Realignment
| # | Milestone Name | Scope | Dependencies | Status |
|---|----------------|-------|-------------|--------|
| M3 | Tools Drawer & File Editor Routing | Implement `SCToolsView.swift` & automatic routing for Info.plist, .xcstrings, .xcodeproj | M1, M2 | PLANNED |
| M4 | Assist Realignment & MCP Exclusivity | Assist rebranding, 13 providers preserved, 291 tools, 33 assets, MCP exclusivity | M1 | PLANNED |
| M5 | Rebranding & Import Audit | Audit imports, eliminate fabricated modules -> `IMPORT_AND_MODULE_AUDIT.md` | M1, M2, M3, M4 | PLANNED |

### Phase 3: Production Hardening, V2 Features & Final Verification Audits
| # | Milestone Name | Scope | Dependencies | Status |
|---|----------------|-------|-------------|--------|
| M6 | Version 2 Roadmap Features | Implement `simctl reboot`, assistant `editHistory`, Device Hub triggers, App Skills | M1 | PLANNED |
| M7 | Production Hardening, Tests & Audit Reports | Hardening (zero mock flags), `swift test` verification, generate 10 audit reports | M1, M2, M3, M4, M5, M6 | PLANNED |
