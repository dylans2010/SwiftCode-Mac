# Bulk Adaptation — Legacy → Mac

**Status:** complete (time-boxed wrap-up, 2026-11-06). All 1,428 staged files in
`~/SwiftCode-Migration-Workspace/staging-bulk/` were coverage-checked and given a
disposition. Every genuinely-missing file that could be adapted honestly was adapted
as a whole file; nothing was left half-finished. No Swift toolchain was run anywhere
in this wave (Dylan's instruction); verification is static only. Nothing in this wave
is VERIFIED — `swift build` / `swift test` and live runs on Dylan's Mac are pending
for everything below.

## Method

Per staged file, in order: (1) check destination coverage first — if the feature
already exists in SwiftCode, record SUPERSEDED with the SwiftCode equivalent named and do
not duplicate it; (2) adapt what is genuinely missing into its proper SwiftPM
target, in destination style (SwiftCode native style, default accent, no Legacy
orange/liquidGlass), real implementations only, onto SwiftCode's Assist host (never a
parallel registry/session loop/providers; no Autopilot; no approval-gate bypass);
(3) respect the REVIEW scout's dispositions in
`~/SwiftCode-Migration-Workspace/audit/review-required-decisions.md` — a DROP stays
dropped; (4) if a file cannot be adapted honestly, record HONESTLY_UNAVAILABLE with
the exact reason — never fake it.

Gap-closure was working in the same tree concurrently. Before adapting, each worker
checked scoped `git status` and grepped the destination for the file's type names;
already-covered files were skipped and reported as such. No worker touched
gap-closure's files, `swiftcode/Package.swift`, the ledger, or the manifest. Wiring is
reported as a list for the parent (see § Wiring).

## Totals (1,428 / 1,428 accounted for)

| Slice | Files | Adapted | Superseded | Honest-unavail. | Skipped | Missing |
|---|---|---|---|---|---|---|
| Backend-Assist | 145 | 2 | 81 | 57 | 5 | 0 |
| Views-A | 271 | 109 | 69 | 2 | 91 | 0 |
| Views-B | 240 | 147 | 10 | 58 | 25 | 0 |
| Views-C | 176 | 96 | 62 | 17 | 1 | 0 |
| Views-D | 167 | 29 | 116 | 22 | 0 | 0 |
| Core | 124 | 61 | 62 | 1 | 0 | 0 |
| Persistence-Services | 126 | 87 | 32 | 1 | 6 | 0 |
| Frameworks-Features | 107 | 45 | 44 | 5 | 10 | 3 |
| Small-Clusters | 72 | 26 | 27 | 15 | 4 | 0 |
| **Total** | **1,428** | **602** | **503** | **178** | **142** | **3** |

Disposition TSVs (one row per staged file: legacy path, disposition, destination
path or equivalent, notes) live in `~/SwiftCode-Migration-Workspace/bulk/`:
`backend-assist-dispositions.tsv`, `views-a-dispositions.tsv`,
`views-b-dispositions.tsv`, `views-c-dispositions.tsv`,
`views-d-dispositions.tsv`, `core-dispositions.tsv`,
`persistence-services-dispositions.tsv`, `frameworks-features-dispositions.tsv`,
`small-clusters-dispositions.tsv`. These TSVs are the ledger-update source: the
602 ADAPTED rows become IMPLEMENTED, the 503 SUPERSEDED rows become SUPERSEDED with
the SwiftCode equivalent named in the TSV.

## Per-slice decisions

### Backend-Assist (145)

- **Adapted (2):** `SwiftCodeAssistant/PromptEnhancer.swift` (202 lines; prompt
  enhancement via Foundation Models provider, fails `.modelUnavailable` honestly
  when Apple Foundation Models is unavailable); `SwiftCodeMCP/CIBuildYAML.swift`
  (484 lines; GitHub Actions `build.yml` generation). Plus 2 test files.
- **Superseded (81):** covered by the Waves 1–8 Assist port.
- **Honestly-unavailable (57):** worker runtime (20 — a seam exists, runtime not
  built); vendored Google Cloud SDK runtime (11); REA reverse backend (5);
  Autopilot / autonomous takeover (8 — excluded by design); Legacy-loop internals
  (7); System Assets corpus (3 — Wave 19); other (3).
- **Skipped (5).**

### Views-A (271)

- **Adapted (109):** consolidated into 6 model+view pairs — Personal
  Documentation, Operations dashboard, Package discovery, Project inspector,
  Project dashboard, StatusBar — plus a share-sheet presenter. 16 new files.
- **Superseded (69).**
- **Honestly-unavailable (2).**
- **Skipped (91):** already covered elsewhere — 54 Database rows belong to
  gap-closure, 30 VisualUIBuilder/Artboards rows belong to gap-closure, 5 Transfer
  Projects rows belong to the Backend-Projects (Persistence-Services) slice.
- **Honest deviations:** Legacy SwiftData → Codable JSON (SwiftCode has no database
  layer); Legacy "Clean / Up to date" defaults NOT carried over — status reads
  "Unknown" until a live check runs.

### Views-B (240)

- **Adapted (147):** 152 new files in `swiftcode-ide/DevTools/` (141) + `Developer/`
  (11). Bulk transform of self-contained SwiftUI views; liquid-glass removed,
  Legacy orange → default accent (except 6 spots where orange is data, not chrome).
  `#if canImport` guards + `DevToolsUnavailableView` stub for Linux.
- **Superseded (10).**
- **Honestly-unavailable (58):** 42 are Virtualization views (no
  VZVirtualMachine backend). 11 Developer views were hardcoded/fabricated data in
  Legacy and were not ported as fakes.
- **Skipped (25):** real rewrites (Battery/CPU/FPS monitors, QR/barcode
  generators, etc.).
- **Follow-up:** views are not yet reachable from the UI (hub + menu entry needed).

### Views-C (176)

- **Adapted (96):** 17 new files (5,532 lines). DeviceConnectKit port — 69 Legacy
  files → 7 `DeviceConnect*` files + view (honest fixes: `stopMonitoring` cancels
  the leaked task, liveness via `kill(pid, 0)`, no fabricated metrics); GitHub
  clients (gists / releases / notifications / orgs / issues, including
  `createRepository`, unported in Wave 10); 3 SwiftUI browser views; 2 test files.
- **Superseded (62).**
- **Honestly-unavailable (17):** interactive PTY terminal, Apple ID sign-in, IPA
  packaging, 7-file local workflow engine, others.
- **Skipped (1):** simulated demo view (`isSimulating`, fake logs).

### Views-D (167)

- **Adapted (29):** 12 new files in `swiftcode/Sources/swiftcode-ide/` (2,328 lines):
  skills library (real SKILL.md), backups (onto BackupEngine), external MCP
  servers (`~/.config/swiftcode/mcp-servers.json`), Ollama models (live API), code
  complexity, Markdown, branch graph, go-to-line, alternative keys, Composio
  settings, PR creation (onto GitHubClient), app permissions.
- **Superseded (116):** Assistant pane / Settings panes / navigators.
- **Honestly-unavailable (22):** realtime collaboration (12 — no backend),
  updater (2), sounds (2), other (6).
- **Wiring:** `SwiftCodeCloud` + `SwiftCodeGitHub` onto `swiftcode-ide` (see § Wiring).
- **Dependency note:** `BackupsSettingsView` depends on gap-closure's untracked
  `BackupEngine.swift` / `BackupModels.swift`.

### Core (124)

- **Adapted (61):** 63 new files (61 source + 2 tests). Whole 25-file simctl
  cluster, skills stack, preview models, build diagnostics.
- **Superseded (62).**
- **Honestly-unavailable (1).**
- **Fake-data removal:** canned simctl output with fake UDIDs, fabricated success
  output, `Double.random` performance metrics, two invented apps with made-up
  paths — all replaced with honest errors / empty states.
- **Collision flag (parent to resolve at integration):**
  `swiftcode/Sources/SwiftCodeAssistant/SkillIndex.swift` exists once on disk and is
  Core's documented port (header cites Legacy source + bulk TSV; has
  enable/disable + indexing). Gap-closure had also claimed a file at that path —
  confirm with gap-closure at integration whether its content is subsumed.

### Persistence-Services (126)

- **Adapted (87):** 68 new files. New targets `SwiftCodeConnect` (24 files — full
  Connect family + `LocalBuildService` + new seam `ConnectWorkspaceProvider.swift`)
  and `SwiftCodeCollaboration` (21 files — full Collaboration + Transfer family + new
  seam `CollaborationProject.swift`); SwiftCodeIDECore (9: `ProjectRegistryStore`,
  `ThemeStore`, `ProjectFolders`, `FileTemplateManager`, `ProjectZipImporter`,
  `LegacyProjectTemplates` (29 templates consolidated),
  `LegacyProjectTemplateManager`, `UnifiedLogger`, `DeploymentLogStore`);
  `SwiftCodeUI/Sound` (2: `SoundCatalog`, `SoundInstaller`); `swiftcode-ide/Color+Hex.swift`;
  `SwiftCodeGoogleAuth/AntigravityQuotaService.swift`;
  `SwiftCodeXcodebuild/IPABuildService.swift`; `SwiftCodeAssistant/LocalModelManager.swift`;
  `SwiftCodeGitHub/RepoPermManager.swift`; 7 test files.
- **Superseded (32):** each with SwiftCode equivalent in the TSV (e.g. `BookmarkStore`
  → `Session/Bookmarks.swift`; `BreakpointStore` → `Model/WorkspaceModel.swift`;
  `PreferencesStore` → `Model/Preferences.swift`; `OpenRouterService` → Wave 9
  OpenRouter provider; `SyntaxHighlighter` → SwiftCodeSyntax;
  `AgentCodeReviewManager` → `code_review` tool + `CodeReviewModel.swift` —
  Legacy's was a mock).
- **Honestly-unavailable (1):** `ProjectFilesExtracter` — needs SwiftCodeGitHub
  workflow-runs/artifacts API (not ported in Wave 10) plus Legacy's
  remote-generation backend.
- **Skipped (6):** `NewFileComment` (already covered — gap-closure/another worker);
  `AgentSkillManager` (Skills-slice dependency); `ComposioService` (already covered
  by gap-closure's `SwiftCodeTools+ComposioClient.swift`); `SoundManager` +
  `NotificationManager` (blocked on Audio slice `AlertTone`/`AlertSoundPlayer` +
  Models slice `AppSettings` sound IDs); `ToolbarSettings` (no destination consumer).
- **Honest rewrites:** `LocalBuildService` (Legacy returned `"Fake IPA Content"`
  after sleeps → real `URLSession` POST, decodes `BuildResponse`);
  `ConnectAssistService` (canned string → provider route, honest error when
  unconfigured); Connect Test/Terminal/Build services (Autopilot internals →
  provider seam / `Process`); `IPABuildService` (hardcoded
  `/Users/dylan/.../build_ipa.sh` removed); `ProjectTemplateEngine` (nested-path
  parent-dir fix).
- **Already committed:** `SwiftCodeIDECore/Model/ProjectRegistryStore.swift` is
  tracked in the gap-closure commit (`caec764`, also on remote main as `6deab9b`),
  byte-identical to the bulk file — it was scooped into that commit. The other 67
  Persistence files are untracked.
- **Dedupes/collisions:** `ProjectRegistryEntry`/`ProjectKind` vs Core slice
  (remove the bulk copy if Core lands its own); `ProjectFolder` also exists in
  `SwiftCodeIDEShell/ProjectDashboardModel.swift` with a different shape (Swift
  shadows per-module, so it builds — flagged in-file).
- **Security notes:** `PeerSessionManager` auto-accepts all invitations /
  certificates — gate on user approval + validate certificates before shipping.
  TrustStore: previously-trusted devices must re-pair once (new SecretStore
  account). Transfer packages written by Legacy do not decode (shape change).
- **Resources to land:** 35 `.aiff` sounds (review doc: PORT-AS-IS) + 20 File
  Templates `.txt` resources.

### Frameworks-Features (107)

- **Adapted (45):** 18 new files. Offline-models stack (HuggingFace client,
  downloader with resume, storage, manager — GGUF conversion throws honestly;
  large files buffer in memory); 16-manager `.scproj` format layer;
  code-intelligence engine; project notes/folders/snippets; Advanced Tools views.
- **Superseded (44):** 15 Legacy UI/Styling files (incl. `LiquidGlass`) superseded
  by `ShellStyle` + `GlassBars`.
- **Honestly-unavailable (5):** need MLX runtime or SFSymbol data.
- **Skipped (10).**
- **Missing (3):** `DocumentationBrowserView` (2,853 lines — Wave 19
  rewrite-from-spec), `ProjectNotesWorkspaceView`, `WorkspaceProfilesView`.
- **Security fix:** Legacy stored API keys in plaintext JSON in 4 places; the
  port uses SecretStore.

### Small-Clusters (72)

- **Adapted (26):** 31 new files. Real Codex API-key client (OpenAI Responses API,
  SecretStore keys, default `gpt-5-codex`; `streamResponse` honestly labelled
  typewriter replay, not a live stream); audio tone system; `GitHubOAuth` rewired
  to SecretStore; `DocumentationAnalyzer` honestly reworked (Legacy's extractor
  was a canned string).
- **Superseded (27).**
- **Honestly-unavailable (15):** incl. On Device Intelligence files (canned-text
  fakes in Legacy, not Apple Intelligence).
- **Skipped (4).**
- **Security notes:** Legacy's "KeychainService" never touched the Keychain
  (base64 in UserDefaults + plaintext JSON cache); Legacy's `supabaseAnonKey` fell
  back to a hardcoded JWT whose signature is literally `mock-key-signature`
  (gap-closure's AppConfig already fixed that).
- **Parent decision flagged:** the SPDX corpus is not in any target's bundle
  resources, so `LicenseCatalog` is empty until a resources entry is added.

## Files created (381 total, destination repo only, uncommitted unless noted)

| Slice | New files | Where |
|---|---|---|
| Backend-Assist | 4 (2 source + 2 tests) | `SwiftCodeAssistant/PromptEnhancer.swift`, `SwiftCodeMCP/CIBuildYAML.swift` + tests |
| Views-A | 16 | `swiftcode/Sources/swiftcode-ide/` (6 model+view pairs + share-sheet presenter) |
| Views-B | 152 | `swiftcode/Sources/swiftcode-ide/DevTools/` (141) + `Developer/` (11) |
| Views-C | 17 | `DeviceConnect*`, GitHub clients, 3 browser views, 2 tests |
| Views-D | 12 | `swiftcode/Sources/swiftcode-ide/` |
| Core | 63 (61 source + 2 tests) | simctl cluster, skills stack, preview models, build diagnostics |
| Persistence-Services | 68 (61 source + 7 tests) | `SwiftCodeConnect` (24), `SwiftCodeCollaboration` (21), SwiftCodeIDECore (9), misc (7), tests (7) |
| Frameworks-Features | 18 | offline-models stack, `.scproj` layer, code-intelligence, notes/snippets |
| Small-Clusters | 31 | Codex client, audio tone system, GitHubOAuth, DocumentationAnalyzer |

One file is already committed: `SwiftCodeIDECore/Model/ProjectRegistryStore.swift`
(in gap-closure commit `caec764` / remote main `6deab9b`, byte-identical to the bulk
file). The remaining 380 are untracked. No existing destination file was modified
by this wave except through that gap-closure commit; bulk workers created new files
only.

## Package.swift wiring needed (list, not edits)

1. New library product + target `SwiftCodeConnect`, macOS-only (Network; inside the
   existing `#if os(macOS)` block), deps `["SwiftCodeAssistant"]`.
2. New library product + target `SwiftCodeCollaboration`, macOS-only
   (MultipeerConnectivity; same block), deps
   `[.product(name: "Crypto", package: "swift-crypto")]` (mirror SwiftCodeIDECore's
   CryptoKit precedent).
3. New test targets `SwiftCodeConnectTests` (`SwiftCodeConnect`) and
   `SwiftCodeCollaborationTests` (`SwiftCodeCollaboration`), macOS-only.
4. Add `"SwiftCodeConnect"` + `"SwiftCodeCollaboration"` to SwiftCodeUI's target dependencies.
5. Views-D: add `SwiftCodeCloud` + `SwiftCodeGitHub` to `swiftcode-ide`'s target dependencies.
6. No changes needed for SwiftCodeIDECore / SwiftCodeGitHub / SwiftCodeGoogleAuth /
   SwiftCodeAssistant / SwiftCodeXcodebuild / swiftcode-ide (Persistence-Services items), and
   no other slice reported Package.swift wiring.

## Wiring / integration list

- Connect shell: set `ConnectServer.shared.workspaceProvider` from the open
  `WorkspaceSession` (git via `ConnectLocalGit`, builds/tests via SwiftCodeBuild,
  assist via CodingAssistantModel, devices via Device Hub/simctl); until then
  Connect honestly answers NO_ACTIVE_PROJECT.
- NewProject flow: `LegacyProjectTemplateManager` + `LegacyProjectTemplates` +
  `ProjectZipImporter`.
- Settings: `ThemeStore`, `SoundCatalog`/`SoundInstaller`,
  `AntigravityQuotaService`, `RepoPermManager` (pass GitHubClient's tokenProvider).
- Deploy UI: `DeploymentLogStore`. Library sidebar: `ProjectFolders`.
- Views-B: DevTools views need a hub + menu entry to be reachable.
- Views-D: `BackupsSettingsView` depends on gap-closure's untracked
  `BackupEngine.swift` / `BackupModels.swift`.
- Resources to land: 35 `.aiff` sounds + 20 File Templates `.txt` resources
  (Persistence-Services); SPDX corpus resources entry for `LicenseCatalog`
  (parent decision).

## Static checks

- Delimiter balance: checked per slice on every created file; imbalances flagged
  during the wave were all string-literal false positives on re-check (stripped
  depth 0), except none remain open. Persistence-Services: 68/68 balanced
  (re-verified by coordinator with a string/comment-aware scanner; the
  coordinator's 79-file glob also covered neighbouring `NewProject/` files — all
  balanced).
- Secrets: `python3 -I .github/scripts/scan-public.py` — 0 findings on 4,979
  tracked files (coordinator re-run). Per-slice secret scans on the new files: 0
  findings. No real API key, token, or secret was written anywhere.
- TODO/FIXME in new files: none (Persistence-Services re-verified).
- Node test suites: no Node changes in this wave; prior suites (115/115) untouched.
- **Not verified:** no Swift build or test was run — no Swift toolchain in this
  environment, per Dylan's instruction. All test files (2 Backend-Assist, 2 Core,
  2 Views-C, 7 Persistence-Services, plus any others listed per slice) are
  unexecuted. The two new targets (`SwiftCodeConnect`, `SwiftCodeCollaboration`) are not
  yet in Package.swift, so nothing here has compiled.

## What is still pending / remainder

- **Genuinely-missing, not adapted (3):** `DocumentationBrowserView` (2,853
  lines — Wave 19 rewrite-from-spec), `ProjectNotesWorkspaceView`,
  `WorkspaceProfilesView` (Frameworks-Features).
- **Skipped rewrites (142):** notably Views-B's 25 (Battery/CPU/FPS monitors,
  QR/barcode generators, etc.), Views-A's 91 (mostly gap-closure-owned rows:
  54 Database, 30 VisualUIBuilder/Artboards), Persistence-Services' 6 (incl.
  `SoundManager`/`NotificationManager` blocked on the Audio + Models slices).
- **Honestly-unavailable blocks (178):** worker runtime (20), REA reverse backend
  (5), MLX runtime, Virtualization backend (42 Views-B views), realtime
  collaboration (12), updater, interactive PTY terminal, Apple ID sign-in, IPA
  packaging, local workflow engine, On Device Intelligence (canned-text fakes),
  Autopilot/autonomous takeover (excluded by design), System Assets corpus (Wave
  19), `ProjectFilesExtracter` (needs SwiftCodeGitHub workflow-runs/artifacts API).
- **Wave 19 (REVIEW execution):** Documentation Assets rewrite-from-spec +
  System Assets re-derivation; the 5 missing example commands (Wave 15 ships 2/7).
- **Rebrand SwiftCode→SwiftCode** (scout still running at wave start), README V2
  parity, destination ledgers, final 12 audits + destination cleanup audit.
- **Mac verification for everything in this wave:** `swift build` / `swift test`
  + live runs on Dylan's Mac; nothing is VERIFIED until then.
- **Dylan-supplied items (unchanged):** SCCloud endpoint URL; OpenRouter API key;
  GitHub PAT; `opencode serve` / `hermes setup`; Node on the Mac; Google OAuth
  client secret; three App Store Connect products + signed build; Gemini /
  Anthropic / OpenAI / Mistral / Qwen API keys; real sync backend decision; AFM
  context-window disagreement (8,192 vs 16,000) needs a Mac check.

## Evidence

- Staging input: `~/SwiftCode-Migration-Workspace/staging-bulk/MANIFEST.tsv`
  (1,428 files) and `~/SwiftCode-Migration-Workspace/staging-bulk/` copies.
- Disposition TSVs: `~/SwiftCode-Migration-Workspace/bulk/*-dispositions.tsv`
  (9 files; per-TSV counts verified by coordinator with `awk`: 145 + 271 + 240 +
  176 + 167 + 124 + 126 + 107 + 72 = 1,428; disposition sums 602 / 503 / 178 /
  142 / 3).
- Destination HEAD at verification: local `caec764` (gap-closure wave), remote
  main `6deab9b` (same gap-closure wave, pushed by parent); Wave 18 remote was
  `d3cf4934`. The bulk wave created new files only and did not commit or push.
- Secret scan: `python3 -I .github/scripts/scan-public.py` → "Scanned 4979
  tracked files: 0 findings."
- Per-slice verification: each worker's final report was checked by the
  coordinator against its TSV counts and created files; Persistence-Services was
  re-verified file-by-file in the final turn (68 files present, delimiters
  balanced, TSV 87/32/6/1).
- Clean-room: implementation reads only `specs/`, public docs, and Dylan's own
  code (direct porting authorised by Dylan under MIT); no worker opened
  `research/dirty/`, Ghidra, the Xcode copy/IPSW, or observed Apple's
  Xcode/Simulator. No Swift toolchain command was run in this wave.
