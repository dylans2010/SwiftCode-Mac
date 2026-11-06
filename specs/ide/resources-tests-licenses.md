# Wave 18 — Resources, Tests, Licenses (bulk migration)

Migration wave 18 of the SwiftCode Legacy → Mac migration. Bulk categories
from `~/SwiftCode-Migration-Workspace/manifests/classification_legacy.csv`,
all verified live from the CSV (counts are not from memory).

| Category | CSV rows | Placed / ported | Deduped / already present | Skipped |
|---|---|---|---|---|
| `RESOURCE_MIGRATION` | 715 | 3 newly placed | 12 already present, byte-identical; 3 diverged, deliberately not overwritten | 697 |
| `TEST_MIGRATION` | 34 | 26 IMPLEMENTED (18 new tests in 5 files; rest already ported in Waves 1–16) | — | 8 |
| `PRESERVE_LICENSE_OR_ATTRIBUTION` | 820 | 780 placed | 40 deduped | 0 |

MCP tool count unchanged at 433. No `swiftcode/Package.swift` changes in this
wave. No commits or pushes by this wave; the parent integrates, verifies,
commits and pushes.

## 1. Resources (715)

### Placed (3, verbatim, sha256-verified against the CSV)

All three live in `sdk/`, outside the Swift package, so no SwiftPM wiring
was needed:

- `SwiftCode/SDK/TypeScript/cli/package-lock.json` → `sdk/cli/package-lock.json`
- `SwiftCode/SDK/TypeScript/package/package-lock.json` → `sdk/package/package-lock.json`
- `SwiftCode/SDK/TypeScript/runtime-adapter/package-lock.json` → `sdk/runtime-adapter/package-lock.json`

Caveat: lockfile resolvability was NOT validated by an `npm ci` /
`npm install` run — no registry install was attempted here.

### Already present, byte-identical (12 — no action, not claimed as this wave)

SDK files placed by the Wave 14/15 SDK work: the example manifest, the
standalone-swift `template.json`, and the `package.json` / `snippets.json` /
`tsconfig.json` / `swiftcode.json` files under `sdk/cli`, `sdk/package`,
`sdk/runtime-adapter`, and `sdk/templates/`.

### Already present but diverged — deliberately NOT overwritten (3)

- `sdk/Contracts/Manifest/swiftcode-extension-v1.schema.json` — content
  identical except doc-path rewording (`Docs/Intro-to-SDK.md` →
  `specs/ide/sdk-platform.md`, `SwiftCode/SDK/Documentation/` → `sdk/docs/`).
- `sdk/runtime-adapter/package.json` — same, doc-path rewording only.
- `swiftcode/Sources/SwiftCodeSDK/Resources/SwiftCodeSDK.json` — same keys, same
  `sdkVersion` 1.2.0, but Legacy's `releaseNotes` is a JSON **list** while
  the destination's is a **dict**. `SDKConfigStore.swift:19` decodes
  `releaseNotes: [String: String]` — copying Legacy's file would break
  decoding. The destination dict form is the correct one; do not
  "reconcile" it toward Legacy.

### Skipped (697, grouped)

1. **477 — `SwiftCode/Assets.xcassets/**`**: consumer is Legacy
   `AppIconManager` (alternate app icons, Settings). No `AppIconManager` /
   alternate-icon feature exists anywhere in the destination. SwiftCode's app
   icon is `packaging/icon/SwiftCode.icns` via `packaging/macos/Info.plist.in`.
   Placing the catalog in `SwiftCodeApp/Resources/` would be inert (nothing
   references it). All Legacy-branded; if the feature is ever ported, these
   need the rebrand wave first.
2. **203 — `SwiftCode/Resources/Documentation Assets/**`**: offline docs
   bundle consumed only by Legacy `DocumentationBrowserView`, which is not
   ported. Includes `DeveloperDocumentation.doccarchive/` (68 files),
   `XcodeFrameworks/` (67 files: `CoreDocumentation.framework`,
   `IDEDocViewer.framework`, `IDEDocumentation.framework` resources), and
   68 loose doccarchive-root files. Additional blocker:
   `XcodeFrameworks/*` and `apple-logo.svg` are Apple Xcode framework
   resources / Apple artwork — copying them into `swiftcode/` would violate the
   destination `AGENTS.md` clean-room rules 1 and 5 (no copied Apple
   resources, no Apple trademarks/artwork).
3. **5 — `SwiftCode/SDK/Examples/RepositoryBuildExtension/*`**: deliberate
   non-ship decision. `SDKExampleManager.swift` and
   `specs/ide/sdk-platform.md` §25 record the example files as spec
   reference material only ("SwiftCode ships no bundled example project"); the
   example identity is carried in code and instantiated from
   `sdk/templates/extension-typescript`.
4. **5 — `SwiftCode/Resources/Themes/*.json`** (`MidnightTerminal`, `Paper`,
   `SolarFlare`, `SwiftCodeDark`, `SwiftCodeLight`): Legacy theme schema
   (`id/name/background/foreground/keywordColor/stringColor/commentColor/
   numberColor/typeColor/accentColor/isBuiltIn`) is incompatible with SwiftCode
   `EditorTheme` (`.swiftcodetheme`: requires `fontName`, `fontSize`, `tokens`
   map, `consoleFontName`, `consoleFontSize`, etc.); the destination has no
   bundled-theme loader (built-ins hardcoded, user themes load from a user
   directory as `.swiftcodetheme`). A verbatim copy would be inert; converting
   schemas is out of scope for a copy-exact wave.
5. **1 — `SwiftCode/Resources/DocSymbols.json`**: consumed only by Legacy
   `DocumentationBrowserView` (not ported).
6. **1 — `SwiftCode/Resources/sf_symbols_full.json`**: consumed only by
   Legacy `SFSymbolBrowserView` (not ported); destination `symbols.browse`
   opens via `SDKViewHostRegistry` with no JSON loader.
7. **1 — `SwiftCode/Resources/Codex/Bridge/package.json`**: companion
   `bridge.js` is not in this slice and consumer `CodexBridgeManager` is
   not ported; the file alone is useless.
8. **1 — `SwiftCode/Resources/SCProjDocumentIcon.icns`**: referenced only
   by Legacy `Info.plist` `CFBundleTypeIconFile` for
   `com.swiftcode.project`; destination `packaging/macos/Info.plist.in`
   registers no `.scproj` document type.
9. **1 — `SwiftCode/Resources/SwiftCode.entitlements`**: `packaging/README.md`
   states the app has hardened runtime and **no entitlements** — a
   deliberate destination decision; entitlements are not SwiftPM resources
   anyway.
10. **1 — `SwiftCode/Info.plist`**: superseded by
    `packaging/macos/Info.plist.in`; a SwiftPM executable target consumes
    no `Info.plist` resource.
11. **1 — `skills-lock.json`** (repo root): pins a Composio skill; the
    destination has no `skills/` dir and no Composio service
    (`use_composio` is honestly-failing).

### Package.swift changes needed from resources

None. Nothing was placed into any `swiftcode/Sources/*/Resources/` dir. (If
the skipped icon/theme/docs subsystems are ported later, their resource
wiring will need deciding then — including whether `.xcassets` belongs in
`SwiftCodeApp/Resources/` with an explicit `resources:` declaration.)

## 2. Tests (34)

### Outcome: 26 IMPLEMENTED, 8 SKIPPED

Most of the 34 were **already ported by Waves 1–16** under new names —
verified test-by-test against the live SwiftCode tree, not by trusting the CSV
(whose statuses are all stale `NOT STARTED`). Where a file was only partly
covered, the genuinely missing, portable assertions were ported as new
tests: **18 new tests in 5 new files**, all in existing test targets.

New files (destination only, uncommitted):

- `swiftcode/Tests/SwiftCodeMCPTests/LegacyReverseGapTests.swift` — 5
  swift-testing tests: Reverse allow-list (exactly 11 ops, no forbidden
  execution surface), objdump sub-ops (7), target validator direct checks
  (system path / traversal / relative / nil rejected; in-scope file
  accepted), disclaimer refusal (DRM + license-check refused, legitimate
  task allowed).
- `swiftcode/Tests/SwiftCodeSDKTests/LegacySDKGapTests.swift` — 2 XCTest: keyless
  cloud-model caller keeps the grant path → `.permissionDenied`; all 32
  Legacy canonical capability ids parse as `SDKCapabilityID` (SwiftCode adds
  `assist.main`, asserted as a lower bound).
- `swiftcode/Tests/SwiftCodeSDKTests/LegacySDKInstallerGapTests.swift` — 6 XCTest:
  inspect corrupt when version/name missing; install succeeds with a stub
  npm only after verification; install fails when stub npm exits 0 but
  writes nothing; install fails honestly when stub npm exits non-zero even
  though it wrote files (real error text preserved in log); install falls
  back to the bundled copy when GitHub is unreachable.
- `swiftcode/Tests/SwiftCodeAssistantTests/LegacyAssistGapTests.swift` — 4
  swift-testing tests: `HermesConfiguration.normalisedToolsets`
  (whitespace-only → nil); `AssistantSettings.provider = .openCode` JSON
  round-trip; explicit Claude/GPT SDK configs never use Antigravity/Gemini;
  failover after a Claude failure attributes to the Claude model and picks
  the other Claude candidate, never the eligible Gemini candidate.
- `swiftcode/Tests/SwiftCodeGitHubTests/LegacyGitHubRepoGapTests.swift` — 1
  swift-testing test: `GitHubRepoReference.parse` accepts valid
  owner/repo characters (`org_1.2` / `r-e_p.o`).

IMPLEMENTED rows (26): `GoogleCloudSDKTests.swift` (partial — auth/error-
classification/routing intents covered by `SwiftCodeGoogleAuthTests` +
`AntigravitySDKCatalogTests` + `AssistModelRoutingTests`; 12
runtime/bridge/process/session checks skipped, no SwiftCode type),
`AssistModelRouterTests.swift` (18/21 covered; 3 gap tests added),
`AssistProviderTests.swift` (7.5/8; 1 gap test),
`HermesProviderTests.swift` (7/10; locator covered by `CLIAgentTests`;
1 gap test), `ExtV2TestSuite.swift` (11/14; 3 `use_extension` checks
skipped — tool intentionally unwired in SwiftCode),
`SDKAssistApplicationTests.swift` (covered + extended by Wave 15: 11
Legacy → 14 SwiftCode tests), `SDKAssistEnforcementTests.swift` (14/16; "no
key" case = unentitled-key case per the file's own deviation note; 1 gap
test), `SDKInstallerTests.swift` (partial: 8 existing + 6 gap tests; 2
real-tarball/network tests skipped), `SDKTestRunner/main.swift` (all 7
checks live in `SwiftCodeSDKTests`; canonical caps added),
`SDKTests/SDKTests.swift` (5/5), `ReverseTests.swift` (partial: 3/11
checks ported; rest skipped, see below),
`AssistDocsGitHubToolsTestSuite.swift` (15/17; 1 gap test), and all 13
TypeScript test files (11 in `sdk/package/tests/` — incl.
`scopes-sync` extended 4 → 7 its with the `validate.mjs` pin — plus
`extension.test.mjs` / `manifest.test.mjs` / `hello.test.mjs` in the
templates; several byte-identical).

SKIPPED rows (8):

- **Production type not ported in Waves 1–16** (test would assert behaviour
  the destination does not have): `AssistRuntimeTestSuite.swift` (40 own
  tests on `AssistAgentSession` / `AssistToolRegistry` / `AssistFileSystem` /
  workers / goals / notes — superseded by the MCP host + MetaAssist
  executor, whose behaviour is covered by `SwiftCodeMCPTests` /
  `SwiftCodeAssistantTests`); `SDKProviderTests.swift` (all 8; no
  `AssistSDKSessionRunner` / `SDKToolEventStore` / `SDKToolSourceSetting`
  in SwiftCode); `SystemIndexTestSuite.swift` (no `SystemIndexService` by
  design — stated in `MetaAssistTurnExecutor.swift`);
  `AppUpdateSupportTests.swift` (no `AppUpdateSupport` /
  `ReleaseNotesFormatter` / `RemindLaterGate` in SwiftCode).
- **Misclassified rows — production helpers, not tests:**
  `TestCoverageManager.swift` (fabricates coverage from a filename hash,
  `getRealLineCount` returns placeholder 100 — porting it would enshrine
  fake coverage); `TestTools.swift` (in-app test-runner manager that
  simulates extension test results).
- **Example extension not ported:**
  `RepositoryBuildExtension/tests/extension.test.mjs` and
  `.../manifest.test.mjs` (only the example's manifest survives, as a
  `SwiftCodeSDKTests` fixture).

### Package.swift changes needed from tests

None. All new tests are in existing test targets (`SwiftCodeMCPTests`,
`SwiftCodeSDKTests`, `SwiftCodeAssistantTests`, `SwiftCodeGitHubTests`).

### Pending (Mac build/test)

Build + run the 5 new files on Dylan's Mac: `swift test --filter
LegacyReverseGapTests`, `--filter LegacySDKGapTests`, `--filter
LegacySDKInstallerGapTests`, `--filter LegacyAssistGapTests`,
`--filter LegacyGitHubRepoGapTests`. Notes: installer gap tests spawn
stub `/bin/sh` scripts as fake npm (fine on macOS); the keyless
enforcement test only reads the shared grant store (fresh UUID extension,
creates nothing). The unported remainder can only be migrated if/when the
corresponding production code is ported (Reverse `@Reverse` parser + JSON
bridge, Google Cloud SDK runtime, SystemIndex, SDK provider types,
AppUpdateSupport, Assist runtime internals, `use_extension` wiring,
RepositoryBuildExtension example) — each is a production-code decision
for a future wave, not a test-only task.

## 3. Licenses (820)

The whole set is the SPDX license-text corpus that lived at
`SwiftCode/Backend/Licenses/` in Legacy — 819 `.txt` texts plus
`LicenseCatalog.swift`, the loader that discovers them from the app
bundle. Placed into the destination's existing attribution setup as a
subdirectory, `packaging/licenses/spdx/`, rather than flat into
`packaging/licenses/` (which holds the 10 component license texts the
generator references) and rather than a second competing directory. A
`README.md` in `spdx/` documents provenance, the dedup policy, and the
generator relationship. No license text was modified, reworded, or
truncated — all copies are byte-for-byte.

| Outcome | Count |
|---|---|
| Placed (new files) | 780 (779 unique `.txt` texts + `LicenseCatalog.swift`) |
| Deduped (not written as duplicates) | 40 (byte-identical to another Legacy file in the set — 15 content groups) |
| Skipped for any other reason | 0 |
| Collisions with existing `packaging/licenses/` files | 0 (no Legacy hash matches any of the 10 existing files; no basename collisions, checked case-insensitively too) |

Dedup: keeper rule is the alphabetically first Legacy filename in each
group. Full table in
`~/SwiftCode-Migration-Workspace/wave18/deduped.tsv` (and the placed list
in `placed.tsv`, ledger rows in `ledger-rows.tsv`). Groups include the
`deprecated_*` / `-or-later` variants collapsing into their `-only`
counterparts (e.g. `GPL-3.0-or-later`, `deprecated_GPL-3.0` →
`GPL-3.0-only`), the GFDL invariant variants, and the OFL RFN variants.

sha256 verification (fully scripted, no spot-checking): before copying,
all 820 Legacy files re-hashed live — 820/820 matched the CSV (hash and
size), 0 missing. After copying, every placed file re-hashed from the
destination disk — 780/780 matched.

Generator / `THIRD_PARTY_NOTICES.md`: no generator change needed, no
regeneration pending. `packaging/generate-notices.py`'s `COMPONENTS` list
covers third-party components SwiftCode ships/links. The SPDX corpus is
license *templates* a user adds to their own project, not a shipped
component, so it is deliberately not a `COMPONENTS` entry and does not
change `THIRD_PARTY_NOTICES.md`. The generated file was not hand-edited.

### Pending / caveats (licenses)

1. **Corpus not wired into any SwiftPM target yet.**
   `LicenseCatalog.swift` loads `.txt` files from `Bundle.main` resources;
   the texts currently sit in `packaging/` (not a target resource dir) and
   `swiftcode/Package.swift` was off-limits in this wave. The wave that ports
   `LicencesAddView` (MIGRATE_AND_ADAPT) must wire the corpus in as a
   target resource and adapt the catalog — the preserved catalog is in
   `packaging/licenses/spdx/LicenseCatalog.swift`, unadapted by design.
   This is the one genuine Package.swift item from Wave 18 (as a list
   entry for the parent, not an edit): *add the SPDX corpus as a resource
   of the target that will host the licences UI, and adapt
   `LicenseCatalog.swift` to load from that bundle*.
2. **Dedup loses 40 SPDX IDs.** A catalog port that looks templates up by
   filename stem will see only the keeper ID per group (e.g.
   `GPL-3.0-or-later` and `deprecated_GPL-3.0` collapse into
   `GPL-3.0-only`). If per-ID lookup matters, the follow-up wave should
   restore the 40 deduped names as copies/symlinks or teach the catalog
   the alias mapping (dedup table above + `deduped.tsv`).
3. **Nothing was compiled or run.** The corpus is data, not code; no build
   verification applies. The preserved `LicenseCatalog.swift` was not
   compiled (it is outside any target) — its adaptation/verification
   belongs to the porting wave.

## Static-check results (coordinator-verified)

- `python3 -I .github/scripts/scan-public.py`: **0 findings** (4,126
  tracked files).
- Node suite re-run by the coordinator post-merge: **115/115 pass, 0 fail**
  (`sdk/package`, `node --test "tests/*.test.mjs"`).
- New Swift test files: delimiters balanced, no TODO/FIXME, no secrets
  (coordinator re-checked all 5 files).
- Coordinator re-verified independently: all 715 RESOURCE_MIGRATION rows
  hash-match in Legacy; group counts reconcile exactly (477 xcassets +
  203 doc assets + 5 themes + 5 examples + 25 other = 715); the
  `SwiftCodeSDK.json` list-vs-dict divergence confirmed; licenses 5/5
  spot-check SHA-256 matches + GPL dedup group confirmed byte-identical
  in Legacy; tests ledger list covers all 34 CSV rows exactly (26 + 8,
  no gaps, no extras).
- Legacy clean @ `d51a8f0d`; SwiftCode-New untouched; remote main still
  `ec353a4f`. No Swift toolchain here — Mac `swift build` / `swift test`
  pending on Dylan's Mac for the 5 new test files (and for the
  `LicenseCatalog.swift` adaptation when it is ported).

## Evidence

- Classification: `~/SwiftCode-Migration-Workspace/manifests/classification_legacy.csv`
  (RESOURCE_MIGRATION 715, TEST_MIGRATION 34,
  PRESERVE_LICENSE_OR_ATTRIBUTION 820 — all verified live by count).
- Licenses placed list / dedup table / ledger rows:
  `~/SwiftCode-Migration-Workspace/wave18/{placed,deduped,ledger-rows}.tsv`.
- This spec: `specs/ide/resources-tests-licenses.md`.
