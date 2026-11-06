# Rebranding audit — Ycode → SwiftCode

Scope: the whole destination repository, excluding `.git/` and build output
(`.build/`). Matching is case-insensitive on the word `ycode` with word
boundaries, so substrings such as `DisplayCodecs` / `KEYCODE` are not counted.

## 1. Result

| Area | Remaining `Ycode`/`ycode`/`YCODE` | Classification |
|---|---|---|
| `swiftcode/` (shipped code + tests) | 0 after fixes | clean |
| `frameworks/` | 0 after fixes (historical `Ycode-original` design notes remain) | historical attribution |
| `composer/` | 0 | clean |
| `packaging/` | Flatpak app ID + file names | retained distribution identity |
| `docs/` | Flatpak app ID references | retained distribution identity |
| `specs/` | `Ycode-original` design-note provenance | historical attribution |
| `.github/` | Flatpak app ID in the release-metadata check | retained distribution identity |
| `research/` | capture/probe tooling | historical dirty-room tooling |

## 2. Fixed in this session

- `swiftcode/Sources/SwiftCodeIDECore/App/ProductIdentity.swift` — copyright
  now reads “MarcoDotIO and the SwiftCode contributors”.
- `packaging/macos/Info.plist.in` — same copyright correction.
- `frameworks/weatherkit/Scripts/generate-fixtures.py` and the checked-in
  `fixture.json` — fixture attribution now says “the SwiftCode project”.
- `packaging/flatpak/io.github.MarcoDotIO.Ycode.metainfo.xml` — developer name
  now “The SwiftCode contributors”.

## 3. Deliberately retained

### 3.1 Flatpak application ID `io.github.MarcoDotIO.Ycode`

This is a **distribution identity**, not a display name. It is the key under
which the app is installed, updated and discovered on FlatPark
(`flatpark.org/apps/io.github.MarcoDotIO.Ycode/`). Changing it would orphan
existing installs and break the update path. Per the migration brief, where an
identifier changes, backward-compatibility handling is required; here the
correct handling is to keep the stable ID. The user-visible name, desktop
entry, icon and metainfo name are SwiftCode.

Files: `packaging/flatpak/*`, `docs/RELEASING.md`,
`.github/scripts/check-release-metadata.py`, and the tests that assert the
Flatpak ID.

### 3.2 `Ycode-original` design-note provenance

`specs/` and `frameworks/` comments use “Ycode-original” to record that a
design decision predates the rename. This is historical attribution, which the
brief says to preserve. It is not application branding and does not appear in
the UI or in user-facing strings.

### 3.3 `research/`

The clean-room capture and probe tooling under `research/` still refers to the
old app name and old paths. It is analysis infrastructure, not shipped code.
It is tracked, but it is not part of the application. Renaming it is a
mechanical follow-up that does not affect the product; it is recorded here
rather than done blindly because several scripts reference paths that no
longer exist and need to be re-pointed, not just renamed.

## 4. Method

```
grep -rIoE '\b(Ycode|ycode|YCODE)\b' <dir> --exclude-dir=.build
```

Run per top-level directory. The earlier naive `grep -i ycode` produced ~1,872
false positives from `DisplayCodecs`, `KEYCODE`, etc.; the word-boundary form
is the accurate measure.
