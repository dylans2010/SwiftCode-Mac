# Updates — Sparkle 2 Update System

SwiftCode has exactly one update system. It is Sparkle 2, driven by
`AppUpdateService`. There is no second feed, timer, checker, or window.

## Architecture

| Piece | File | Role |
| --- | --- | --- |
| Service | `SwiftCode/Backend/Updates/AppUpdateService.swift` | Owns the `SPUUpdater`, acts as its delegate and user driver, owns all update state (pending offer, download progress, phase, errors). |
| Pure logic | `SwiftCode/Backend/Updates/AppUpdateSupport.swift` | Feed URL, check interval, release-notes HTML→plain-text parsing, Remind Me Later gate. No Sparkle import, so it is testable without a Mac build. |
| Self-checks | `SwiftCode/Backend/Updates/AppUpdateSupportTests.swift` | In-app checks in the project's test-suite style (no XCTest target exists). Run `AppUpdateSupportTests.runAll()` from a debug harness; an empty failure list means all checks passed. |
| Window | `SwiftCode/Views/Settings/UpdateWindowView.swift` | The Commander-style update window (`UpdateWindowController` + `UpdateWindowView`). |
| Settings | `SwiftCode/Views/Settings/UpdatesView.swift` | Settings → Updates panel, bound to the same service. |

Entry points, all routing to `AppUpdateService`:

- App menu → **Check for Updates…** (`SwiftCode/App/AppCommands.swift`).
- Settings → Updates, and the Updates sheet in General settings (same `UpdatesView`).
- Automatic scheduled checks, started once at launch from
  `SwiftCode/App/AppDelegate.swift` (`AppUpdateService.shared.start()`).
  Starting the service never blocks launch; a startup failure is logged
  and shown in Settings, and the app runs normally.

### How the window answers Sparkle

The service is a full custom `SPUUserDriver`. The window's buttons do not
install anything themselves — they answer Sparkle through its reply
callbacks:

- **Install Update** → `.install` (Sparkle downloads, verifies, installs,
  and relaunches; the window stays open through download / ready /
  installing phases).
- **Skip This Version** → `.skip` (Sparkle persists the skip itself; the
  version is never offered again, later versions still are).
- **Remind Me Later** → `.dismiss` plus a persisted 7-day gate
  (`AppUpdateSupport.RemindLaterGate`, UserDefaults key
  `com.swiftcode.updates.remindUntil`). Scheduled checks suppress the offer
  until the gate expires; a manual **Check for Updates…** always re-offers,
  because the user explicitly asked.
- Closing the window with the traffic-light button is a plain dismissal:
  it answers `.dismiss` and never counts as a skip.

### Preferences

Sparkle owns its own keys (automatic checks, automatic downloads, skipped
versions). The Settings toggles bind directly to the service's
`automaticallyChecksForUpdates` / `automaticallyDownloadsUpdates`
properties, so they change real updater behavior, not a stored Boolean.

The checkbox in the update window is labeled exactly
"Automatically download and install updates in the future" and is bound
to the same property; it is disabled when Sparkle reports that automatic
updates are not allowed for the current distribution.

### What was replaced

The previous system was `SwiftCode/Backend/GitHub/GitHubReleaseCheck.swift`
(removed) plus the old `UpdatesView`. It polled the GitHub API for the
*wrong* repository (`dylans2010/SwiftCode`, which redirects), matched only
`build-(\d+)` tags, compared against `CFBundleVersion`, and its only
action was a link opening the release page in a browser. It had no
download, install, release notes, automatic checks, skip, or remind
behavior, and no update-related UserDefaults keys existed at all — so
there was nothing to migrate: no user preference was reset or lost.
The old system is fully removed; a repository search for
`GitHubReleaseCheck` returns only the explanatory comments in the new
files.

## Feed

Single feed URL, set in both places (the delegate is authoritative if
they ever diverge):

```
https://github.com/dylans2010/SwiftCode-Mac/releases/latest/download/appcast.xml
```

This is the `latest` release's `appcast.xml` asset, published by
`.github/workflows/release.yml`. Sparkle reads release notes from the
appcast item's description (or its linked release-notes page over HTTPS
only); no changelog is hardcoded anywhere.

## Versioning — read this before every release

Sparkle compares `CFBundleVersion` (the build number). The project now
pins explicit defaults in the app target's Debug/Release configs:

- `MARKETING_VERSION = 1.0.0`
- `CURRENT_PROJECT_VERSION = 1`

**Every release must bump `CURRENT_PROJECT_VERSION` to a value greater
than the previous release's, or installed copies will never be offered
the update.** `MARKETING_VERSION` is what users see; it may stay the
same across builds, but the build number must increase.

## Signing — production blocker, do first

`SUPublicEDKey` is deliberately **not** in `Info.plist` yet, because no
real key pair exists and a placeholder would be worse than none:
Sparkle fails closed at install time while the key is absent, and both
Settings and the update window show a "no signing key configured"
warning until it is set.

To enable real updates:

1. Run Sparkle's `generate_keys` tool (from the Sparkle release tarball).
   It prints a public key and a private key.
2. Paste the **public** key into `SwiftCode/Info.plist` as `SUPublicEDKey`.
   Only the public key ever goes in the repository.
3. Store the **private** key as the repository secret `SPARKLE_PRIVATE_KEY`.
   Never commit it, never paste it into a chat log, never put it in a file
   in the repo. The release workflow writes it to a 600-permission temp
   file for one step and deletes it immediately.
4. Ship at least one release built **with** the public key embedded
   before expecting clients to install updates: a client built without
   the key cannot verify a signed update.

## Local Release Pipeline (`scripts/release.sh`)

Instead of relying on GitHub Actions CI runners, SwiftCode provides a fully local, reproducible release pipeline via [`scripts/release.sh`](../scripts/release.sh).

### Prerequisites
- macOS machine with Xcode 15+ and developer command-line tools.
- GitHub CLI (`gh`) authenticated with repository access (`gh auth status`).
- Developer ID Application certificate installed in Keychain (for direct distribution).
- Apple Notarization credentials: either Keychain profile (`NOTARY_KEYCHAIN_PROFILE`) or Apple ID / App Password (`APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`).
- Sparkle EdDSA signing key in Keychain (`https://sparkle-project.org` entry) or `SPARKLE_PRIVATE_KEY` env var.

### Usage
```bash
# Dry-run validation (runs tests, preflight checks, builds, and verifies packaging without publishing)
./scripts/release.sh --dry-run

# Local development / ad-hoc testing (skips Apple notarization and Developer ID requirement)
./scripts/release.sh --allow-adhoc --skip-notarize

# Full production release (builds, signs, notarizes, staples, creates DMG & appcast, tags, and publishes)
./scripts/release.sh
```

### Options
- `--dry-run`: Runs preflight, test runner, application build, ad-hoc signing, DMG creation, and Sparkle appcast generation to verify the full pipeline without publishing or touching remote state.
- `--skip-notarize`: Bypasses `xcrun notarytool` submission and stapling.
- `--allow-adhoc`: Permits ad-hoc (`-`) codesigning if no "Developer ID Application" identity is present in Keychain.
- `--version <ver>`: Explicitly overrides the marketing version (defaults to Xcode project `MARKETING_VERSION`).
- `--build-num <num>`: Explicitly overrides the build version (defaults to Xcode project `CURRENT_PROJECT_VERSION`).

## Release workflow (GitHub Actions)

`.github/workflows/release.yml` runs on tags matching `v*` and, in order:

1. Fails fast if any required secret is missing (before building or
   publishing anything).
2. Imports the Developer ID certificate, builds a signed Release app,
   verifies the signature, notarizes with `notarytool`, and staples.
3. Builds `SwiftCode.dmg` with the same `hdiutil` recipe as `build.yml`.
4. Downloads the official Sparkle tools from the latest Sparkle GitHub
   release (resolved dynamically, verified to contain `generate_appcast`).
5. Runs `generate_appcast --ed-key-file <temp key file>
   --download-url-prefix https://github.com/dylans2010/SwiftCode-Mac/releases/download/<tag>/`
   on the DMG directory.
6. Verifies the generated `appcast.xml` contains a `sparkle:edSignature`
   and references `SwiftCode.dmg` for the tag — if either check fails,
   nothing is uploaded.
7. Uploads `SwiftCode.dmg` and `appcast.xml` to the tag's GitHub Release,
   last, so the feed never advertises an artifact that does not exist.

Required repository secrets: `SPARKLE_PRIVATE_KEY`,
`DEVELOPER_ID_CERTIFICATE` (base64 `.p12`),
`DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`
(app-specific password), `APPLE_TEAM_ID`.

`build.yml` / `ci.yml` are unchanged: they remain unsigned build-check
pipelines and do not publish updates.

## Testing

What can be checked without a Mac build (done when this system landed):

- `AppUpdateSupportTests.runAll()` expectations are pure-logic checks:
  feed URL is HTTPS and points at SwiftCode-Mac releases, HTML notes
  parse to headings/bullets with entities decoded, empty notes produce
  no blocks, the remind gate suppresses scheduled offers, expires, and
  never suppresses manual checks.
- Static checks: the pbxproj references for Sparkle and the four new
  files were cross-checked section by section (file refs, build files,
  Sources phase, Frameworks phase, groups), and no
  `GitHubReleaseCheck` reference remains in code or project.

What still needs a Mac (xcodebuild on Dylan's machine) before this is
called production-ready:

- The project builds with the new Sparkle SPM dependency resolved.
- Sparkle Swift API signatures used by `AppUpdateService` compile as
  written — a small number (noted in the service file) were taken from
  Sparkle's API reference and are the most likely first-build fixes,
  all localized to that one file.
- End-to-end: feed unreachable → app launches, manual check reports
  up-to-date / error with retry; a test release appears with real notes;
  Skip persists; Remind defers 7 days; auto-download toggle changes
  behavior; a signed update downloads, verifies, installs, and relaunches.
- The first `release.yml` run on a real tag, confirming notarization,
  `generate_appcast` output, and the appcast signature gate.

Useful reset while testing: clear Sparkle's last-check state with
`defaults delete com.dylans2010.SwiftCode-Mac SULastCheckTime`, and clear
any stored skipped-version state, to force a fresh offer.
