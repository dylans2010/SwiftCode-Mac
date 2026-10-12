# SwiftCode SDK — Agent Build Plan

**Purpose:** The complete, structured work order for a future agent. Covers (A) the parked Shippable product phase
and (B) the new third-party Assist authorization system.
**Branch:** `feature/swiftcode-sdk` on `dylans2010/SwiftCode-Mac`. **Do NOT merge to main / open a PR without Dylan's word.**
**Original spec:** preserved in git history (`git log --follow -- Docs/Intro-to-SDK.md`).

---

## 0. How to use this document

Work top to bottom. Each task has **Goal → Files → Steps → Acceptance criteria → Tests**. Do not skip the
conventions in §2. After every task: commit (see §2), push via the Git Database API with tree-SHA verification,
and report per §9. If a step cannot be completed as specified, stop that task, record the blocker, and continue
with the next independent task — never fake completion.

## 1. Starting state (verify before writing code)

1. `git log --oneline -5` on `feature/swiftcode-sdk`; `git status` clean.
2. `git ls-remote origin refs/heads/feature/swiftcode-sdk` must equal local HEAD. If not, investigate — the
   checkout is live-shared. Never force-push.
3. Already built: SDK contracts, manifest schema/validators, capability broker (31 capability IDs — see
   `SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`), grant store, approval UX, audit log, Assist gate
   (deny-by-default for extensions), HMAC developer API keys (`sc_dev_live_`/`sc_dev_test_`), source-control +
   build adapters, out-of-process node runtime (lifecycle, NDJSON IPC), `@swiftcode/sdk` TS package,
   `swiftcode` CLI, Studio UI + code editor, `use.Security` Keychain system, 12 view capabilities with
   `SDKViewOpener` + `ScopesIDLists.ts`/`.swift` (sync-tested), 20-snippet TS library, distribution tarball
   (see §4).
4. **Not built — this plan:** §4–§8 (Shippable, minus distribution which is live) and §10–§17 (Assist auth).

## 2. Non-negotiable conventions

- Real implementations only. No mocks, placeholders, TODO stubs, or fake success in production code.
- New Swift files MUST be registered in `SwiftCode.xcodeproj/project.pbxproj`: flat top-level objects (never
  nested), 20–32 char alphanumeric IDs, path-less groups resolve to the PARENT's path. After editing, script-verify:
  every file ref resolves, zero dangling refs.
- Commit author/committer email: ALWAYS `dylans2010@users.noreply.github.com`.
- Push ONLY via the Git Database API (`~/workspace/skills/github/bin/gh-api`): blobs → tree with `base_tree` →
  commit → update `refs/heads/feature/swiftcode-sdk`. Verify each pushed tree SHA is byte-identical to the local
  tree SHA. Update the existing ref; never recreate it. Never `git push` over HTTPS; SSH to github.com is blocked.
- No Swift toolchain here: Swift is statically verified only — say so plainly. `xcodebuild` on Dylan's Mac is
  required before merge. TypeScript/Node work MUST be built and tested here (`tsc`, `node --test`).
- Assist is never reachable by extensions except through the system in Part B. Capability checks are host-enforced
  on every privileged call; a manifest field is never a security boundary.
- Keep `ScopesIDLists.ts` (`SwiftCode/SDK/TypeScript/package/src/`) and `ScopesIDLists.swift`
  (`SwiftCode/SDK/Host/`) in sync — the two-way sync test must stay green when adding IDs.

## 3. Key locations

- Capabilities/registry: `SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`
- ID lists: `SwiftCode/SDK/Host/ScopesIDLists.swift`, `SwiftCode/SDK/TypeScript/package/src/ScopesIDLists.ts`
- View openers: `SwiftCode/SDK/Host/ViewOpener/` · Bootstrap: `SwiftCode/SDK/Host/SDKBootstrap.swift`
- TS package: `SwiftCode/SDK/TypeScript/package/` (src, cli, templates, snippets)
- API keys: `SwiftCode/SDK/Host/APIKeys/` · Security: `SwiftCode/SDK/Host/Security/`
- Studio: `SwiftCode/SDK/Studio/` (views in `Studio/Views/`)
- Distribution tarball: `SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz`
- Docs: `SwiftCode/SDK/Documentation/`

---

# PART A — Shippable product phase

## 4. Distribution (STATUS: LIVE — verify, don't rebuild)

- Tarball `SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz` (41 KB, 23 files) committed; served from tag
  `sdk-v1.0.0` + GitHub Release "SwiftCode SDK v1.0.0".
- Install link (verified with stock node, no registry/auth):
  `https://raw.githubusercontent.com/dylans2010/SwiftCode-Mac/sdk-v1.0.0/SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz`
- Agent: verify the link still installs (`npm install <url> --prefix /tmp/x && node -e "require('/tmp/x/node_modules/@swiftcode/sdk/package.json').version"`).
  For new versions: re-`npm pack` → commit tarball → move tag → update Release body.

## 5. Task A1 — Studio first-launch SDK installer

- **Goal:** First Studio launch prompts the user to install the SDK; approval triggers a real, verified install.
- **Files:** New: `SwiftCode/SDK/Studio/Views/SDKFirstLaunchInstallerView.swift`,
  `SwiftCode/SDK/Host/SDKInstaller.swift` (Process wrapper). Register both in the xcodeproj.
- **Steps:**
  1. Prompt UI: explains what the SDK is, install location (`~/.swiftcode/sdk`), decline/remind-later options.
  2. On approval, `SDKInstaller` runs via Swift `Process`:
     `npm install https://raw.githubusercontent.com/dylans2010/SwiftCode-Mac/sdk-v1.0.0/SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz --prefix ~/.swiftcode/sdk`
  3. Stream live stdout/stderr to the UI. On non-zero exit, show the real error — never a fake "installed".
  4. Verify: resolve `<prefix>/node_modules/@swiftcode/sdk/package.json` and check `version`; only then report success.
  5. Fallback: if GitHub unreachable, `npm install <app-bundled SDK path>` and state this honestly in the UI.
  6. Idempotent repair: detect broken installs (missing package/version mismatch) and offer re-install.
- **Acceptance:** Fresh-home install succeeds and verifies; network failure falls back with honest messaging; broken
  install is detected and repaired; declining leaves Studio fully usable.
- **Tests:** Installer logic against a stubbed home dir (success / unreachable / corrupt cases). Swift side
  statically verified; live run needs Dylan's Mac — state it.

## 6. Task A2 — Extension/app manager (host-side)

- **Goal:** A host service that starts and supervises ALL installed extensions/apps.
- **Files:** New: `SwiftCode/SDK/Host/SDKExtensionManager.swift` (+ xcodeproj registration).
- **Steps:**
  1. Discover packages in the controlled extensions directory; validate manifests (reuse `SDKManifestValidator`).
  2. Launch runtimes and activate enabled ones; wire into `SDKBootstrap`.
  3. Crash handling: mark failed, post diagnostics, clean up contributions — never an infinite crash/restart loop
     (bounded retries with backoff, then stopped+diagnosed).
  4. Disabled/invalid packages stay stopped with actionable diagnostics.
  5. Uninstall path removes runtime state, commands, streams, and session grants per revocation rules.
- **Acceptance:** N installed extensions start on boot; a crashing one is quarantined with diagnostics; disabling
  stops it; uninstall cleans everything.
- **Tests:** TS-side lifecycle tests here; Swift statically verified + live run on Dylan's Mac.

## 7. Task A3 — `AvailableExtensionsView.swift`

- **Goal:** The Studio view where users see and use every installed extension/app.
- **Files:** New: `SwiftCode/SDK/Studio/Views/AvailableExtensionsView.swift` (+ xcodeproj registration).
- **Steps:**
  1. List installed extensions/apps (id, version, enabled state) from the manager (§6).
  2. Show each item's contributed commands; invoking one calls through the TS runtime
     (`context.commands`), never native injection.
  3. Enable/disable/uninstall actions wired to the real manager — no decorative buttons.
- **Acceptance:** Every visible control performs its real action; extension UI remains TypeScript-driven.

## 8. Task A4 — Build → ship → install round-trip

- **Goal:** One distributable file format for building, exporting, and installing both extensions and apps.
- **Files:** Extend `SwiftCode/SDK/TypeScript/cli/` (`package.mjs`, `install.mjs`); Studio Ship/Export view.
- **Steps:**
  1. `swiftcode build` (compiler-like: `tsc` for TS; xcodebuild path for Swift where available) with live output.
  2. `swiftcode package` → deterministic `.swiftcode-extension` ZIP (manifest + dist + assets + digest; keep the
     byte-identical-across-builds property — verify ×10).
  3. Studio Ship/Export: save panel / share sheet producing the file.
  4. `swiftcode install <file>` (+ double-click if wired) installs extensions AND apps from the same format.
  5. Document the format precisely in `SwiftCode/SDK/Documentation/`.
- **Acceptance:** build → package → install → run works on a generated extension; tampered package rejected with
  typed errors.
- **Tests:** Full round-trip here with stock node; determinism check; tamper rejection.

---

# PART B — Third-party Assist authorization system

## 9. Overview

Today Assist is deny-by-default for extensions. Part B opens it deliberately: developers apply through a form,
receive key-bound entitlements, and call Assist through one of two SDK variants. The manifest can never grant this —
only a verified entitlement on the developer's API key can.

## 10. Task B1 — Application form

- **Goal:** Developers submit how they will use Assist; the answers are stored with the request and gate the entitlement.
- **Files:** New: `SwiftCode/SDK/Studio/Views/AssistAccessFormView.swift`,
  `SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift` (+ xcodeproj registration).
- **Required fields (all validated, none optional):**
  1. App identity (extension ID + display name — must match an installed/registered app).
  2. SDK variant: `assistSDK.UI` or `assistSDK` (radio, §11).
  3. "How will Assist be used in your app?" (free text, min length, stored verbatim).
  4. "Do you have your own UI for Assist responses?" (yes/no + description if yes; required choice informs variant).
  5. "Will third-party models outside SwiftCode be used?" (yes/no; if yes, list providers/models).
  6. Data handling: does user data leave the device? (yes/no + where to).
  7. Contact email.
- **Steps:** Native SwiftUI form → validates → stores a `SDKAssistApplication` record (pending) → approval step
  grants entitlements (§12). Approval policy: v1 = recorded self-attestation with revocation-on-abuse (document this
  as the policy; do not invent a human review queue).
- **Acceptance:** Incomplete forms are rejected with field-level errors; submitted forms persist; approval/denial
  produces the entitlement state in §12.

## 11. Task B2 — Two SDK variants

- **Goal:** `assistSDK.UI` and `assistSDK` as separate, typed SDK surfaces.
- **Files:** Extend `SwiftCode/SDK/TypeScript/package/src/` (`assist.ts`, `assistUI.ts`); Swift counterparts in
  `SwiftCode/SDK/Host/` (+ xcodeproj registration); ScopesIDLists entries for both.
- **assistSDK.UI (with UI):** exposes embedding of the real Assist Main view (`AssistMainView`) inside the
  developer's app — the host presents it; the extension never touches Assist internals.
- **assistSDK (without UI):** exposes the full Assist API surface EXCEPT UI: sessions, streaming responses, tool
  access per the approved scope — the developer renders everything themselves.
- **Acceptance:** UI variant can only present the host's Assist view (no custom Assist chrome); headless variant has
  no view-opening path; both require the entitlement (§12) or every call fails with the §13 error.

## 12. Task B3 — Entitlement model

- **Goal:** Two key-bound entitlements, granted only through the §10 flow.
- **Entitlements:**
  - `com.SwiftCode.developer-AI-Assist` — unlocks the Assist SDK variants (§11).
  - `com.SwiftCode.developer-AI-Allows-Cloud` — unlocks the SwiftCode cloud model for third-party apps (gates the
    existing `use.SwiftCodeModel` capability the same way).
- **Binding:** Entitlements are stored ON the developer's API key record (`sc_dev_live_…`/`sc_dev_test_…`), never in
  the manifest, never self-asserted. The API key token presented at call time must carry the entitlement.
- **Files:** Extend `SwiftCode/SDK/Host/APIKeys/` (key record, grant/revoke); audit events for grant/revoke.
- **Acceptance:** Entitlement present on key → calls allowed; absent → §13 error; revoked → immediate denial at the
  authorization boundary.

## 13. Task B4 — Enforcement + the exact user error

- **Goal:** Every Assist/cloud-model call checks the key-bound entitlement; failures produce the exact user message.
- **Enforcement points (all of them):** TS public API entry, IPC dispatcher route, direct service resolution, and
  any malformed/forged request path. A claim of the entitlement in the manifest, package name, or client code is
  ignored — only the key record counts.
- **User-facing error (verbatim, do not reword):**
  `This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information.`
- **Cloud-model denial** uses an analogous message (proposed wording — Dylan to finalize):
  `This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.`
- **Acceptance:** With a valid entitlement, calls succeed. Without it — via every route above — the caller gets a
  typed denial and the end user sees exactly the verbatim message. Log denials without leaking conversation content
  or credentials.

## 14. Task B5 — Revocation

- Revoking either entitlement takes effect immediately at the authorization boundary; in-flight Assist sessions are
  closed where safe; audit event recorded. Uninstalling the app removes its entitlement bindings.

## 15. Task B6 — Tests (must run)

- Form: valid/invalid submissions, field-level errors, persistence, approval→entitlement grant, denial→no grant.
- Variants: UI variant cannot reach headless-only paths and vice versa; neither works without the entitlement.
- Enforcement: all four routes (§13) with and without the entitlement; forged manifest claims ignored; wrong-key
  (entitlement on key A, call with key B) denied.
- Cloud: `use.SwiftCodeModel` denied without `com.SwiftCode.developer-AI-Allows-Cloud`, allowed with it (quota still
  enforced).
- Revocation: mid-session revoke blocks subsequent calls.
- Run TS tests here (`tsc`, `node --test`); Swift statically verified + live run on Dylan's Mac — state it.

## 16. Docs

- New: `SwiftCode/SDK/Documentation/Assist-Access.md` — the form, the two variants, entitlements, the exact user
  error, revocation, and the approval policy. Cross-link from the SDK README.

---

## 17. Global definition of done

- [ ] A1–A4 acceptance criteria hold; installer verifies before claiming success; round-trip green.
- [ ] B1–B6 acceptance criteria hold; the verbatim §13 error appears on every denied route.
- [ ] `npm run build` + `npm test` green in `SwiftCode/SDK/TypeScript/package`; scopes sync test green.
- [ ] xcodeproj: all new Swift files registered, zero dangling refs.
- [ ] No mocks/placeholders; no secrets in logs; Assist unreachable except via Part B entitlements.
- [ ] Swift compiled via `xcodebuild` on Dylan's Mac before any merge.

## 18. Final report format (from the implementing agent)

1. Commits pushed (SHAs) + per-commit tree-verification statement. 2. Exact test commands + results.
2. What was verified here vs what needs Dylan's Mac. 4. Known gaps — no vague "future work".
3. Regressions vs the pre-existing suite. 6. Do not claim production-ready if a boundary is unimplemented.
