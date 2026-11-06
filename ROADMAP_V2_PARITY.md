# ROADMAP_V2_PARITY.md — SwiftCode Version 2 roadmap parity

Source: the `### Version 2: Xcode 27.2 parity` table and `### Further out`
list in `README.md`, assessed against the Legacy → Mac migration
(2026-11-05/06). Every row below was checked against the live tree at
the rebrand commit (`305696b`) and the Wave 19 slices A/C/D/E
commit (`b322a16`) and slice B (system assets, staged for the
next commit); "Evidence" names the files that establish
the state. Nothing here is marked VERIFIED — the Mac build/test run on
Dylan's Mac is still pending, and these states describe code present in
the repo, not code proven to run.

States: IMPLEMENTED = the item exists in the tree as real code;
PARTIAL = part of the item exists; NOT STARTED = no code for the item.
"README state" is the wording the README table / list carries after
this migration; the previous wording is in "Before".

## Version 2: Xcode 27.2 parity

| Area | Before | README state now | Migration status | Evidence |
|---|---|---|---|---|
| Project files | Planned | Planned | NOT STARTED | No `.xcproj` anywhere in `swiftcode/Sources/` — the JSON project format was not ported. The repo's own project format work is the `.scproj` layer (16 managers, bulk wave), which is SwiftCode's format, not Xcode 27.2's `.xcproj`. |
| Platforms | Investigating | Investigating | NOT STARTED | No `HomeView` anywhere in `swiftcode/Sources/`. |
| App Intents | Planned; the API is a developer preview | Planned; the API is a developer preview | NOT STARTED | No `.skillsbundle` anywhere in `swiftcode/Sources/`. |
| Device Hub | Planned | Partial: device discovery, pairing and remote services landed; Shake, memory pressure, slow animations and Standby not yet implemented | PARTIAL | `swiftcode/Sources/SwiftCodeConnect/` (24 files: `IOSDiscoveryService`, `MacDiscoveryService`, `PairingManager`, `TrustStore`, `ConnectBuildService`, `ConnectTestService`, `ConnectTerminalService`, `ConnectFileService`, `ConnectGitService`). The four named interactions are absent — the only "shake" hits in the tree are "handshake". |
| Editor | Planned | Planned | NOT STARTED | No rendered-Markdown editor and no `#Playground`. Wave 19 slice C added a read-only Markdown renderer for the notes view (`SwiftCodeUI/Notes/MarkdownRenderer.swift`, swift-markdown) — a preview, not an editor with formatting tools. |
| Icons | Partial: `.icon` files build into app icons today | Partial: `.icon` files build into app icons today | NOT STARTED (by this migration; pre-existing Partial kept) | Only a menu-order string (`SwiftCodeIDECore/App/DeveloperTools.swift`), a file template (`Icon Composer Icon`, `.icon`, in `Model/Templates.swift`), and `packaging/icon/generate-all-app-icons.swift`. No Icon Composer 2.0 document editor and no `.icon` viewer. |
| Command line | Partial | Partial: simctl-style verbs landed (list, boot, shutdown, create, delete, erase, install, uninstall, launch, terminate); reboot still missing | PARTIAL | `swiftcode/Sources/SwiftCodeIDECore/Simctl/` — the whole cluster ported from Legacy in the bulk wave with the canned output / fake UDIDs removed (honest errors where the backend is unavailable): `SimctlService.swift`, `SimctlDiscoveryClient.swift`, `SimctlJSONModels.swift`, `CommandExecutionEngine.swift`. No `reboot` verb exists in `SimctlService`. |
| Coding assistant | Partial: chat, proposals, `swiftcode mcp` | Partial: agent and plug-in workflows landed (Agentic registry, Extensions v2, MetaAssist bridge, 433 MCP tools); edit history still missing | PARTIAL | 433 MCP tools, 0 duplicate IDs (`swiftcode/Sources/SwiftCodeMCP/`); Agentic registry 141 tools; Extensions v2 (`SwiftCodeExtensions`); MetaAssist `muse serve` bridge (`SwiftCodeAssistant/MetaAssistTurnExecutor.swift`); 5 providers on `SwiftCodeAssistant`. No `EditHistory` / `editHistory` anywhere in `swiftcode/Sources/`. |

## Further out

| Item | Before | README state now | Migration status | Evidence |
|---|---|---|---|---|
| Signing, distribution and physical devices | (listed, no state) | Partial: signing model and device discovery/pairing landed; distribution output tree deliberately not ported; store submission still out | PARTIAL | Signing model: `swiftcode/Sources/SwiftCodeSigning/` (`SigningIdentity`, `ProvisioningProfile`, `ProvisioningResolver`, `EntitlementPolicy`, `EntitlementValue`, `NestedCode`, `Certificate`). Devices: `SwiftCodeConnect` (`PairingManager`, `TrustStore`, `IOSDiscoveryService`) + `SwiftCodeDeviceModel/DeviceConnectCommands.swift`. Distribution: the Legacy `Distribution/` output tree (201 MB / 2,478 files, ~91.6 MB filler from one script) was deliberately NOT copied — its rows stay NOT STARTED in `MIGRATION_FEATURE_PARITY.md`. |
| Simulators: speed and fidelity first, then tvOS, visionOS input, and wearing the visionOS simulator in a headset | (listed, no state) | Partial: simctl verbs and VM console over a real KVM probe landed; tvOS/visionOS input and headset wearing still out | PARTIAL | `SwiftCodeIDECore/Simctl/` (see Command line above); VM console over a real KVM probe in the gap-closure wave (no guest kernel/display — the window says so). No tvOS/visionOS input code. |
| AR on the simulator | (listed, no state) | Unchanged | NOT STARTED | No ARKit/RealityKit simulator camera/depth/pose code from the migration. |
| Interface Builder connections and Auto Layout, and the Core Data model editor | (listed, no state) | Unchanged | NOT STARTED | No `IBConnection`, Core Data model editor, or equivalent in `swiftcode/Sources/` (IB editor session/inspector models exist, but connections and the Core Data model editor do not). |
| Profiling of Mac processes, with allocations and leaks | (listed, no state) | Unchanged | NOT STARTED | Only a registry-only entry: `SwiftCodeIDECore/Debug/DebugToolsRegistry.swift:76` registers `memory_leaks` ("Memory Leak Detector") with no handler anywhere in `swiftcode/Sources/`. No allocations/leaks profiling implementation. |
| Scene Composer: an editor window for USD scenes | (listed, no state) | Unchanged | NOT STARTED | `composer/` is the command-line core only; no editor window (`SceneComposer.*Window`, `ComposerWindow`, USD editor window — no matches). |
| More open frameworks | (listed, no state) | Unchanged | NOT STARTED | The migration added IDE-internal targets (`SwiftCodeConnect`, `SwiftCodeCollaboration`, `SwiftCodeCloud`, `SwiftCodeGitHub`, `SwiftCodeExtensions`, `SwiftCodeSDK`, `SwiftCodePaywall`, `SwiftCodeGoogleAuth`), not open frameworks for Apple's APIs on Linux. `frameworks/` is unchanged by the migration. |

## What "implemented" means here

The V2 table's "Partial" rows above describe code present in the repo
after the migration. They do not mean the feature was run, built, or
verified on a Mac — no Swift tools were run in this environment (per
Dylan, 2026-11-06) and the Mac build/test pass is still pending on
Dylan's Mac. The per-file ledger is `MIGRATION_FEATURE_PARITY.md`
(2,409 IMPLEMENTED / 492 SUPERSEDED / 8,931 NOT STARTED of 11,832
Legacy files; 0 VERIFIED).
