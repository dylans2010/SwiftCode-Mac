# Assist @Reverse — REA Audit & Execution Plan (Implemented)

Status: implemented on branch `feature/assist-reverse` in this worktree.
Swift was NOT compiled here (no Swift/Xcode toolchain in this
environment) — see §9. The bridge was verified against real REA 6.5.0.

## 1. REA audit (rea-agents@6.5.0, MIT)

Verified by installing the pinned package in `/tmp` (never in-repo)
and inspecting `node_modules/rea-agents/dist/`.

- Package: `rea-agents@6.5.0`, `license: MIT`, `type: module`,
  `engines: node ^22.19.0 || ^24.11.0 || >=26.0.0`. No `exports` /
  `main` / `types` fields — internal `dist/` paths are NOT a public API
  and must be treated as version-pinned internals (this subsystem pins
  6.5.0 and verifies `package.json` name+version at runtime).
- Entry points: `scripts/rea.mjs` CLI (`rea <command> --format json`
  emits a canonical Evidence envelope); `dist/mcp/` is the MCP server
  (NOT used, NOT imported, NOT launched anywhere in this subsystem).
- Real non-MCP path: `dist/composition/directAnalysis.js` exports
  `createDirectAnalysis(selectedEnvironment)` returning
  `{ runDirectAnalysis, runProviderAnalysis, runSessionStatus }`, which
  delegate to `dist/application/DirectAnalysis.js`. Verified: the import
  resolves, `runDirectAnalysis(path, "inspect_artifact", {}, {})`
  returns real Evidence (`provider: rea-artifact-graph`, `evidence_id`
  `ev_aa5c…`, `normalized_result.inspection_id …`).
- `inspect_with_objdump` is NOT declared by the composite direct
  provider. Verified: `runDirectAnalysis` returns
  `{ error: "Analysis failed", code: "capability_unavailable",
  category: "unsupported_provider", message: "…operation is not
  declared by this provider" }`. Hence the bridge's pinned-CLI fallback
  for that ONE operation (`rea inspect-with-objdump <path> <op>
  --format json`), parsing the same Evidence envelope. The fallback is
  documented as CLI-JSON, never presented as a direct API call.
- Native-macOS ops (`inspect_macho`, `inspect_plist`,
  `inspect_signature`, `list_architectures`, `demangle_swift`) are
  reported `unsupported_host` off macOS by `rea capabilities
  --format json`. They become available on macOS. The bridge computes
  availability from `process.platform`, and per-operation REA errors
  remain authoritative.
- Evidence envelope (verbatim shape, from the verified run):
  `{ evidence_id, subject: { name, digest: { sha256 }, local_path,
  format }, provider: { id, name, version }, operation, parameters,
  raw_result, normalized_result, confidence: "observed",
  limitations: [...], locations: [{ kind, path }], evidence_links: [] }`.
  `inspect_with_objdump` Evidence: `provider: gnu.objdump`,
  `normalized_result: { stdout, stderr, exit_code, signal,
  output_truncated, completion_status, artifact_sha256_after,
  artifact_changed }`.
- Disclaimer (REA `DISCLAIMER.md`): refuses circumventing DRM,
  license checks, anti-cheat, game cheats, auth/bot-protection bypass.
  This subsystem enforces the same boundary in
  `ReverseTargetValidator.refusalError(forTask:)` + docs.
- Excluded from the allow-list: `execute_rizin_command` (free-form),
  Frida/GDB/Rizin-debug sessions, ADB/browser/device ops, firmware
  extraction (writes), and all IDA/JEB/JADX-backed operations (licensed
  client integrations this subsystem must not drive).

## 2. SwiftCode integration points (verified by reading the files)

- Composer: `AssistMainView.inputText` + `submitMessage()` +
  `updateComposerTrigger` (last-word `@` → `.resource`, `/` → skill/meta).
  `ComposerTriggerMode` in `AssistComposerPopup.swift`; no command
  channel existed — `@` previously only picked resources.
- Envelope: `AssistTaskEnvelope` (`AssistTaskContext.swift`) carries
  skills/MCP/files/slash. Verified: `AssistManager.sendMessage`
  appended the stored user message WITHOUT the envelope — fixed by
  passing `envelope:` into the stored `AssistMessage` init (minimal,
  benefits all commands). New field: `reverseInvocation`.
- Routing: `AssistAgentSession.start` runs
  `AssistIntentClassifier.classify(prompt:)` and, when
  `deterministicToolId` is set, executes that ONE tool directly and ends
  the turn. `detectExplicitTool` is the hook: `@Reverse` with any parse
  (even without a target) now deterministically routes to
  `reverse_analyze`; the adapter returns actionable errors for missing /
  invalid targets instead of silence. Follow-up reasoning happens in a
  subsequent turn (the user can ask follow-ups; the evidence ID stays in
  history).
- Registry: `AssistToolRegistry.registerAllTools()`; generic
  `validate()` relativizes `path`/`filePath`/`sourcePath`/
  `destinationPath` and rejects `..`. Reverse uses `targetPath` /
  `operation` / `task` / `objdumpOperation` / `symbol` /
  `timeoutSeconds` — none touched by the generic validator — and does
  its own validation inside `execute` (registry `validate()` is bypassed
  on the deterministic fast path, and would not corrupt these keys on
  the normal path either).
- Tool protocol: `AssistTool` (`Tools/AssistTool.swift`) has NO progress
  callback and cancellation does NOT kill in-flight `execute`. Hence:
  progress is collected as an ordered trail in the result + manager
  snapshot, and cancellation terminates the bridge child process.
- Permissions: `AssistPermissionsManager` Autopilot BYPASSES gates —
  Reverse enforces its own checks inside `execute` and never consults
  the bypass.
- Settings: `AppSettings` (`@Published` + `assist.*` UserDefaults keys)
  + `AssistSettingsView`. New keys: `assist.reverseEnabled`,
  `assist.reverseBridgePath`, `assist.reverseReaDir`.
- Bridge template: `SDKNodeLauncher` (resolve Node, no download, secret
  stripping) + `SDKIPCTransport` (NDJSON, 1 MiB/frame). Reverse mirrors
  both, with one process per request (simpler crash/cancel semantics
  than a persistent process).
- Tests: single app target, NO XCTest target. Tests live in Sources via
  `AssistRuntimeTestSuite` — Reverse tests added as `ReverseTests.swift`
  and wired into `runAllTests()`.
- pbxproj: per-file PBXBuildFile + PBXFileReference + group children +
  Sources phase entries; new `Reverse` subgroup under `Internal API`
  (path="Reverse"); `ReverseBridge.mjs` is a bundle resource (Resources
  phase), NOT in Sources.

## 3. Architecture

```
Composer (@Reverse) -> ReverseCommandParser -> AssistTaskEnvelope.reverseInvocation
  -> AssistIntentClassifier (deterministic -> reverse_analyze)
  -> AssistAgentSession fast path -> ReverseToolAdapter (AssistTool)
  -> ReverseManager (lifecycle / cache / cancel)
  -> ReverseBridge (one Node process per request, argv only, NDJSON, bounded)
  -> ReverseBridge.mjs -> REA direct import (10 ops) | pinned CLI fallback (objdump)
  -> Evidence -> ReverseEvidenceProcessor -> structured findings in conversation
```

Provider paths: Reverse is supported on the native Agent Mode path
(`agentSession.start` fast path). Chat Mode has no tools by design, so
`@Reverse` there is treated as plain text plus the envelope marker;
Cloud / Meta / Antigravity paths receive the envelope but do not have
the deterministic fast path — the adapter is still registered, so a
model on those paths MAY call `reverse_analyze` from its schema, but
that is model-driven, not guaranteed. Settings shows readiness
regardless of path. This is documented honestly; no path is rewired.

## 4. Security

- Target/scope: absolute path, exists, is a file, symlink-resolved,
  not under /System /sbin /usr /bin /etc /var /Library /private /dev,
  not in a home dot-directory, and inside workspace root OR
  ~/Downloads / ~/Desktop / ~/Documents.
- No shell anywhere; fixed argv; no free-form commands; objdump op is a
  fixed enum; bridge validates args again (defense in depth).
- Bridge child env strips secret-bearing variables.
- Analyzed content is untrusted data; evidence is never treated as
  instructions; no secrets or full artifact contents are logged
  (stderr tail only, bounded).
- Static-only operations: nothing executes or interacts with the target.
- Cancellation kills the bridge process (SIGTERM → SIGKILL grace);
  the bridge forwards SIGTERM to its CLI child.
- No network use by the bridge; REA local analysis only. Offline-ness
  of upstream engines is NOT claimed beyond that.

## 5. Files changed

Added (all under `SwiftCode/Backend/Assist/API/Internal API/Reverse/`
unless noted):
- `ReverseModels.swift`, `ReverseBridge.swift`, `ReverseBridge.mjs`,
  `ReverseManager.swift`, `ReverseToolAdapter.swift`,
  `ReverseCommandParser.swift`, `ReverseEvidenceProcessor.swift`,
  `ReverseTests.swift`, `README.md`
- `Docs/Assist-Reverse-REA-Audit-and-Plan.md` (this file)

Modified (minimal wiring):
- `SwiftCode/Backend/Assist/AssistTaskContext.swift` — `reverseInvocation` field.
- `SwiftCode/Views/Assist/AssistComposerPopup.swift` — `.reverse` resource kind + Reverse row + `onSelectReverse` callback.
- `SwiftCode/Views/Assist/AssistMainView.swift` — `selectReverse()`, envelope attach in `submitMessage()` + Send-Now path.
- `SwiftCode/Backend/Assist/AssistToolRegistry.swift` — register adapter + `reverse` alias.
- `SwiftCode/Backend/Assist/AssistToolRouter.swift` — `reverse_analyze` metadata.
- `SwiftCode/Backend/Assist/AssistToolActivityFormatter.swift` — `reverse_analyze` labels.
- `SwiftCode/Backend/Assist/AssistIntentClassifier.swift` — deterministic `@Reverse` route in `detectExplicitTool`.
- `SwiftCode/Backend/Assist/AssistManager.swift` — stored message keeps the envelope.
- `SwiftCode/Models/AppSettings.swift` — `reverseEnabled` / `reverseBridgePath` / `reverseReaDir`.
- `SwiftCode/Views/Settings/AssistSettingsView.swift` — Reverse section (toggle, paths, readiness check).
- `SwiftCode/Backend/Assist/Functions/System Assets/AvailableTools.md` — Reverse catalog entry.
- `SwiftCode/Backend/Assist/AssistRuntimeTestSuite.swift` — include Reverse tests.
- `SwiftCode.xcodeproj/project.pbxproj` — Reverse group + Sources entries + `.mjs` resource.

Untouched by design: `UseMCP` / `Frameworks/Internal/MCP`,
`AssistAgentSession`, `AssistTool` protocol.

## 6. Verification (actual commands + outcomes)

In `/tmp/rea-verify` (never in-repo):
- `npm install rea-agents@6.5.0` (exact) — 173 packages, Node v24.20.0.
- `node --check ReverseBridge.mjs` — OK.
- Bridge `ping` — `{ reaVersion: "6.5.0", nodeVersion: "v24.20.0", platform: "linux" }`.
- Bridge `capabilities` — 11 ops; native-macOS ops `available: false`
  with `unsupported_host` reason; objdump available (objdump on PATH).
- Bridge `analyze` direct `inspect_artifact` on `/tmp/rea-verify/sample-bin`
  (copy of `/bin/ls`) — real Evidence, `evidence_id ev_aa5c…`,
  provider `rea-artifact-graph`, `normalized_result.inspection_id …`.
- Bridge `analyze` CLI-fallback `inspect_with_objdump` /
  `file_headers` on the same file — real Evidence, `evidence_id
  ev_a4f3…`, provider `gnu.objdump`, `normalized_result.stdout`
  contains `file format elf64-x86-64`.
- Direct-import probe: `createDirectAnalysis` import resolves;
  `runDirectAnalysis(..., "inspect_with_objdump", …)` returns
  `capability_unavailable` — the documented reason for the CLI fallback.
- `grep` for the forbidden transport in `Reverse/`: only the
  forbidding comments + the allow-list test reference it (see §8).

## 7. What is NOT implemented / limitations

- Swift NOT compiled here (no Swift/Xcode toolchain). Needs:
  `xcodebuild` clean build + runtime suite + live UI run on a Mac.
- Native-macOS ops not exercised here (Linux host): `inspect_macho`,
  `inspect_plist`, `inspect_signature`, `list_architectures`,
  `demangle_swift` are wired and reported available on macOS, but no
  Mach-O Evidence was produced in this environment. `inspect_go_binary`,
  `inspect_managed_artifact`, `inspect_managed_members`,
  `inspect_sqlite_database` are allow-listed via the direct path but
  were not exercised against real targets here (no Go/PE/SQLite
  fixtures); per-operation REA errors are the authority at runtime.
- The deterministic fast path ends the turn after one Reverse
  operation; multi-step investigations continue via follow-up turns
  (evidence ID stays in history). No automatic multi-op investigation
  loop was added.
- No live progress streaming (the `AssistTool` protocol has no progress
  channel); progress is an ordered trail in the result + manager
  snapshot. No `AssistTool` protocol change was made.
- REA is NOT vendored in-repo. The operator must place
  `rea-agents@6.5.0` in a configured directory (Settings) or beside
  the bridge; SwiftCode never downloads/installs it.
- `inspect_sqlite_database` upstream requires Node 24.15+/26+ with
  `DatabaseSync.limits`; on older Node 24 it will fail with an upstream
  error — reported, not masked.

## 8. No-forbidden-transport audit

`grep -rni "modelcontextprotocol" SwiftCode/Backend/Assist/API/Internal\ API/Reverse/`
returns only the test's negative assertion string. The literal string
"MCP" appears in `Reverse/` only in: one forbidding comment in
`ReverseBridge.swift`, the test assertions, and the `Reverse/README.md`
statement "No MCP anywhere in this subsystem". The bridge `.mjs`
forbids the Model Context Protocol transport in a comment spelled with
spaces, so the implementation identifier never appears there. No server,
client, import, argv, or fallback for that transport exists in the
Reverse subsystem. (`explicitMCPServers` is a pre-existing envelope
field, untouched.)
