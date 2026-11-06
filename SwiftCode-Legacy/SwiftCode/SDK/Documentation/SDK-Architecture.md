# SwiftCode SDK — Architecture Decision Record

**Status:** Phase 0 exit gate · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` (proposed names in the spec are requirements, not existing APIs)

## 0. Baseline (Phase 0)

- Full repo audit performed 2026-10-12 by four read-only subagents. Reports (coordination copies):
  `~/workspace/swiftcode-sdk/audits/01-build-service.md`,
  `~/workspace/swiftcode-sdk/audits/02-source-control.md`,
  `~/workspace/swiftcode-sdk/audits/03-project-workspace.md`,
  `~/workspace/swiftcode-sdk/audits/04-assist-boundary.md`.
- Baseline tests: Python bridge suite `SwiftCode/Resources/Google Cloud SDK/bridge/gemini_auth_test.py` — **26/26 pass** on this branch.
- **No Swift build/test baseline exists in this environment** (no swiftc/xcodebuild). Swift code is statically verified only (balanced syntax, API usage against audited sources, xcodeproj refs resolve). `xcodebuild` build + test-suite run on Dylan's Mac is required before this branch is considered verified.
- Pre-existing issues noted (not caused by SDK work): the two `agent_runner.py` copies have diverged; `KeychainService` duplicates secrets base64-encoded into UserDefaults (`com.swiftcode.fallback.key.<key>`); `ConnectBuildService` cancellation is dishonest (reports cancelled while the process keeps running).

## 1. Module strategy

The app is a **single target** (`SwiftCode`, macOS 15.0, Swift 6.0). No XPC services, no test targets, no sandbox entitlement.
Per spec §1.1 ("names are architectural labels, not a requirement to introduce a separate target for every label") and
"adapt to the existing project rather than forcing a disruptive reorganization" (§5), the SDK ships **inside the
existing app target** under `SwiftCode/SDK/`, with hard directory boundaries standing in for module boundaries:

```
SwiftCode/SDK/
├── Contracts/        # versioned public data contracts, manifest schema, error taxonomy, IPC envelopes (data only, no services)
├── Host/             # PublicAPI façade, CapabilityBroker, ExtensionRegistry, ServiceAdapters (only layer that may touch app singletons)
├── Runtime/         # Lifecycle, IPC transport, Isolation, Diagnostics (never touches app services directly)
├── Internal/        # #if DEBUG-only: SandboxBypass, TestHarness, SDKConfigStore, DirectServiceAccess
├── Assist/          # Authorization (deny-by-default gate) + Audit
├── TypeScript/      # package/, cli/, runtime-adapter/, templates/ (node sources, not compiled into the app)
├── Testing/         # test harness sources (pending — directory not yet created)
└── Documentation/   # SDK-Architecture.md (this file), Extension-Manifest.md, Capabilities-and-Permissions.md,
                     # TypeScript-Extensions.md, Runtime-and-Security.md, Compatibility.md, Security-Keychain.md,
                     # Assist-Access.md (Part B: third-party Assist authorization — form, variants, entitlements,
                     # enforcement, revocation, approval policy)
```

New Swift files are registered in `SwiftCode.xcodeproj` by the coordinator (pbxproj lessons: accept 20–32 char
alphanumeric IDs; path-less groups resolve to the parent's path; anchor child-ID extraction to line start).
Subagents MUST NOT edit the `.pbxproj` themselves; they return exact file lists.

Per-task notes convention (spec §2.6): each SDK area maintains `SwiftCode/SDK/<Area>/agent_notes.md`.

## 2. Services wrapped (adapters in `SwiftCode/SDK/Host/ServiceAdapters/`)

| SDK capability | Real service wrapped | Adapter responsibilities |
|---|---|---|
| `source-control.read` | `GitService` (`SwiftCode/Backend/Git/GitService.swift`, `public actor`, singleton) — `getStatus`, `getDiff`, `getLog`, `getBranches` | Add: repo detection (`git rev-parse --is-inside-work-tree` — no detection API exists today); bounded diffs with truncation metadata (service returns unbounded text, no binary handling); stderr→typed-error mapping (service only throws `AppError.gitError(String)`); timeout around the blocking `ProcessRunnerTool` runner. Expose reads ONLY — the singleton also has `stage/commit/rollback/forcePush`, which the adapter must never surface. |
| `build.execute` | NEW host-owned `SDKBuildService` facade built on `AssistXcodeProjectResolver` (project/scheme discovery) + direct `Process` launch | Pinned `/usr/bin/xcodebuild` (never the user-overridable `xcodebuild_executable_path` pref); allow-listed params (scheme/configuration/destination validated, no env/settings/executable injection — none exists today and none is added); retained `Process` handle for **genuine** cancellation; real streamed output; truthful terminal state (exit code 0 + `** BUILD SUCCEEDED **` + zero parsed errors, mirroring `AssistBuildProjectTool`/`AssistVerificationPipeline` semantics); per-build identity (extension ID + project + correlation ID). Deliberately NOT built on `ConnectBuildService` (synthetic progress, fabricated diagnostics, dishonest cancellation) or `XcodeBuildManager` (UI-bound global singleton). |
| `project.read` (later) | `ProjectSessionStore.activeProject` / `Project` | Safe metadata only. |
| `workspace.read/write` (later) | `CodingManager` (has per-call symlink-resolving path-containment checks) | Constrained API on top of existing containment. |

Workspace scope single source of truth: `ProjectSessionStore.activeProject.directoryURL` (imported projects may point anywhere on disk — scope is per-project, not per-folder).

## 3. TypeScript execution strategy

**Out-of-process node child process**, stdio NDJSON transport (newline-delimited JSON request/response/event frames).
Rationale: no sandbox/XPC infrastructure exists; the closest working precedent is `GoogleCloudSDKProcess` (child `Process` + socket IPC + env separation for the Antigravity bridge). stdio avoids socket-path auth problems; each extension gets its own process, never the main thread.

- **Node resolution (host-controlled):** `SWIFTCODE_NODE_PATH` env override (dev) → well-known paths (`/opt/homebrew/bin/node`, `/usr/local/bin/node`, `/usr/bin/node`) → `PATH` lookup. If none found → typed `RUNTIME_UNAVAILABLE` error with actionable guidance. **Never silently download or execute runtime binaries** (spec §4.2).
- **Missing-toolchain path is tested**, not just documented.
- No `node_modules` inside extension packages unless the package format explicitly requires and validates them (spec §17).

## 4. Host ↔ extension communication

Versioned JSON envelopes over stdio, `protocolVersion: 1`, every message carrying `type` (`request`/`response`/`event`), `requestId` correlation ID, `method`, validated `payload`. Bounded messages (1 MB default), per-request timeouts, malformed/unknown privileged messages rejected with typed errors. **Extension identity is bound by the host to the runtime session** (validated manifest ID + package digest) — an extension-supplied identity field is never trusted (§10.4).

## 5. Permission grants: storage, scope, revocation, audit

- **Grant store:** host-owned actor-guarded JSON file `~/Library/Application Support/SwiftCode/SDKGrants.json` (mode `0600`). Record fields per spec §8.2: extension ID, package identity/version/digest, capability ID, scope (project/workspace), grant timestamp, granting principal, optional expiry, revocation status/timestamp, policy version, correlation metadata. Survives restart; revocation takes effect at the broker check immediately.
- **NOT via `KeychainService`** — its UserDefaults base64 fallback is a secret-leak vector (must be fixed before it holds SDK API keys, §8.2.1).
- **Audit log:** append-only JSONL `~/Library/Application Support/SwiftCode/SDKAudit.jsonl` (mode `0600`), host-only writes; records permission requested/granted/denied/revoked, Assist denials, API-key lifecycle, install/update/disable/uninstall, runtime termination. Extensions cannot read or modify it.
- **Approval UX:** modeled on the existing `TerminalApprovalSettings` pattern (explicit allow-list, no "allow everything" default), extended with per-extension identity, plain-language capability explanations, and revocation UI.

## 6. Local extension install / update

Install root: `~/Library/Application Support/SwiftCode/Extensions/<extension-id>/<version>/`. Deterministic package format (defined Phase 6; ZIP-like with documented suffix), validated before install: manifest, entry point inside package root, no path traversal, no escaping symlinks, digest recorded. Update is an explicit flow; a changed package digest or publisher identity **re-triggers approval** (no silent grant inheritance); failed update rolls back where feasible. No marketplace, no remote registry, no auto-update from a server (deferred per §3.2).

## 7. Capability registry (fixed for Phase 1+)

`project.read`, `workspace.read`, `workspace.write`, `source-control.read`, `source-control.write`, `build.execute`,
`task.execute`, `network.request`, `ui.contribute`, `credentials.use`, `assist.invoke` — semantics per spec §8.1 table.
The first TypeScript extension requests **only** `source-control.read` + `build.execute` and `"assist": {"requested": false}`.

## 8. Error taxonomy (fixed for Phase 1+)

Stable codes: `MANIFEST_INVALID`, `MANIFEST_UNSUPPORTED_VERSION`, `SCHEMA_VALIDATION_FAILED`, `PACKAGE_INTEGRITY_FAILURE`,
`PATH_TRAVERSAL`, `PERMISSION_DENIED`, `PERMISSION_REVOKED`, `PERMISSION_EXPIRED`, `PROJECT_NOT_OPEN`, `PROJECT_OUT_OF_SCOPE`,
`NOT_A_REPOSITORY`, `SERVICE_UNAVAILABLE`, `INVALID_ARGUMENT`, `INVALID_TARGET`, `BUILD_FAILED`, `BUILD_CANCELLED`,
`BUILD_TIMEOUT`, `RUNTIME_LAUNCH_FAILED`, `RUNTIME_CRASH`, `ACTIVATION_FAILED`, `DEACTIVATION_FAILED`, `IPC_MALFORMED`,
`IPC_PROTOCOL_MISMATCH`, `IPC_TIMEOUT`, `RESOURCE_LIMIT_EXCEEDED`, `INSTALL_FAILED`, `UPDATE_FAILED`, `UNINSTALL_FAILED`,
`API_KEY_INVALID`, `API_KEY_SCOPE_INSUFFICIENT`, `API_KEY_REVOKED`, `ASSIST_DENIED`, `RUNTIME_UNAVAILABLE`, `OUTPUT_TOO_LARGE`,
`REQUEST_TIMEOUT`, `UNKNOWN_CAPABILITY`, `INCOMPATIBLE_SDK_VERSION`, `TIMEOUT`.
Each carries: stable code, user-safe message, actionable suggestion, correlation ID (`ERR-XXXXXX`), structured diagnostics.
Dual logging (§16): user-facing sanitized stream ↔ developer verbose stream at `~/.swiftcode/logs/developer-sdk.log`, mapped by correlation ID.

## 9. Assist isolation (spec §9, non-negotiable)

- `assist.invoke` exists in the registry but is **never grantable in this release**: any request → typed `ASSIST_DENIED` + audit event.
- No `assist` object in the TypeScript `SwiftCodeContext`. No general-purpose bridge to `AssistManager`/`AssistAPIRouter`/`LLMService`.
- Choke points to gate: `AssistManager.shared.sendMessage`, `AssistAPIRouter.route`, `LLMService.sendChatRequest`, the bridge Unix socket.
- Tests must prove denial across: public API, IPC (including forged/malformed messages), direct service resolution. A manifest `"assist": {"requested": true}` is descriptive metadata only — still denied without the (future, separate) Assist authorization flow, which is NOT implemented in this release and no dormant bypass is added.

## 10. Versioning (spec §18)

- SDK package: `1.0.0` · manifest schema: `manifestVersion 1` · host/runtime protocol: `1` · internal `apiVersion`: `2026.1`.
- `SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json` is the canonical version metadata, managed by internal developers; user projects' SDK bindings sync from it on launch (non-breaking auto, breaking with explicit Studio prompt).
- `SwiftCode/SDK/Internal/` compiles **only under `#if DEBUG`** (stripped from release builds).

## 11. Developer API keys (spec §8.2.1)

Built-in key system, format `sc_dev_live_…` / `sc_dev_test_…` (cryptographically signed), created in Studio → Settings → Developer API Keys, scopes (`apps:create`, `apps:publish`, `capabilities:request`), stored via a **purpose-built Keychain wrapper** (not the leaky `KeychainService` fallback path), validated on every privileged platform action, revocable/rotatable with immediate effect. Required for app creation/publishing and privileged capability access.

## 12. First-release limitations (verified, not vague)

- No public marketplace / remote registry / server-driven auto-update.
- No arbitrary shell or process execution capability (`build.execute` ≠ shell).
- Python extension runtime deferred (standalone Python projects may come first, per §3.2).
- UI contributions limited to the command model initially; no arbitrary native UI injection.
- Command contributions need a new open registry — today's `CommandPaletteView.CommandAction` enum and `ToolbarActionManager.SheetDestination` enum are closed and cannot be plugged into without refactor (Studio/registry design must account for this).
- Assist is unavailable to extensions, period.
- The app is unsandboxed; extension isolation is process-boundary + broker enforcement, not OS sandboxing — documented honestly, no sandbox claims.
- No XCTest target exists; SDK tests ship as: Swift in-app runtime suite (`SwiftCode/SDK/Testing/`), node-based tests for TS sources, Python AST-exec pattern for bridge-adjacent logic — mirroring the repo's existing working patterns.

## 13. Phase 1 work items (contracts & manifest)

P1a manifest JSON schema + first-extension example manifest · P1b strict manifest/package validator ·
P1c error taxonomy + dual logging · P1d public data contracts + IPC envelopes ·
P1e `SwiftCodeSDK.json` + config store + `#if DEBUG` Internal scaffolding.
