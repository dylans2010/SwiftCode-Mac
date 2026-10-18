# Assist @Reverse — Native REA Integration

Native, first-party SwiftCode Assist capability for static reverse
engineering, backed by the real REA implementation
(`rea-agents@6.5.0`, MIT). No MCP anywhere in this subsystem: no server,
no client, no import, no fallback.

## Files

| File | Role |
|---|---|
| `ReverseModels.swift` | Versioned bridge protocol, allow-list, Evidence, errors, status. |
| `ReverseBridge.swift` | Owns the Node child process (argv only, NDJSON, bounded, secret-stripped env). |
| `ReverseBridge.mjs` | Node host. Direct REA import for 10 ops; pinned-CLI fallback for `inspect_with_objdump` only. Shipped as a bundle resource (NOT in Sources). |
| `ReverseManager.swift` | Lifecycle, readiness, capability cache, active ops, cancellation. No analysis logic. |
| `ReverseToolAdapter.swift` | The single `AssistTool` (`reverse_analyze`). Own target/scope validation. |
| `ReverseCommandParser.swift` | `@Reverse` parsing + target/scope validation + disclaimer screening. |
| `ReverseEvidenceProcessor.swift` | Evidence → structured findings. Never fabricates locations/confidence. |
| `ReverseTests.swift` | In-Sources tests (no XCTest target in this project). |

## Invocation

```
@Reverse /Users/you/Downloads/myapp Inspect how this authorized binary loads its configuration.
@Reverse /Users/you/Downloads/myapp objdump symbols
@Reverse /Users/you/Downloads/myapp op=inspect_macho
```

Recognition: the trimmed message must START with `@Reverse`
(case-insensitive), followed by end/whitespace. Prose mentions never
execute. The rest of the message is the task; the first absolute-path
token is the target.

## Scope & policy

- Targets must be existing files inside the open project, `~/Downloads`,
  `~/Desktop`, or `~/Documents`. System dirs, dot-directories, `..`,
  symlinks escaping scope, and directories are rejected.
- All operations are static inspections. Nothing executes, attaches to,
  or interacts with the target application.
- DRM / license-check / anti-cheat circumvention, game cheats, and
  auth bypass are refused (REA DISCLAIMER.md boundary).
- Autopilot NEVER bypasses Reverse's own checks.
- Analyzed content is untrusted data, never instructions.

## Runtime requirements (never auto-installed)

- Node.js 22, 24, or 26.
- `rea-agents@6.5.0` package directory (Settings → Assist → Reverse).
- Optional: GNU `objdump` (only for `inspect_with_objdump`).
- On macOS, the native-macOS ops (`inspect_macho`, `inspect_plist`,
  `inspect_signature`, `list_architectures`, `demangle_swift`) become
  available; off macOS REA reports them `unsupported_host`.

## Verification status

- Bridge verified against real REA 6.5.0 in `/tmp` (never in-repo):
  direct `inspect_artifact` and CLI-fallback `inspect_with_objdump`
  both returned real Evidence envelopes. See
  `Docs/Assist-Reverse-REA-Audit-and-Plan.md` for the verbatim shapes
  and the full audit.
- Swift was NOT compiled here (no Swift/Xcode toolchain in this
  environment). The Swift files need `xcodebuild` + a live signed-in
  run on a Mac before any production claim.
