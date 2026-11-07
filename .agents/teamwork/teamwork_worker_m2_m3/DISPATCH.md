# Worker M2-M3 Dispatch: Legacy Feature Migration, Tools Drawer & File Routing

## Mission
Write the real production Swift code for Milestone 2 and Milestone 3 immediately:
1. **10 Scaffold Templates**:
   - Port the 10 scaffold templates from `SwiftCode-Legacy/SwiftCode/Backend/Persistence/Templates/` into `swiftcode/Sources/SwiftCodeIDECore/Model/NewProject/LegacyProjectTemplates.swift`:
     `CommandLineToolTemplate`, `DocumentAppTemplate`, `FrameworkTemplate`, `GameMetalTemplate`, `GameSpriteKitTemplate`, `MultiplatformAppTemplate`, `SafariExtensionTemplate`, `StaticLibraryTemplate`, `SwiftMacroTemplate`, `SwiftPackageTemplate`.
   - Ensure they conform to `ProjectScaffoldTemplate` and are registered in `ProjectTemplateCatalog`.
2. **IPA Packaging & Apple Sign-In UI**:
   - Port `IPABuildView.swift` (from `SwiftCode-Legacy/SwiftCode/Views/Build/Xcode Build/IPABuildView.swift`) and `AppleSignInView.swift` into `swiftcode/Sources/SwiftCodeUI/Deploy/`.
   - Wire `IPABuildView` to `IPABuildService.shared` in `SwiftCodeXcodebuild`.
   - Adapt styling to modern AppKit/SwiftUI controls.
3. **Virtualization UI**:
   - Wire virtualization management views into `swiftcode/Sources/SwiftCodeUI/Virtualization/` and connect them into `VirtualizationWindowController.swift`.
   - Replace static mock VM seedings in `VirtualMachineRegistry.swift` with real virtual disk file inspection.
4. **Centralized Tools Drawer (`SCToolsView.swift`)**:
   - Create `swiftcode/Sources/SwiftCodeUI/Window/SCToolsView.swift` (or in `swiftcode-ide/`).
   - Implement standalone tool cards/launchers:
     - SF Symbols Browser (`SFSymbolBrowserView`)
     - Database Management (`DatabaseExplorerWindowController`)
     - Virtualization Console (`VirtualizationWindowController`)
     - Visual UI Builder (`VisualUIBuilderWindowManager` / `ArtboardWindowController`)
     - Device Connect (`DeviceWindowController`)
     - IPA Packaging & Signing (`IPABuildView`)
     - Coding Dictionary (`CodingDictionaryWindowController`)
     - CI Workflows (`CIWindowController`)
     - Terminal (`SandboxTerminalWindowController`)
   - Add a dedicated "Tools" button in the editor toolbar (`WorkspaceWindowController` / `EditorAreaController`) to toggle `SCToolsView`.
5. **Automatic File-Type Detection and Specialized Editor Routing**:
   - In `swiftcode/Sources/SwiftCodeIDEShell/Support/StructuredEditors.swift` and `WorkspaceWindowController.swift`:
     - `Info.plist` / `*.entitlements` -> dedicated `InfoPlistView` / `PlistEditorController`.
     - `*.xcstrings` -> dedicated `LocalizingAppNewView` (String Catalog editor).
     - `*.xcodeproj` -> dedicated `XcodeProjViewer`.
     - Fallback to standard code editor for all normal source files.
   - Verify that opening files activates the specialized viewer automatically rather than requiring drawer selection.
6. **Build Verification**:
   - Run `cd swiftcode && swift build` to verify clean compilation.

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work.

## Working Directory
/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m2_m3/

## Output
Write completion report to `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m2_m3/handoff.md`.

## 2026-11-07T01:50:48Z
Task received from orchestrator:
Write the production Swift code for Milestone 2 and Milestone 3 immediately:
1. Port the 10 scaffold templates into swiftcode/Sources/SwiftCodeIDECore/Model/NewProject/LegacyProjectTemplates.swift and register them.
2. Port IPABuildView.swift and AppleSignInView.swift into swiftcode/Sources/SwiftCodeUI/Deploy/ and bind to IPABuildService.
3. Wire Virtualization UI views into swiftcode/Sources/SwiftCodeUI/Virtualization/ and VirtualizationWindowController.
4. Implement SCToolsView.swift with tool cards and add Tools button in the editor toolbar.
5. Implement automatic file-type routing in StructuredEditors.swift and WorkspaceWindowController for Info.plist, *.xcstrings, and *.xcodeproj.
6. Run `cd swiftcode && swift build` to verify clean compilation.
7. Write your handoff report to /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m2_m3/handoff.md.

## 2026-11-07T02:07:51Z
Orchestrator heartbeat check:
Context: Checking M2-M3 implementation status
Content: Heartbeat check: `SCToolsView.swift`, `IPABuildView.swift`, `AppleSignInView.swift`, and `LegacyProjectTemplates.swift` have landed in the tree. What is your current status on build verification and `handoff.md`?
Action: Please update your progress.md and finalize your handoff report.
