# Wave 19 slice E — Resources remainder + SPDX wiring

Status: staged for the parent to apply. Nothing in this slice writes to
the destination repo: all files live under
`staging-wave19/resources/`, mirroring their destination paths, plus the
two adapted Swift files and this spec. The parent applies them (copy
files, apply the adapted Swift files, add the two `Package.swift`
resources entries listed in `INTEGRATION.md`), then flips the ledger
rows listed there.

## 1. Sounds — Legacy's 57 `.aiff` files

Source: `SwiftCode/Resources/Sounds/` in Legacy (read-only,
`d51a8f0d`). All 57 files staged byte-for-byte at
`swiftcode/Sources/SwiftCodeUI/Resources/Sounds/`, filenames preserved
(REVIEW scout disposition: PORT-AS-IS).

Counts, corrected: the bulk wave's remainder note said "35 .aiff".
The true count is **57 files, 32 distinct audio contents**. The
destination's `SoundCatalog` lists 32 custom sounds, each with a clean
`filename` (`Soft Bloom.aiff`) and a `legacyFilename`
(`SwiftCode_Chill_SoftBloom.aiff`); Legacy's own `SoundCatalog`
references exactly those 32 legacy names. The other 25 files
(`Notification_A`–`H`, `Message_A`–`E`, `Success_A`–`D`,
`Complete_A`–`D`, `Error_A`/`B`/`C`, `Warning_A`) are byte-identical
duplicates of the 32 (sha256-verified: 32 distinct hashes across 57
files, e.g. `SwiftCode_Notification_A.aiff` ==
`SwiftCode_Chill_SoftBloom.aiff`). They are staged anyway: the ledger
is one row per file, the REVIEW scout says PORT-AS-IS with filenames
preserved, and Legacy shipped all 57 names. Dropping the 25 duplicates
is a parent decision for later, not this slice's to make unilaterally.

Verification: every staged file starts with `FORM` + `AIFF`/`AIFC`
magic (57/57), and every staged sha256 matches its Legacy source
(57/57).

Wiring: `Package.swift`, SwiftCodeUI target, add
`resources: [.copy("Resources/Sounds")]` (exact anchor in
`INTEGRATION.md`). This makes two existing lookups work:

- `AppSound.devRepoURL` already resolves to
  `swiftcode/Sources/SwiftCodeUI/Resources/Sounds/<name>` from the
  source tree (it computes the path from `#filePath`), so the staged
  layout is exactly the path that fallback expects.
- `AppSound.bundleURL` did not work for SwiftPM-bundled resources:
  it only checked `Bundle.main`, and SwiftPM puts target resources in
  the target's module bundle. The staged `SoundCatalog.swift` adds a
  `Bundle.module` lookup (subdirectory `Sounds`, then root) ahead of
  the `Bundle.main` checks and updates the stale header note (which
  said "35 custom .aiff resources are not in this repo yet"). Nothing
  else in the file changed (10 changed lines total). `SoundInstaller`
  needs no change: it installs through `SoundCatalog.resolvedURL`.

## 2. File Templates — Legacy's 20 `.txt` files

Source: `SwiftCode/Resources/File Templates/` in Legacy. All 20 staged
byte-for-byte (verified UTF-8, non-empty, real template bodies — no
placeholders) at the proposed path
`swiftcode/Sources/SwiftCodeIDECore/Resources/File Templates/`.

There is **no file-based File Templates area in the destination**.
Templates live as hardcoded Swift strings: `FileTemplate` (6 cases) and
`FileTemplateCatalog`/`TemplateContents` in
`swiftcode/Sources/SwiftCodeIDECore/Model/Templates.swift` and
`TemplateContents.swift`. `TemplateEntry.files(named:)` returns an
empty file for every catalog entry that has no `fileTemplate` and no
`TemplateContents` case. So the staged `.txt` files have no runtime
reader today.

Content comparison (Legacy body vs destination's hardcoded content):

- 19 of 20 bodies are **not** present in the destination: SwiftUI
  (fixed `ContentView` with globe vs the destination's
  name-parameterised minimal view), UIKit, AppKit, SwiftActor,
  CFile (a `main()` program vs a stub function), UnitTest (full
  `XCTestCase` with temp-dir setUp/tearDown), Storyboard (a full scene
  vs the destination's empty `<scenes/>`), ShellScript, Markdown,
  README_Template, HTML, CSS, JSON, JavaScript, PythonScript,
  Configuration (a GitHub Actions YAML — the destination's
  "Configuration Settings File" is an xcconfig comment, a different
  kind), Entitlements, InfoPlist (full build-settings plist vs an
  empty-dict plist), PackageSwift.
- 1 of 20 is effectively covered: `XCTestUnitTest.swift.txt`
  (`MyTests` / `testExample`) matches the destination's parameterised
  "XCTest Unit Test" case modulo the class name.

Consequence: the staged files are **reference/source material, NOT
bundle resources**. Do NOT add them to any `Package.swift` resources
entry: nothing reads them at runtime (dead bundle weight), and any
`.txt` that ever landed in `Bundle.main` would be ingested as a
"license" by `LicenseCatalog`'s main-bundle scan (see §3). The live
follow-up is a code task, not a file placement: fold the 19 bodies
into `TemplateContents.swift` as new cases (or add the missing catalog
entries). That is remainder work for the parent, listed in
`INTEGRATION.md`.

## 3. SPDX wiring — corpus already in the repo, now wired

The corpus is already in the destination at
`packaging/licenses/spdx/` (Wave 18): **779 `.txt` files** (one per
unique content hash) + Legacy's original `LicenseCatalog.swift`
(preserved as-is, not adapted — its README says "Do not edit this
file in place") + a provenance `README.md`. The 780th Wave 18
"placed" row is that `LicenseCatalog.swift` file, not a license text.

Wiring needs the files under the owning target (SwiftPM resources
must live inside the target directory), so the 779 `.txt` files are
staged as a second copy at
`swiftcode/Sources/SwiftCodeIDECore/Resources/Licenses/`
(sha256-verified 779/779 against `packaging/licenses/spdx/`). The
canonical store stays `packaging/licenses/spdx/`; the target copy is
the build input. The texts are static SPDX license texts and do not
change, so the two copies do not drift in practice.

`Package.swift`, SwiftCodeIDECore target, add
`resources: [.copy("Resources/Licenses")]` (exact anchor in
`INTEGRATION.md`).

The staged `LicenseCatalog.swift` (adapted from the current
`swiftcode/Sources/SwiftCodeIDECore/Utilities/LicenseCatalog.swift`,
109 changed lines) makes three changes and nothing else:

1. The bundle path now also searches `Bundle.module` with
   subdirectory `"Licenses"` (the SwiftPM module-bundle location),
   keeping the `Bundle.main` path first (Legacy behaviour). URLs are
   deduplicated; IDs are deduplicated first-wins (main before module).
2. Dedup aliases: a static 40-entry map (deduped ID stem → keeper
   ID stem), generated from `wave18/deduped.tsv`, not hand-typed.
   Each deduped ID is re-issued under its own ID with its keeper's
   body/name/category/summary, so `licenseBody(for:)` serves all 819
   Legacy IDs (779 discovered + 40 aliased). No text is invented:
   every alias shares its keeper's body byte-for-byte (sha256-verified
   40/40). Aliases apply to the bundle path only, never to an explicit
   directory — the `loadTemplates(directory:)` test seam is untouched,
   so the existing `LicenseCatalogTests` (fixture counts, names,
   categories, sorting, empty dir) still hold by construction.
3. Doc comment updated to the wiring status.

The 40 deduped IDs collapse onto 15 keeper files (e.g.
`GPL-3.0-only` covers `GPL-3.0-or-later` and `deprecated_GPL-3.0`;
`GFDL-1.1-invariants-only` covers five variants). The full mapping is
in `INTEGRATION.md` §4.

Still missing (not this slice): `LicencesAddView` does not exist in
the destination and **nothing calls `LicenseCatalog`** (no consumers
in `swiftcode/Sources/`). Wiring makes the catalogue populate; the
view is follow-up work. Until a view exists, `cachedTemplates` is
populated but unread.

Interaction warning: `LicenseCatalog`'s `Bundle.main` scan ingests
*every* `.txt` in the main bundle except `sfsymbol*` files. Never put
non-license `.txt` files (notably the File Templates in §2) into any
target whose resources land in `Bundle.main`, or they will appear as
"licenses". The `Resources/Licenses/` module-bundle path is immune
(it is scoped to subdirectory `"Licenses"`).

## 4. Apply order (parent)

1. Copy the staged trees into the repo at their mirrored paths
   (sounds, templates, SPDX copy).
2. Replace `swiftcode/Sources/SwiftCodeIDECore/Utilities/LicenseCatalog.swift`
   with the staged adapted file, and
   `swiftcode/Sources/SwiftCodeUI/Sound/SoundCatalog.swift` with the
   staged adapted file.
3. Add the two `Package.swift` resources entries from
   `INTEGRATION.md` §2 (no other `Package.swift` change).
4. Flip the ledger rows in `INTEGRATION.md` §3–§4.
5. Run `python3 -I .github/scripts/scan-public.py` after applying
   (not run here: the staged files are not tracked yet).

## Evidence

- Legacy sounds: `SwiftCode/Resources/Sounds/`, 57 files, 7.6 MB;
  sha256: 32 distinct hashes; AIFF magic verified 57/57 with
  `python3 -I` (FORM + AIFF/AIFC header). Legacy's own
  `SwiftCode/Services/SoundCatalog.swift` references exactly the 32
  canonical legacy filenames (verified by grep); the destination's
  `SoundCatalog.swift` references the same 32 as `legacyFilename`.
  REVIEW scout disposition PORT-AS-IS for all 57
  (`audit/review-required-decisions.md:121`).
- Legacy templates: `SwiftCode/Resources/File Templates/`, 20 files;
  all read in full (real bodies, listed in §2); destination template
  system read in full (`Model/Templates.swift`,
  `Model/TemplateContents.swift`, `Model/FileTemplateManager.swift` —
  hardcoded strings, no file loading). Content comparison done
  entry-by-entry against `TemplateContents.files(_:name:platform:)`.
- SPDX corpus: `packaging/licenses/spdx/` on disk (779 `.txt` +
  `LicenseCatalog.swift` + `README.md`); `wave18/placed.tsv` (780
  rows: 779 `.txt` + `LicenseCatalog.swift`); `wave18/deduped.tsv`
  (40 rows); keeper hashes re-verified 40/40 against disk with
  `python3 -I` + sha256. Ledger cross-check: all 820 license rows
  read; the 780 placed rows match `placed.tsv` and disk exactly; the
  40 deduped rows all claim IMPLEMENTED at same-name destinations
  that do not exist (Wave 18 ledger error, corrected in
  `INTEGRATION.md` §4).
- Wiring: `swiftcode/Package.swift` target blocks read
  (SwiftCodeUI, SwiftCodeIDECore — neither has a resources entry
  today); repo convention confirmed from existing entries
  (`SwiftCodeExtensions` extension-host.js, `SwiftCodeSDK`
  SwiftCodeSDK.json, `SwiftCodeMCP` ReverseBridge.mjs) and
  `Bundle.module` use in those targets. `LicenseCatalogTests.swift`
  read in full before adapting the catalogue; the directory seam is
  untouched. `LicencesAddView`: no match in `swiftcode/Sources/`
  (grep); `LicenseCatalog` consumers: none (grep).
- Verification of staged artifacts: staged-copy sha256 matches
  57/57 sounds, 20/20 templates, 779/779 SPDX; delimiter balance
  0/0/0 on both staged Swift files; adapted diffs are minimal
  (SoundCatalog 10 changed lines, LicenseCatalog 109, of which 40
  are the generated alias-map entries). No Swift tools were run
  (per Dylan, 2026-11-06); no build or test execution is claimed.
