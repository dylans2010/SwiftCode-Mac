# SwiftCode-Legacy to Production inventory

Temporary working document. Every row was produced by running the command in its **Proof**
column in this repository on 2026-11-07, not from the previous inventory, which contained
fabricated numbers (for example a "27,291-line" `IPABuildView.swift`).

Legend: **PRESENT** real implementation · **PARTIAL** some of it exists · **MISSING** nothing
in production · **BLOCKED** needs a written spec first (AGENTS.md rule 4).

---

## 0. Scope of the two trees

| Metric | Legacy | Production | Proof |
|---|---|---|---|
| Swift files | 2,232 | 5,103 | `find SwiftCode-Legacy -name '*.swift' \| wc -l` vs `find swiftcode frameworks composer -name '*.swift' \| wc -l` |
| Assist tool files | 278 (`Backend/Assist/Tools`) | 30 (`SwiftCodeAssistant/Tools`) + 14 (`SwiftCodeMCP/Tools/Assist`) | `ls SwiftCode-Legacy/SwiftCode/Backend/Assist/Tools \| wc -l` |
| Assist registrations | 291 | 39 (20 Assistant + 19 MCP) | `grep -c 'register(' SwiftCode-Legacy/SwiftCode/Backend/Assist/AssistToolRegistry.swift` |
| System training docs | 33 | 33 mirrored | `ls 'SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets' \| wc -l` |

---

## 1. Assist (formerly "Assistant")

### 1.1 Tool surface

Legacy surface extracted mechanically into
`swiftcode/Sources/SwiftCodeAssistant/Tools/AssistToolCatalog.swift`
(generator `research/audit/gen_tool_catalog.py`, data `research/audit/legacy_tool_catalog.json`).

- Catalog entries: **290** distinct ids (291 registrations minus one collision).
- Production `AssistTool` types: **36**; every id is inside the catalog.
- Catalog ids without a production implementation: **254**.

`AssistToolRegistry.register(_:)` refuses any id outside the catalog, and
`allTools` / `getToolSchemas()` are filtered by it, so the model can only be offered legacy
tool ids. Rejected ids are recorded in `rejectedToolIds`; `surfaceGaps` lists catalog ids with
no registration.

Measured: `prod ids in catalog: 36`, `prod ids NOT in catalog: []`,
`catalog ids with no prod impl: 254`.

**Status: PARTIAL.** The allow-list is real and enforced; 254 legacy tools are still
unimplemented.

### 1.2 System training data

All 33 documents were copied from
`SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets` over the production folder
with `Assistant` to `Assist` (`research/audit/sync_system_assets.py`), and no production-only
document remains.

Proof: `python3 -I research/audit/sync_system_assets.py` prints `copied: 33` and
`production-only files kept: []`.

**Status: PRESENT.** The production copies had described the 433-tool MCP catalogue; that text
is now replaced by the legacy text.

### 1.3 Naming

`SwiftCodeUI` already uses "Assist" (96 files); two literal `"Assistant"` strings remain.

**Status: PARTIAL.**

---

## 2. The 17 directive features

| # | Feature | Production location | Status | Proof |
|---|---|---|---|---|
| F01 | `.xcstrings` UI | `SwiftCodeIDEShell/Support/StructuredEditors.swift` routes `xcstrings` to `StringCatalogEditorModel` | PARTIAL: `SwiftCodeUI/App/LocalizingAppNewView.swift` does not exist | `test -f` fails; routing case exists |
| F02 | `Info.plist` / `.entitlements` editor | `swiftcode-ide/InfoPlistView.swift` | PRESENT | 1,389 lines |
| F03 | `.xcodeproj` viewer | `swiftcode-ide/XcodeProjViewer.swift` + `xcodeproj` case in `StructuredEditors.open` | PRESENT | 217 lines; `grep -n xcodeproj StructuredEditors.swift` |
| F04 | Artboards | `SwiftCodeUI/VisualUIBuilder` | PRESENT | 34 files, 7,845 lines |
| F05 | Integrated terminal | `SwiftCodeUI/Terminal` | PRESENT | directory present |
| F06 | IPA + Apple sign-in | `SwiftCodeUI/Deploy/IPABuildView.swift`, `AppleSignInView.swift` | PRESENT | 581 + 496 lines |
| F07 | Source control | `SwiftCodeUI/SourceControl` | PRESENT | 68 files, 17,290 lines |
| F08 | CI workflows | `SwiftCodeUI/CI` | PRESENT | 14 files, 3,923 lines |
| F09 | Simulators and previews | `SwiftCodePreviews`, `SwiftCodeIDECore/Simctl` | PRESENT | 26 files, 3,080 lines |
| F10 | Visual UI builder | shares `SwiftCodeUI/VisualUIBuilder` | PRESENT | as F04 |
| F11 | SF Symbols browser | `SwiftCodeUI/App/SFSymbolBrowserView.swift` | PRESENT | file exists |
| F12 | Device Connect | `SwiftCodeConnect` | PRESENT | 24 files, 2,934 lines |
| F13 | Virtualization | `SwiftCodeUI/Virtualization` | PARTIAL: legacy has 38 files (wizard, console, profiles absent) | 3 files, 976 lines |
| F14 | Database | `SwiftCodeUI/Database` | PRESENT | 42 files, 7,635 lines |
| F15 | Coding dictionary | `SwiftCodeUI/Dictionary` | PRESENT | 6 files, 2,485 lines |
| F16 | Legacy templates | `SwiftCodeIDECore/Model/NewProject/LegacyProjectTemplates.swift` | UNVERIFIED | not counted this pass |
| F17 | `.scproj` archive | `SwiftCodeIDECore/Model/SCProjectFormat.swift` | UNVERIFIED | not counted this pass |

---

## 3. Central tools drawer

`SwiftCodeUI/Window/SCToolsView.swift` (282 lines) is reachable from the menu:
`WorkspaceWindowController.swift:1669` wires `#selector(toggleToolsDrawer(_:))`, implemented in
`WorkspaceWindowController+ToolsDrawer.swift`.

**Status: PRESENT**, with a real defect: `SCToolsView.toolDestinationView` renders a
placeholder for every tool except IPA packaging and SF Symbols.

---

## 4. README "Version 2: Xcode 27.2 parity" and "Further out"

| Item | Status |
|---|---|
| JSON `.xcproj` project format | BLOCKED. No spec exists (`grep -rl xcproj specs` is empty) and the format was not studied; inventing a schema would be fabricated behavior. |
| HomeView platform | BLOCKED for the same reason; the name appears only in `docs/FUTURE.md` and templates. |
| `.skillsbundle` app skills | PARTIAL to PRESENT for template and validation: `SwiftCodeProject/SkillsBundle.swift` (239 lines) creates the bundle and validates folder names, front matter, duplicates and body length. Built output is not wired. |
| Device Hub: shake, memory pressure, slow animations, Standby | MISSING. |
| Rendered Markdown with formatting tools | PARTIAL: `swiftcode-ide/DevTools/MarkdownPreviewerView.swift` is 36 lines, no formatting tools. |
| `#Playground` | MISSING as an editor feature; the token only appears in docs and templates. |
| Icon Composer 2.0 / `.icon` viewer | PRESENT: `SwiftCodeIcon/IconDocument.swift` (350), `SwiftCodeUI/Editor/IconComposerController.swift` (278). |
| `simctl` verbs including reboot | PARTIAL: `SimulatorCommand.reboot` and `SimulatorManager.restartSelectedDevice()` exist, but the `swiftcode` CLI dispatcher only exposes `sim headset`, `sim runtimes`, `sim remote`. The README claim that the verbs landed is inaccurate. |
| Assist edit history | PARTIAL: `SwiftCodeAssistant/Diff/AssistEditHistory.swift` (179 lines) is a persisted transaction ledger with revert and reapply; no UI surfaces it. |

`ROADMAP_V2_PARITY.md` and `MIGRATION_FEATURE_PARITY.md`, both linked from the README, do not exist.

---

## 5. Compilation state

The package did not compile before this pass. Repaired this pass, all verified by rebuilding:

- added the missing `GitService` (status, diff, push) required by `AssistGitManager` and
  `AssistVerificationPipeline`;
- added the missing `ProcessRunnerTool` required by `AssistBuildProjectTool`;
- added `AlertSoundPlayer`, `NotificationManager` and `PlanQuestionManager` required by
  `AssistAgentSession`;
- added `MetaAssistProvider.shared`, `discoverModels()` and `normalizeToolName(_:)`;
- added `AssistXcodeProjectResolver.listedSchemes` and `resolveScheme`;
- removed a duplicate `KeyImportResult`;
- fixed actor-isolation and API-drift errors in `AssistFeedbackService`, `AssistContextBuilder`
  and `AssistModelDiscovery` (including a real `isDiscovering` flag set by `discoverAllModels`);
- moved the `EmptyTemplate` check out of the Assistant runtime suite, which referenced a
  downstream target, into `Tests/SwiftCodeIDECoreTests/EmptyTemplateScaffoldTests.swift`.

Command: `cd swiftcode && swift build --target SwiftCodeAssistant`.

The target is **not yet green**: 43 unique errors remain, all in the provider layer, in files
this pass did not modify (`GoogleCloudSDKTests` 13, `AssistManager` 12,
`GoogleCloudSDKConfiguration` 10, `HermesProvider` 5, `AntigravitySDKModelFetcher` 2,
`GoogleCloudSDKLifecycleManager` 1). Because the compiler reached these files, every file this
pass added or edited type-checks.

- `ProviderKind` has no `.gemini` and no `.mistral`;
- `AssistModelRouter` has no `resolveAPIKey`, `buildSDKConfiguration`, `currentRuntimeModel`;
- `AssistModelDiscoveryService` has no `providerResolutionForCustomModel`;
- `GoogleAccountAuthService` has no `actionableSignInError`, `swiftCodeClientID`,
  `requiredScopes`;
- `GoogleCloudSDKConfiguration` cannot be passed where `SDKSessionConfiguration` is expected;
- `ChatEvent` has no `delta`; `AppSettings` has no `$assistSystemID`;
  `HermesProvider` has no `findExecutable` and its `AssistantProvider` conformance crosses actor
  isolation; a `ready` case expects `[ModelInfo]`; `AssistModelRouterTests` is out of scope.

No claimed feature above should be treated as "built and verified" until that list is empty.

---

## 6. What is still required, in order

1. Repair the provider-layer errors listed in section 5, then build `SwiftCodeAssistant`,
   `SwiftCodeMCP`, `SwiftCodeIDECore` and `SwiftCodeUI`.
2. Port the 254 missing Assist tools; the catalog gives each id, name, summary and legacy type.
3. Add edit-history UI, and a Markdown editor with formatting tools.
4. Write specs for `.xcproj` and HomeView before implementing them.
5. Device Hub actions and the CLI `simctl` verb table.
6. Virtualization wizard, console and profile views (35 legacy files).
