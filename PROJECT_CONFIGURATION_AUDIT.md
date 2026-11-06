# Project configuration audit

The destination is a Swift Package (`swiftcode/Package.swift`) plus the local
packages `frameworks/*` and `composer/`. There is no `.xcodeproj` in the
destination; the brief's “project configuration” requirement is satisfied by
the package manifest and its products (`SwiftCodeApp`, `swiftcode-ide`, and the
supporting libraries). The Legacy `.xcodeproj` is not copied (it is listed as
PROJECT_CONFIGURATION_MIGRATION and is not needed by a SwiftPM build).

## 1. Defects found and fixed

| File | Defect | Fix |
|---|---|---|
| `swiftcode/Package.swift` | Path dependency product referenced as `swiftcode-storekit` while the local package identity is `storekit` (directory name); `swift build` failed at manifest resolution. | Product references changed to `storekit`. |

## 2. Known configuration warnings (not yet fixed)

`swift build` reports unhandled files in `SwiftCodeIDECore`:

- `Sources/SwiftCodeIDECore/Resources/File Templates/*.txt` (20 files) — these
  are the built-in file templates that `FileTemplateManager` loads at runtime.
  They exist in the tree but are **not declared as a target resource**, so they
  are not bundled. The manager currently degrades to an empty list with an
  error message. Declaring the directory as a `.copy` resource is the fix.
- `Tests/SwiftCodeSDKTests/Fixtures/repository-build-extension.swiftcode.json`
  — a test fixture not declared as a resource.

These are recorded here so they are not mistaken for silent success. They do
not block compilation, but the file-template feature does not work until the
resources are declared.

## 3. Toolchain

| Item | Value |
|---|---|
| Xcode | 27.3 (MacOSX27.3.sdk) |
| Swift | 6.4.2 |
| Build command | `swift build` (from `swiftcode/`) |
| Target platform | arm64-apple-macos15.0 (per manifest) |

## 4. Package structure notes

- `Package.swift` is generated/edited programmatically at the bottom
  (`package.targets += [...]`), which is unusual but valid.
- The local `frameworks/storekit` package provides `StoreKitConfiguration` and
  `StoreKitEngine` products; its identity is `storekit`.
- `Package.resolved` changed as part of the identity fix; the pin set is
  otherwise unchanged.
