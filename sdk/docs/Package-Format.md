# The `.swiftcode-extension` Package Format

**Status:** Task A4, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §8 · **Producers/consumers:** `swiftcode package`
(`TypeScript/cli/commands/package.mjs`), `swiftcode install`
(`TypeScript/cli/commands/install.mjs`), Studio Ship/Export
(`SDK/Studio/Views/SDKShipExportView.swift`)

One distributable file format for building, exporting, and installing both
extensions and apps. A package is produced by `swiftcode package`, verified
and installed by `swiftcode install`, and exported from Studio through the
Ship/Export view's save panel.

## 1. Container

A `.swiftcode-extension` file is a **ZIP archive** with these hard limits
(enforced identically by the packager and the installer's native reader):

- Compression: `stored` (method 0) or `deflate` (method 8) only.
- No encryption, no multi-disk archives, no zip64.
- Entry names: relative, forward-slash paths. Absolute names, `\` separators,
  and `..` segments are rejected at install time.
- Duplicate entry names are rejected.
- Symlinks recorded in the archive whose resolved target escapes the
  package are rejected at install time (the packager never emits them:
  contained symlinks are materialized as regular files).

**Determinism.** The packager writes every entry with a fixed modification
time (`2000-01-01T00:00:00Z`), fixed Unix mode (`0644`), fixed deflate level
(9), and entries sorted byte-wise by name. Packaging the same source tree
twice yields byte-identical archives (verified: 10 consecutive packages of
the same tree hash identically). Zip entries embed mtimes and modes, so
without pinning them every build would hash differently.

Size limit: 256 MiB (installer-side).

## 2. Archive layout

| Entry                 | Required | Notes                                                              |
| --------------------- | -------- | ------------------------------------------------------------------ |
| `swiftcode.json`      | yes      | The manifest (`Extension-Manifest.md`); validated against the v1 schema |
| `swiftcode-digest.json` | yes    | Embedded integrity record (§3)                                     |
| `dist/**`             | yes      | Compiled output; must contain `runtime.entrypoint`                 |
| `schemas/**`          | no       | Shipped schema copies (the manifest `$schema` pointer resolves here) |
| `README.md`           | no       |                                                                    |
| `package.json`        | no       | Project metadata (informational; not used at install time)         |
| other assets          | no       | Any additional files under the shippable roots                     |

Never shipped: `node_modules/`, `.env` / `.env.*` (secret-bearing),
`*.tsbuildinfo`, `.git/`, `.gitignore`, `.DS_Store`.

The installer's extraction recreates exactly this tree (minus zip
metadata) under `<extensions-root>/<id>/<version>/`, then writes the
host install record `.sdk-install.json` alongside it (host metadata, not
package content — excluded from content digests like the Swift registry
excludes it).

## 3. The embedded integrity record (`swiftcode-digest.json`)

Every package carries its own integrity proof so the installer can detect
**any** post-packaging modification — a flipped byte in `dist/`, an edited
manifest, an added or removed file — without trusting the archive.

Content (UTF-8 JSON, keys sorted, compact, no trailing newline — fully
deterministic):

```json
{
  "contentDigest": "da1a0c69eb8a44fe657ef888225e273826e283e34eea7feac18f36366f1af355",
  "formatVersion": 1,
  "id": "com.example.my-extension",
  "kind": "extension",
  "version": "0.1.0"
}
```

| Field           | Meaning                                                                 |
| --------------- | ----------------------------------------------------------------------- |
| `formatVersion` | `1`. Packages with any other version are rejected (`DIGEST_RECORD_MALFORMED`). |
| `id`            | Manifest id the package was built from. Must equal `swiftcode.json`'s `id`. |
| `version`       | Manifest version. Must equal `swiftcode.json`'s `version`.              |
| `kind`          | `"extension"` or `"app"` (§5). Must equal the manifest `type`.          |
| `contentDigest` | SHA-256 over the canonicalized package contents (§4).                   |

## 4. Digest algorithm and canonicalization

`contentDigest` is SHA-256 over a canonical byte stream built from the
**staged package contents** — the exact tree the archive contains,
**excluding `swiftcode-digest.json` itself** (it cannot hash itself).

The canonicalization is identical to the canonical directory digest used
by the host registry (`SDKExtensionRegistry.computeDigest(of:)`) and the
CLI's `computeDigestOf`, so the value is verifiable on both sides:

1. Enumerate every entry of the staged tree (files, directories, symlinks),
   skipping the digest record's basename. (On the installed side the host
   metadata file `.sdk-install.json` is skipped the same way.)
2. Sort the relative paths (`/`-joined) by UTF-8 byte order.
3. For each entry, feed the hash, in order:
   - the relative path as UTF-8 bytes,
   - one `0x00` byte,
   - one kind byte: `0x64` (`d`, directory), `0x66` (`f`, file), `0x6c` (`l`, symlink),
   - one `0x00` byte,
   - the content: streamed file bytes, the symlink destination string as
     UTF-8, or nothing for directories.
4. The hex digest of the stream is `contentDigest`.

The packager computes this over its staging dir; the installer recomputes
it over the extracted tree. Any difference fails the install with
`DIGEST_MISMATCH` (expected vs. actual digests are reported).

Two digests exist per package — do not confuse them:

- `contentDigest` (embedded): integrity of the shipped contents, computed
  **before** archiving, excluding the digest record.
- `packageDigest` (install record `.sdk-install.json`): canonical digest of
  the **installed tree**, including `swiftcode-digest.json` (deterministic
  content), recomputed by the installer after the move as a final
  "what actually landed" check.

## 5. Extension vs. app handling

Extensions and apps are the **same format**: identical archive layout,
identical digest algorithm, identical install flow, identical target
(`<extensions-root>/<id>/<version>/`). The kind is carried only by the
manifest `type` field (schema enum `["extension", "app"]`), mirrored into
the digest record's `kind` and reported by `install` ("Extension:" /
"App:") and its `--json` output (`data.kind`).

Differences are behavioral, on the host, not in the format:

- An `extension` contributes commands/UI to the host and is activated by
  the extension manager on launch.
- An `app` is a standalone package; the host does not inject it into the
  command palette or activate it at boot. (App-specific host launch
  behavior is future work; the v1 installer treats both kinds identically
  up to the kind label.)

The manifest `type` value is never a security boundary: capability checks
remain host-enforced per call, exactly as for extensions.

## 6. Install verification order

`swiftcode install` performs every check **before** touching the controlled
extensions directory, in this order:

1. Suffix (`.swiftcode-extension`) and archive readability.
2. Zip safety: traversal, absolute, duplicate, encrypted/zip64, and
   escaping-symlink entries rejected.
3. `swiftcode-digest.json` present and well-formed; recomputed canonical
   digest equals the embedded `contentDigest`; record identity
   (id/version/kind) equals the manifest's.
4. Full manifest-schema validation plus package checks (entrypoint exists
   inside the package, no escaping symlinks, no secret files).
5. Target `<root>/<id>/<version>/` free, or `--update` with backup +
   re-validate + rollback.
6. Install record `.sdk-install.json` written atomically (0600).

Only after all six does the CLI print "Installed"/"Updated".

## 7. Error taxonomy

Every failure is a typed error: a stable machine `code` plus a human
message. The CLI prints `[CODE] message` on stderr and, in `--json` mode,
returns it as `data.error = { code, message, details }`. Codes:

| Code                      | Meaning                                                        | Exit |
| ------------------------- | -------------------------------------------------------------- | ---- |
| `DIGEST_RECORD_MISSING`   | No `swiftcode-digest.json` in the archive (not a v1 package).   | 1    |
| `DIGEST_RECORD_MALFORMED` | The record is not valid JSON or fails shape checks.            | 1    |
| `DIGEST_MISMATCH`         | Recomputed digest ≠ embedded `contentDigest` — the package was modified after packaging. `details` carries `expected`/`actual`. | 1 |
| `DIGEST_IDENTITY_MISMATCH`| Record id/version/kind disagree with `swiftcode.json`.         | 1    |
| `MANIFEST_INVALID`        | `swiftcode.json` fails schema/package validation. `details` carries the full `problems` list (never just the first). | 1 |
| `MANIFEST_UNREADABLE`     | Package file missing or the archive cannot be extracted.       | 1    |
| `ARCHIVE_UNREADABLE`      | The file is not a readable (stored/deflate, non-zip64) zip.    | 1    |
| `ARCHIVE_UNSAFE_ENTRY`    | Traversal, absolute, duplicate, or escaping-symlink entry.     | 1    |
| `ENTRYPOINT_MISSING`      | `runtime.entrypoint` not produced by the build.                | 1    |
| `ALREADY_INSTALLED`       | id@version installed and `--update` not given.                 | 1    |
| `BUILD_FAILED`            | The compiler (tsc/xcodebuild) exited non-zero; the real diagnostic is included. | 1 |
| `COMPILER_NOT_FOUND`      | No TypeScript compiler found (checked `<dir>/node_modules/.bin/tsc`, PATH `tsc`, `npx --no-install tsc`). | 1 |
| `XCODEBUILD_UNAVAILABLE`  | Swift sources need `xcodebuild`, which is not on this machine. Nothing was compiled — reported honestly, never faked. | 1 |

Usage errors (bad flags, missing arguments) remain `UsageError` → exit 2
with the command's usage text; they are not package-format errors.

## 8. Round-trip

The supported developer loop, all real:

```sh
swiftcode build my-extension            # tsc (live output) / xcodebuild
swiftcode package my-extension --out dist-ship
swiftcode install dist-ship/my-extension-0.1.0.swiftcode-extension
```

`install` lands the tree in the controlled directory; the host runtime
then activates the installed entry point out-of-process over stdio IPC.
Studio's Ship/Export view performs the same `package` step behind a save
panel and hands the user the finished `.swiftcode-extension` file.
