<!-- system-index-depends: CallTool.md -->
# Localizing Apps — Full Apple App Localization

This guide is the canonical procedure for Assist when localizing a proper Apple app. It covers the whole pipeline: making strings localizable in code, String Catalogs, Info.plist regions, plurals and formatting, date/number handling, assets, right-to-left layouts, the XLIFF export/import workflow, scheme-based testing, and App Store Connect metadata.

Use the native `localize_app` tool for the mechanical work (key discovery, `Localizable.xcstrings` merge, `Info.plist` region keys). This asset tells you what to localize, in what order, and how to verify it.

---

## 1. Concepts & Prerequisites

**Prerequisites:** an Xcode project open in the workspace; the `localize_app` and `localization_audit` tools registered; translations for the target languages (human-reviewed or supplied by the user — never ship machine-only translations for user-facing copy without a review note).

**Key terminology:**

- **Development region** (`CFBundleDevelopmentRegion` in Info.plist): the language the app's source strings are written in, usually `en`. It is also the String Catalog's `sourceLanguage`.
- **`CFBundleLocalizations`**: the explicit list of language codes the app ships. If missing, the system infers it, but declaring it is correct practice.
- **String Catalog (`Localizable.xcstrings`)**: Apple's modern single-file localization format (JSON). One file holds every key and every locale, with per-unit state (`translated`, `new`, `needsReview`). Prefer this over everything below.
- **Legacy formats**: `Localizable.strings` (per-locale `Base.lproj`/`en.lproj` folders) and `InfoPlist.strings`. Still valid, but String Catalogs supersede them for app strings. Do not create new legacy files on a project that already uses catalogs.

**The golden rule:** localize *strings*, never string concatenation. Concatenated fragments break grammar in other languages.

---

## 2. Strategy: String Catalogs vs Legacy

| Situation | Do this |
|---|---|
| New localization work | Use `Localizable.xcstrings` via `localize_app`. |
| Project already has `en.lproj/Localizable.strings` | Migrate once with `string_catalog_migrator`, then use catalogs. |
| Bundle display name / permission strings | Use `InfoPlist.strings` per locale (see §3) — these live outside the Localizable table. |
| Plurals with CLDR rules | `.xcstrings` `variations` (Xcode UI) or legacy `.stringsdict` (see §5). |

Never mix a key across both a catalog and a legacy `.strings` file — one wins at runtime and the other silently rots.

---

## 3. Making Strings Localizable in Code

### SwiftUI — automatic via `LocalizedStringKey`

`Text("Hello, world!")` and `Button("Save") {}` are localized **automatically**: SwiftUI treats string literals as `LocalizedStringKey` and looks them up in the catalog. No API call needed.

Interpolated values are fine and stay in one key:

```swift
Text("Downloaded \(count) files")   // one key: "Downloaded %@ files"
```

### Programmatic lookup — `NSLocalizedString`

For UIKit/AppKit code, view models, error messages, notifications:

```swift
let title = NSLocalizedString("settings.title", comment: "Title of the Settings screen")
// Explicit table (rarely needed):
let t = NSLocalizedString("key", tableName: "Localizable", comment: "")
```

Rules: keys are namespaced (`feature.identifier`), comments describe context for translators, and the default table is `Localizable` — keys with another `tableName` live in a separate table, not the main catalog.

### Swift 5.7+ — `String(localized:)`

```swift
label.stringValue = String(localized: "status.syncing")
```

This behaves like `NSLocalizedString` and is what `localize_app` scans for, together with `NSLocalizedString(...)`.

### Strings that must NOT go in the Localizable catalog

- `CFBundleName`, `CFBundleDisplayName` → `InfoPlist.strings` per locale (one file per `.lproj`):
  ```
  "CFBundleDisplayName" = "Mi aplicación";
  ```
- Permission usage descriptions (`NSCameraUsageDescription`, …) → also `InfoPlist.strings`.
- The app's privacy manifest strings are not localizable — they are fixed metadata.

---

## 4. Info.plist Region Keys

Every localized app must declare:

- `CFBundleDevelopmentRegion` — e.g. `en` (the source language).
- `CFBundleLocalizations` — array of shipped language codes, e.g. `["es", "fr", "de"]`.

`localize_app` sets both and verifies the write. Use its `set_development_region` action to change the development region later (it also updates the catalog's `sourceLanguage`). Language codes follow BCP 47: `es`, `pt-BR`, `zh-Hans`, `en-US`.

---

## 5. Format Specifiers & Plurals

Positional specifiers survive reordering across languages — always use them:

```swift
String(format: NSLocalizedString("files.count", comment: ""), count)
// catalog value: "%d files"  /  "%d archivos"  (reorderable as "%1$d ... %2$@")
```

**Plurals** need CLDR categories (one/few/many/other), not `count == 1` branches:

- In a String Catalog: select the key in Xcode and add a **Plural** variation.
- Legacy `.stringsdict`:
  ```xml
  <key>files.count</key>
  <dict>
      <key>NSStringLocalizedFormatKey</key>
      <string>%#@count@</string>
      <key>count</key>
      <dict>
          <key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
          <key>NSStringFormatValueTypeKey</key><string>d</string>
          <key>one</key><string>%d file</string>
          <key>other</key><string>%d files</string>
      </dict>
  </dict>
  ```

`localize_app` writes plain `stringUnit` values; if a key contains format specifiers and needs per-count forms, add the plural variation in Xcode (or ship a `.stringsdict`) rather than inventing plural JSON by hand.

---

## 6. Dates, Numbers, Currencies

Never hardcode formats. Always go through locale-aware formatters:

```swift
let date = Date.now.formatted(date: .long, time: .short)          // locale-aware
let amount = amount.formatted(.currency(code: "USD"))              // locale-aware
let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = .current
```

Test with a non-Gregorian calendar region (e.g. `ar-SA`) to catch hardcoded `MM/dd/yyyy` assumptions. `Date.FormatStyle` and `NumberFormatter` handle this; custom `DateFormatter` date formats do not.

---

## 7. Localized Assets, Images & SF Symbols

- **Images with text baked in**: add per-locale variants to the asset catalog (`imageName.imageset` with localized `Contents.json`), or better, replace baked-in text with SwiftUI `Text` overlays.
- **SF Symbols**: prefer symbols over custom glyphs — they are language-neutral and flip correctly in RTL when drawn with `flipsForRightToLeftLayoutDirection`.
- **App icons, launch screens**: not localized; keep them language-neutral.

---

## 8. Right-to-Left (RTL) Layout

RTL languages: `ar`, `he`, `fa`, `ur` (`localize_app` detects these and reports `layoutDirection: rtl`).

- Use **leading/trailing** anchors, never left/right. In SwiftUI, `HStack` and alignment guides handle this automatically.
- Check custom drawings and `flipsForRightToLeftLayoutDirection` on `UIImage`/`NSImage`.
- Numbers, phone numbers, and code stay LTR — use Unicode isolates (`\u{2066}…\u{2069}`) around embedded LTR runs.
- Test every screen in an RTL pseudo-language (Xcode scheme → Application Language → Right-to-Left Pseudolanguage).

---

## 9. XLIFF Export / Import Workflow (human translators)

For professional translation rounds:

1. Xcode menu: **Editor → Export For Localization…** → produces `.xlf` per locale.
2. Send the XLIFF to translators (it carries source text, comments, and state).
3. **Editor → Import Localizations…** to merge the translated XLIFF back.
4. Re-run `localization_audit` to confirm no key regressed to `new`.

The catalog is the source of truth — XLIFF is a transport format, not storage.

---

## 10. Testing Localization

- **Scheme options** (the fastest loop): Product → Scheme → Edit Scheme → Run → Options → **App Language** / **App Region**. Cycle through every shipped language plus **Double-Length Pseudolanguage** (finds truncation) and **Right-to-Left Pseudolanguage**.
- Check: truncated labels, clipped buttons, overlapping text, untranslated leftovers, correct plural forms, date/number rendering.
- **Automated**: add a UI test per locale that launches with `-AppleLanguages (es)` and screenshots key screens.
- After any string change, run `localization_audit` — it reports missing keys per locale and keys never referenced in Swift.

---

## 11. App Store Connect Metadata

Localizing the binary is half the job. Localize per locale in App Store Connect:

- App name, subtitle, keywords, description, promotional text.
- Screenshots (at least one set per locale; regenerate with the UI-test screenshots from §10).
- What's New text per release.

Keywords differ per market — do not machine-translate the source keywords; research each locale.

---

## 12. Procedure: Localizing with Assist

When the user asks "localize my app into X, Y (and Z)":

1. **Discover**: run `localize_app` with `action=status` — see current keys, catalog state, and Info.plist regions.
2. **Translate**: obtain translations for every discovered key in each target language (ask the user for a glossary or preferred translations for brand terms; never silently invent brand/product names).
3. **Apply**: run `localize_app` with `action=localize`, `languages=[...]` (max 3 per session — do additional batches in follow-up calls), and the `translations` map. Keys without supplied translations are written with state `new` so nothing ships half-translated by accident.
4. **Verify**: re-read the written `Localizable.xcstrings`; run `localization_audit`; confirm `CFBundleLocalizations`/`CFBundleDevelopmentRegion` in Info.plist.
5. **Test**: have the user (or `use_app`/`artboard_run_app`) run the scheme language options from §10, prioritizing RTL and double-length pseudolanguages.
6. **Metadata**: remind the user about App Store Connect (§11) — it is outside the binary and needs a separate pass.

**Limits**: 3 languages per `localize_app` session call by design — a full 10-language rollout is several deliberate passes, not one giant diff. Machine translations are drafts; flag any user-facing string that shipped without human review.
