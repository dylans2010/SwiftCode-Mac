# SwiftCode SDK — Shippable Product Phase: Execution Plan

**Status:** Plan for a future agent. The original `Intro-to-SDK.md` spec is preserved in git history
(`git log --follow -- Docs/Intro-to-SDK.md`, e.g. `git show d20f23ee:Docs/Intro-to-SDK.md`).
**Branch:** `feature/swiftcode-sdk` on `dylans2010/SwiftCode-Mac`. **Do NOT merge to main / open a PR without Dylan's word.**

## 0. Starting state (verify before writing code)

- `git log --oneline -5` on `feature/swiftcode-sdk`; `git status` clean; `git ls-remote origin refs/heads/feature/swiftcode-sdk`
  must match local HEAD (if not, investigate — the checkout is live-shared).
- Already built on this branch: SDK contracts, manifest schema/validators, capability broker (23 capability IDs —
  see `SwiftCode/SDK/Contracts/Capability/` and `SwiftCode/SDK/Host/ScopesIDLists.swift`), grant store, approval UX,
  audit log, Assist gate (deny-by-default), HMAC developer API keys, source-control + build adapters, out-of-process
  node runtime (lifecycle, NDJSON IPC), real `@swiftcode/sdk` TS package, `swiftcode` CLI
  (`SwiftCode/SDK/TypeScript/cli/`), Studio UI incl. code editor, `use.Security` Keychain system (verify it landed —
  it was the last phase before this plan was written), snippet library, docs under `SwiftCode/SDK/Documentation/`.
- **Not built — this plan:** (1) installable-package distribution + Studio first-launch installer,
  (2) extension/app manager, (3) `AvailableExtensionsView.swift`, (4) build → ship → install flows.

## 1. Non-negotiable conventions

- Real implementations only. No mocks, placeholders, TODO stubs, or fake success in production code.
- New Swift files MUST be registered in `SwiftCode.xcodeproj/project.pbxproj`: objects are flat top-level entries
  (never nested inside another group's dict), IDs are 20–32 char alphanumerics, a path-less group's path resolves to
  its PARENT's path (not its name). After editing, script-verify: every file ref resolves to an existing file, zero
  dangling refs, zero root-level file entries.
- Commit author/committer email: ALWAYS `dylans2010@users.noreply.github.com` (never `dylan@...`).
- Push ONLY via the Git Database API (`~/workspace/skills/github/bin/gh-api`): upload blobs → create tree with
  `base_tree` → create commit → update `refs/heads/feature/swiftcode-sdk`. Verify each pushed tree SHA is
  byte-identical to the local commit's tree SHA. Update the existing ref; never recreate it. Never `git push` over
  HTTPS (fails here); SSH to github.com is blocked.
- No Swift toolchain in this environment: Swift code is statically verified only — say so plainly. `xcodebuild`
  build + test suite on Dylan's Mac is required before merge. TypeScript/Node work MUST be actually built and tested
  here (`tsc`, `node --test`).
- Assist is never exposed to extensions. Capability checks are host-enforced on every privileged call.
- Keep `ScopesIDLists.ts` (`SwiftCode/SDK/TypeScript/package/src/`) and `ScopesIDLists.swift`
  (`SwiftCode/SDK/Host/`) in sync — the two-way sync test must stay green when adding IDs.

## 2. Task 1 — Installable package + GitHub distribution (PARTIALLY DONE — 2026-10-12)

- `SwiftCode/SDK/TypeScript/package/package.json` is a proper publishable manifest: name `@swiftcode/sdk`,
  version, `files`, `exports`, `bin` entries for the CLI (`swiftcode`), `engines` (node >= 18).
- **Distribution is LIVE:** the packed tarball is committed at `SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz`
  (41 KB, 23 files) and served from the `sdk-v1.0.0` tag + GitHub Release ("SwiftCode SDK v1.0.0"). Install link —
  verified working with stock node via `npm install <url>`, no registry, no auth:
  `https://raw.githubusercontent.com/dylans2010/SwiftCode-Mac/sdk-v1.0.0/SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz`
- Note: the Release carries no attached asset (asset upload to uploads.github.com is unreachable from this
  environment); the committed tarball served over raw.githubusercontent IS the distribution artifact.
- Remaining for the future agent: version-bump process (re-pack → commit tarball → move tag → update Release body).

## 3. Task 2 — Studio first-launch SDK installer

- First Studio launch → prompt the user to install the SDK (clear explanation, allow decline/remind-later).
- On approval, Studio uses Swift `Process` to run real node/npm:
  `npm install https://github.com/dylans2010/SwiftCode-Mac/releases/download/sdk-v<version>/swiftcode-sdk-<version>.tgz --prefix ~/.swiftcode/sdk`
  (version-pinned URL = deterministic installs; stock npm supports tarball URLs, no registry/account needed).
- VERIFY before claiming success: resolve the installed package and check its version; show real progress and real
  errors; never print "installed" until verified. Idempotent repair/re-install when broken.
- Fallback: if GitHub is unreachable, install from the SDK copy bundled inside SwiftCode.app
  (`npm install <local-path>`) and say so honestly in the UI.

## 4. Task 3 — Extension/app manager (host-side)

- Discover installed packages in the controlled extensions directory, validate manifests, launch runtimes, activate
  enabled ones at startup/manager open.
- Crash handling: mark failed, surface diagnostics, clean up contributions — never enter an infinite crash/restart loop.
- Disabled or invalid packages stay stopped with actionable diagnostics. Uninstall removes runtime state, commands,
  streams, grants per the spec's revocation rules.

## 5. Task 4 — `AvailableExtensionsView.swift`

- Native SwiftUI Studio view listing every installed extension/app and the commands each contributes.
- Extension UI stays TypeScript-driven: this view is a host shell; commands are invoked through the TS runtime.
  Extensions never inject native UI. Register the file in the xcodeproj.

## 6. Task 5 — Build → ship → install round-trip

- "Ship" runs a real compiler-like build (`tsc` for TS extensions; xcodebuild path for Swift where available) with
  live output, then packages to the single deterministic **`.swiftcode-extension` ZIP** format (manifest + dist +
  assets + digest; already byte-identical ×10 from the CLI work — keep that property).
- Studio Ship/Export flow via save panel / share. `swiftcode install` (and double-click, if wired) consumes the same
  file for both extensions and apps. Document the format precisely in `SwiftCode/SDK/Documentation/`.

## 7. Required verification (run here, report exact commands + results)

- `npm pack` → install the tarball from a `file://` URL into a clean prefix (simulates the Release asset) → generate
  an extension with `swiftcode create` against the INSTALLED package (not repo-local) → `npm install` → `npm run build`
  → `npm test` → `swiftcode validate` → `swiftcode package` → `swiftcode install` → run. All green.
- Tampered/corrupt `.swiftcode-extension` rejected with typed errors. First-launch installer tested against a stubbed
  home dir (success, GitHub-unreachable fallback, broken-install repair).
- Swift side: static verification only (state plainly what needs `xcodebuild` on Dylan's Mac: installer Process
  paths, manager startup, AvailableExtensionsView, ship flows).

## 8. Final report (from the implementing agent)

1. Commits pushed (SHAs) with tree-verification statement. 2. Test commands + results. 3. What was verified here vs
   what needs Dylan's Mac. 4. Known gaps/limitations — no vague "future work". 5. Regressions vs the pre-existing
   suite. Do not claim production-ready if a security boundary is unimplemented.
