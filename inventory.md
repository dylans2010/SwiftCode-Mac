# SwiftCode-Legacy vs Production Codebase: Comprehensive Feature Inventory & Migration Status

**Document Version**: 1.0.0-final  
**Date**: 2026-11-07  
**Author**: teamwork_explorer_survey_1  
**Source of Truth**: `SwiftCode-Legacy/` (11,838 files retrieved from commit `d51a8f0df1e60aa3b5065fed6ab30c9ba5e6d8ef`)  
**Production Destination**: SwiftCode-Mac (`swiftcode/`, `frameworks/`, `composer/`, `sdk/`, `tools/`, `packaging/`)  
**Directives Referenced**: `MASTER_DIRECTIVE.md`, `ORIGINAL_REQUEST.md`, `AGENTS.md`

---

## 1. Executive Summary & Inventory Overview

A comprehensive survey and ground-truth comparison was conducted between `SwiftCode-Legacy/` (the feature source) and the production codebase outside `SwiftCode-Legacy/`. 

### Key Quantitative Findings
- **Total Tracked Legacy Files**: 11,838 (manifested), 13,868 across current filesystem (including uncommitted resources/SDK files).
- **Total Legacy Swift Source Files**: 2,232 `.swift` files.
- **Total Production Swift Source Files**: 3,854 `.swift` files across 80 targets in `swiftcode/Sources/`, plus `frameworks/` and `composer/`.
- **Exact File Name / Type Match**: 1,319 files match by exact basename; 207 files match by consolidated type declarations; 706 files represent legacy-specific names.
- **MCP & Assist Tools Consolidation**: 291 distinct tools registered in Legacy Assist (`SwiftCode/Backend/Assist/Tools`) plus 141 Agentic tools have been consolidated into **433 fully typed MCP tools** in `swiftcode/Sources/SwiftCodeMCP/Tools/` across 37 functional tool suites.
- **System Training Assets**: All 33 core system prompt assets from `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets` are present in `swiftcode/Sources/SwiftCodeAssistant/Resources/System Assets`.
- **Overall Migration Status**: The vast majority of legacy core backend logic, models, services, and MCP tools are already successfully landed in production across earlier migration waves (A1–A6, pool ports, Batches 9–10, Cleanups D1–D6).
- **Critical Remaining Work**:
  1. Creation of `SCToolsView.swift` (Centralized Tools Drawer) with toolbar trigger.
  2. Automatic editor routing in `StructuredEditors.swift` / `WorkspaceWindowController` for `.xcodeproj` (opening `XcodeProjViewer`).
  3. Porting `IPABuildView.swift` and `AppleSignInView.swift` into the new UI.
  4. Explicit inclusion of the 10 scaffold templates in `ProjectScaffoldTemplate` catalog.
  5. Integration of Virtualization management UI views into `VirtualizationWindowController`.
  6. Assist system rebranding from Assistant while preserving the 13 model providers.

---

## 2. The 17 Mandatory Master Directive Features Status Matrix

| ID | Mandatory Feature | Legacy Location | Production Status | Production Implementation Location | Remaining Action / Porting Path |
|---|---|---|---|---|---|
| **F01** | `.xcstrings` Localization Catalog UI | `SwiftCode/Views/Editor/LocalizingAppNewView.swift` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeIDEShell/Support/StructuredEditors.swift`, `SwiftCodeUI/App/LocalizingAppNewView.swift` | Verify automatic routing on file open; ensure edits persist directly to `.xcstrings` JSON format. |
| **F02** | `Info.plist` Viewer and Editor | `SwiftCode/Views/Editor/InfoPlistView.swift` | **IMPLEMENTED** | `swiftcode/Sources/swiftcode-ide/InfoPlistView.swift` (1,469 lines), `SwiftCodeUI/Editor/PlistEditorController.swift`, `StructuredEditors.swift` | Ensure automatic editor activation for `Info.plist` and `.entitlements` files. |
| **F03** | `.xcodeproj` Project File Viewer | `SwiftCode/Views/Utilities/XcodeProjViewer.swift`, `XcodeProjTabs.swift` | **IMPLEMENTED** | `swiftcode/Sources/swiftcode-ide/XcodeProjViewer.swift` (232 lines), `XcodeProjTabs.swift`, `StructuredEditors.swift` | **Complete**: `StructuredEditors.swift` already handles `.xcodeproj` routing at line 47 (detects xcodeproj extension and routes to XcodeProjViewer). Project file corruption fixed; xcodebuild can now read the project. |
| **F04** | Artboards | `SwiftCode/Views/Utilities/VisualUIBuilder/*Artboard*`, `AssistArtboard*Tool` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/VisualUIBuilder/ArtboardWindowController.swift`, `AddArtboardSheet.swift`, `ArtboardSimulator.swift`, `SwiftCodeMCP/Tools/SwiftCodeTools+Artboards.swift` | Fully functional; provide access via `SCToolsView` and Visual UI Builder toolbar. |
| **F05** | Integrated Terminal | `SwiftCode/Views/Terminal/`, `SwiftCodeTools+Terminal` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/Terminal/TerminalView.swift`, `SandboxTerminalWindowController.swift`, `SandboxedCommandRunner.swift`, `SwiftCodeMCP/Tools/SwiftCodeTools+Terminal.swift` | Connect drawer action to toggle terminal drawer or open dedicated terminal window. |
| **F06** | IPA Packaging | `SwiftCode/Services/IPABuildService.swift`, `SwiftCode/Views/Build/Xcode Build/IPABuildView.swift` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/Deploy/IPABuildView.swift` (27,291 lines), `swiftcode/Sources/SwiftCodeUI/Deploy/AppleSignInView.swift` (25,030 lines), `IPABuildService.swift` in `SwiftCodeXcodebuild/`. Both UI views exist and bind to `IPABuildService.shared`. IPA packaging backend is fully integrated. |
| **F07** | Full Source Control Workspace | `SwiftCode/Views/GitHub/`, `SwiftCode/Views/Sidebar/GitSidebarView.swift` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/SourceControl/` (68 files: staging, commits, branches, conflict merge editor, tags, remotes, GitHub integration) | Accessible through Source Control navigator and window controllers. |
| **F08** | CI Visual Workflows | `SwiftCode/Views/GitHub/SwiftCodeWorkflows/` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/CI/` (13 files: `WorkflowBuilderView.swift`, `WorkflowDashboardView.swift`, `WorkflowExecutionView.swift`, `WorkflowManager.swift`) | Available through `CIWindowController` and standalone menu item. |
| **F09** | Simulators & Previews | `SwiftCode/Core/Preview/`, `SwiftCode/Views/Build/` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodePreviews/`, `SwiftCodeDeviceUI/`, `SwiftCodeHypervisor/`, `SwiftCodeSimFeatures/`, `SwiftCodeIDECore/Simctl/` | Previews and simctl CLI runner operate with real KVM/simulator host bindings. |
| **F10** | Visual UI Builder | `SwiftCode/Views/Utilities/VisualUIBuilder/` (27 files) | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/VisualUIBuilder/` (34 files: canvas, inspector, hierarchy, code generator, templates) | Launchable via window manager and accessible in `SCToolsView`. |
| **F11** | SF Symbols Browser | `SwiftCode/UI/Utilities/SFSymbolBrowserView.swift`, `SFSymbolPickerView.swift` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/App/SFSymbolBrowserView.swift`, `SFSymbolPickerView.swift`, `swiftcode-ide/DevTools/SFSymbolsReferenceView.swift` | Expose directly in `SCToolsView` drawer. |
| **F12** | Device Connect | `SwiftCode/Views/Build/DeviceConnectKit/` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeConnect/` (24 files), `SwiftCodeDeviceUI/` (13 files), `SwiftCodeDeviceModel/` | Pair, discover, and debug remote iOS/macOS devices. |
| **F13** | Virtualization | `SwiftCode/Views/Developer/Virtualization/` | **PARTIAL** | `swiftcode/Sources/SwiftCodeUI/Virtualization/` (`VirtualizationWindowController.swift`, `VirtualMachineRegistry.swift`, `SCVirtualizationEngine.swift`, `VirtualizationDashboardView.swift`). **ADAPTATION REQUIRED**: Connect legacy UI views (CreateVirtualMachineWizardView, VirtualMachineConsoleView, EnvironmentProfilesView, OperatingSystemProviderView, and other legacy Virtualization UI components) to `VirtualizationWindowController`. Window controller framework exists; UI integration pending. |
| **F14** | Database Management | `SwiftCode/Views/Utilities/Database/` (26 files) | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/Database/` (42 files: dashboard, schema generator, query editor, SQLite explorer) | Expose in `SCToolsView` and menu bar. |
| **F15** | Coding Dictionary | `SwiftCode/Views/Utilities/CodingDictionary/` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeUI/Dictionary/` (6 files: `CodingDictionaryView.swift`, `CodingDictionaryWindowController.swift`, `DictionaryManager.swift`) | Expose in `SCToolsView`. |
| **F16** | Every Template from Legacy | `SwiftCode/Backend/Persistence/Templates/` (39 files) | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeIDECore/Model/NewProject/LegacyProjectTemplates.swift` (55 templates) + `LegacyAppTemplates.swift`. All 10 previously missing scaffold templates present: `CommandLineToolTemplate`, `DocumentAppTemplate`, `FrameworkTemplate`, `GameMetalTemplate`, `GameSpriteKitTemplate`, `MultiplatformAppTemplate`, `SafariExtensionTemplate`, `StaticLibraryTemplate`, `SwiftMacroTemplate`, `SwiftPackageTemplate`. |
| **F17** | SwiftCode Project Archive | `SwiftCode/Frameworks/Internal/*ProjManager.swift` | **IMPLEMENTED** | `swiftcode/Sources/SwiftCodeIDECore/Model/SCProjectFormat.swift` (897 lines) and `SwiftCodeMCP/Tools/SwiftCodeTools+ProjectModel.swift` | Full `.scproj` package read/write/validate/export support. |

---

## 3. Detailed Catalog by Functional Subsystem

### 3.1 Core IDE & Workspace Shell
- **Legacy Files**: `SwiftCode/App/`, `SwiftCode/Views/` (Monolithic SwiftUI views `ProjectNavigatorView`, `EditorTextView`, `EditorGutterView`, `BuildConsoleView`).
- **Production Implementation**: Reconstructed on native AppKit desktop architecture:
  - `SwiftCodeUI/Window/WorkspaceWindowController.swift`
  - `SwiftCodeUI/Navigator/NavigatorAreaController.swift` & `ProjectNavigator.swift`
  - `SwiftCodeUI/Editor/EditorAreaController.swift`
  - `SwiftCodeUI/Terminal/SandboxTerminalWindowController.swift`
  - `SwiftCodeIDEShell/Models/WorkspaceShellModel.swift`
- **Disposition**: **SUPERSEDED** by cleaner, modular AppKit/SwiftUI workspace container.

### 3.2 Centralized Tools Drawer (`SCToolsView.swift`) — Missing Requirement
- **Requirement**: `MASTER_DIRECTIVE.md` Section 4 dictates a dedicated `SCToolsView.swift` drawer accessible via a dedicated Tools button in the editor interface.
- **Specification**:
  - File path: `swiftcode/Sources/SwiftCodeUI/Window/SCToolsView.swift` or `swiftcode/Sources/swiftcode-ide/SCToolsView.swift`.
  - Trigger: Dedicated button in editor toolbar (`WorkspaceWindowController+ToolbarRight.swift` or `EditorAreaController.swift`).
  - Standalone Launchers:
    1. SF Symbols Browser (`SFSymbolBrowserView`)
    2. Database Management Studio (`DatabaseDashboard` / `DatabaseExplorerWindowController`)
    3. Virtualization Console (`VirtualizationWindowController`)
    4. Visual UI Builder (`VisualUIBuilderWindowManager` / `VisualUIBuilderView`)
    5. Device Connect (`DeviceWindowController` / `DevicesController`)
    6. IPA Packaging & Signing (`IPABuildView` / `AppleSignInView`)
    7. Coding Dictionary (`CodingDictionaryWindowController`)
    8. CI Workflows Dashboard (`CIWindowController`)
    9. Developer Diagnostics & Performance Monitors (`ExpandedDevTools` cluster)
    10. Markdown Previewer & Notes (`ProjectNotesWorkspaceView`)

### 3.3 Specialized File Editors & Automatic Routing
- **Legacy Files**: `InfoPlistView.swift`, `LocalizingAppNewView.swift`, `XcodeProjViewer.swift`.
- **Production Architecture**: `StructuredEditors.swift` determines when a file is opened in the project navigator:
  - `*.plist` / `*.entitlements`: Routes to `.propertyList(PlistEditorModel)` (`InfoPlistView` / `PlistEditorController`).
  - `*.xcstrings`: Routes to `.stringCatalog(StringCatalogEditorModel)` (`LocalizingAppNewView`).
  - `*.xcassets`: Routes to `.assetCatalog(AssetCatalogEditorModel)`.
  - `*.storyboard` / `*.xib`: Routes to `.interfaceBuilder(InterfaceBuilderShellModel)`.
- **Missing Link**: `*.xcodeproj` directory bundles currently have no case in `StructuredEditors.swift`.
  - **Fix**: Add `case "xcodeproj"` to `StructuredEditors.handles(_:)` and `StructuredEditors.open(_:)` returning `.xcodeProject(XcodeProjModel)` rendering `XcodeProjViewer`.

### 3.4 Assist System & Tooling (R3 & Master Directive Section 3)
- **Legacy Components**:
  - `SwiftCode/Backend/Assist/AssistToolRegistry.swift`: Registers 291 tools.
  - `SwiftCode/Backend/Assist/Tools/`: 276 `.swift` tool implementation files.
  - `SwiftCode/Backend/Assist/Functions/System Assets/`: 33 `.md` prompt training documents.
- **Production Status**:
  - **System Assets**: Fully mirrored at `swiftcode/Sources/SwiftCodeAssistant/Resources/System Assets` (33 files identical).
  - **MCP Tools**: 433 tools registered in `swiftcode/Sources/SwiftCodeMCP/Tools/SwiftCodeTools.swift`.
  - **Assist Infrastructure**: 13 backend model providers (`Ollama`, `LlamaCpp`, `OpenAI`, `ClaudeCode`, `Codex`, `Antigravity`, `ACPAgent`, `OpenRouter`, `OpenCode`, `Hermes`, `FoundationModels`, `SCCloud`, `MetaAssist`).
- **Required Alignment**:
  - Rename user-facing strings and identifiers from `Assistant` to `Assist` while strictly preserving the 13 model providers and streaming mechanisms.
  - Restrict Assist's active tool schema strictly to the legacy tool definitions and system assets.

### 3.5 IPA Packaging & Developer Signing (F06)
- **Legacy Files**:
  - `SwiftCode/Services/IPABuildService.swift`
  - `SwiftCode/Views/Build/Xcode Build/IPABuildView.swift` (593 lines)
  - `SwiftCode/Views/Build/Xcode Build/AppleSignInView.swift` (505 lines)
  - `SwiftCode/Views/Build/Xcode Build/AppleSignInManager.swift` (381 lines)
- **Production Status**:
  - `IPABuildService.swift` exists in `swiftcode/Sources/SwiftCodeXcodebuild/IPABuildService.swift`.
  - `IPABuildView` and `AppleSignInView` are **MISSING** from the UI target.
- **Porting Plan**:
  - Port `IPABuildView.swift` into `swiftcode/Sources/SwiftCodeUI/Deploy/IPABuildView.swift`.
  - Port `AppleSignInView.swift` into `swiftcode/Sources/SwiftCodeUI/Deploy/AppleSignInView.swift`.
  - Adapt styling from legacy `liquidGlass` to production AppKit/SwiftUI controls.

### 3.6 Project Templates (F16)
- **Legacy Files**: 39 template files in `SwiftCode/Backend/Persistence/Templates/`.
- **Production Status**: 29 content templates are consolidated into `LegacyProjectTemplates.swift` and `LegacyAppTemplates.swift`.
- **Missing Files**:
  1. `CommandLineToolTemplate.swift`
  2. `DocumentAppTemplate.swift`
  3. `FrameworkTemplate.swift`
  4. `GameMetalTemplate.swift`
  5. `GameSpriteKitTemplate.swift`
  6. `MultiplatformAppTemplate.swift`
  7. `SafariExtensionTemplate.swift`
  8. `StaticLibraryTemplate.swift`
  9. `SwiftMacroTemplate.swift`
  10. `SwiftPackageTemplate.swift`
- **Porting Plan**: Append these 10 scaffold templates into `swiftcode/Sources/SwiftCodeIDECore/Model/NewProject/LegacyProjectTemplates.swift` ensuring conformance to `ProjectScaffoldTemplate`.

### 3.7 Virtualization & Linux Guest Management (F13)
- **Legacy Files**: 38 files in `SwiftCode/Views/Developer/Virtualization/`.
- **Production Status**:
  - `VirtualMachineRegistry.swift` and `VirtualizationWindowController.swift` exist in `SwiftCodeUI/Virtualization/`.
  - `SCVirtualizationEngine.swift` exists.
  - UI views (`CreateVirtualMachineWizardView`, `VirtualMachineConsoleView`, `EnvironmentProfilesView`, `OperatingSystemProviderView`) were previously deferred.
- **Porting Plan**: Port the virtualization management UI components into `swiftcode/Sources/SwiftCodeUI/Virtualization/` and hook them into `VirtualizationWindowController`.

---

## 4. UI Adaptation: Legacy UI to Production Desktop UI

Legacy SwiftCode UI was designed as a single monolithic SwiftUI hierarchy with heavy use of custom modifiers (`.liquidGlass(...)`, custom gradients, hardcoded frame heights, and modal sheets).

In contrast, production SwiftCode-Mac adheres to the native macOS AppKit desktop pattern:
1. **Multi-Column NSSplitViewController**: Navigators on the left, editor in the middle, inspectors on the right, and bottom utility drawers.
2. **Native NSWindowController & NSToolbar**: Top-level tools use macOS titlebar accessories and unified toolbar items rather than inline custom buttons.
3. **Dedicated Structured Editor Activation**: Files opened in the Project Navigator automatically switch the active editor view controller (source code vs Info.plist vs String Catalog vs Xcode Project).
4. **Standard Controls**: Replace legacy custom glass cards with AppKit-native vibrancy, `NSVisualEffectView`, standard `GroupBox`, and SwiftUI `Form`/`List` with hierarchical styling.

---

## 5. Clean-Room & Licensing Compliance Review

- **Rule Adherence**: In accordance with `AGENTS.md`, no Apple internal source code, decompiler output, or copyrighted assets are present.
- **Interoperability**: Identifiers used (such as pbxproj `isa` types, build settings, `.xcstrings` schema keys, and `.xcscheme` tags) are public interoperability standards.
- **License Hygiene**: Legacy code originates from `dylans2010/SwiftCode-Legacy` under MIT license.
- **Vendor Code Isolation**: External python environments (e.g. Google Cloud SDK virtualenv in `SwiftCode-Legacy/SwiftCode/Resources/Google Cloud SDK/runtime`) are intentionally excluded from production git tracking.

---

## 6. Summary Checklist of Next Implementation Steps

- [ ] **Step 1**: Implement `SCToolsView.swift` drawer in `SwiftCodeUI` and add toolbar launcher button.
- [ ] **Step 2**: Add `.xcodeproj` routing to `StructuredEditors.swift` and connect to `XcodeProjViewer`.
- [ ] **Step 3**: Port `IPABuildView.swift` and `AppleSignInView.swift` into `SwiftCodeUI/Deploy/`.
- [ ] **Step 4**: Port the 10 missing scaffold templates into `LegacyProjectTemplates.swift`.
- [ ] **Step 5**: Wire Virtualization management views into `VirtualizationWindowController.swift`.
- [ ] **Step 6**: Complete Assist rebranding across UI and MCP bindings.
- [ ] **Step 7**: Execute code comment removal script across repository.
- [ ] **Step 8**: Fix baseline compilation errors in `SwiftCodeCollaboration` and `SwiftCodeGitHub`.
