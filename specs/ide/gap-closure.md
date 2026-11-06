# Gap closure — honestly-unavailable / honestly-failing items (Waves 1–17)

Coordinator merge doc. Each slice spec below is the authority for its
family; this file records the wave-level picture, the coordinator
decisions, and what is still open. Nothing here is VERIFIED — no Swift
toolchain exists in this environment; `swift build` / `swift test` and
live runs are pending on Dylan's Mac for everything.

## Slice specs

- `specs/ide/gap-closure-llm.md` — LLM wiring (11 tools onto Wave 9 providers)
- `specs/ide/gap-closure-failing-tools.md` — failing tools (slice still running at wrap-up; spec in tree, report pending)
- `specs/ide/gap-closure-search.md` — search tools (4 tools, real keyless endpoints)
- `specs/ide/gap-closure-correctness.md` — Myers diff, aliases, safe_undo, progress, AST, rename
- `specs/ide/gap-closure-cloud-github.md` — URL-scheme plumbing, Storage upload, SupabaseService, BackupEngine, AppConfig, GitHub remainder
- `specs/ide/gap-closure-windows-artboards.md` — Wave 17 follow-ups, 4 remaining view windows, Artboards format/persistence
- (misc slice still running at wrap-up; its spec was not yet written)

## What landed in this wave (coordinator-verified)

- **LLM wiring (11 tools):** all wired through `LLMToolCompletionService`
  to the Wave 9 providers via the host dispatch. `code_review` enforces
  Legacy's JSON verdict contract. No provider configured → honest
  failure naming the provider. Legacy's hardcoded fallback queue
  deliberately not ported.
- **Search (4 tools):** `web_search` (DuckDuckGo Instant Answer API),
  `documentation_search` / `api_reference_search` (Apple DocC JSON),
  `package_search` (Swift Package Index page + GitHub public search
  fallback). All endpoints probed live; full ranked search and Apple
  full-text search honestly unavailable (no keyless endpoint exists).
- **Correctness (6 items):** real O(ND) Myers engine (3,000 random
  trials vs brute-force LCS, 0 failures); parameter aliases (engine +
  server wiring); `safe_undo` via a per-file journal (deliberate
  decision NOT to unify with `project_snapshot` — different question,
  and Legacy snapshots are only ever created explicitly); progress from
  real Agentic plans; `swift_ast_inspector` on real swift-syntax parse;
  token-aware `symbol_rename_project` (limit stated: not semantic).
- **Cloud + GitHub:** URL-scheme plumbing + `Info.plist.in`
  `CFBundleURLTypes` (unblocks Appwrite AND Google OAuth); multipart
  Storage upload; `SupabaseService` (PostgREST); full `BackupEngine`;
  all five `AppConfig` entries; 12 GitHub methods (pushFile, getFileSHA,
  workflows, releases, repo ZIP, createRepository).
- **Windows + Artboards:** `/` popup + `useMetaSlashCommands` toggle
  (default ON) + Settings UI + router failover (max 2, never when
  auto-switch is off) + live extension writes via review presenter;
  deploy console, CI dashboard, VM console (Allocate/Release, no guest
  kernel/display), sandboxed terminal (argv-only, allowlist, workspace-
  confined — NOT a Seatbelt sandbox); Artboards format (57 component
  types, not 60) + `.ycode-artboard` persistence + `fix_artboards`
  pass 2.

## Coordinator incident — Wave 18 reset wiped tracked-file edits

The parent landed Wave 18 (`d3cf493`) mid-wave; its
`git reset --hard origin/main` reverted the completed slices'
uncommitted edits to TRACKED files (new untracked files survived).
The coordinator recovered them from the slices' session logs:
replayed the cloud slice's 5 files and the search slice's seam edit,
re-ran the LLM slice's own assertion-guarded patch scripts (its two
header-comment edits had failed at runtime on misquoted wrapping —
the method addition plus a corrected header edit were applied), and
the correctness slice re-applied its own `FileWriting.swift` edits.
Lesson for the parent: never `reset --hard` while parallel
coordinators hold uncommitted work in the same tree.

## Patches applied by the coordinator (all anchors asserted exactly-once)

LLM A (code_refactor) + B (intel_autofix); correctness P1 (alias
wiring in `MCPServer.run`), P2 (Myers `file_compare_diff`), P3
(Myers patch engine), P4 + P-commit (file_write `diff` key + journal
recording in `commit()`), P5 (safe_undo / progress handlers), P6
(AST handler), P7 (rename handler), P8 (`plans(workspace:)`);
cloud `Info.plist.in` URL schemes; windows P1
(`useMetaSlashCommands` field) + P2 (Netlify/Vercel secret accounts).

## Patches NOT applied — held for the parent / follow-up

- Search `AgenticNetwork.swift` registration patch (rewires the 4
  search tools, deletes the Wave 8 honest-fail handlers): its target
  file belongs to the still-running failing-tools slice. Apply after
  that slice lands; anchors were verified by the slice.
- Windows P3 (slash-popup composer wiring — insertion points only,
  no exact text), P4 (view-host surface actions — deletion half only,
  additions undescribed), P5 (GitHub client workflow/Pages endpoints
  — description, not exact text; deploy/CI services work without
  them), P6 (`Package.swift`: `"YcodeHypervisor"` in `YcodeUI` deps).
- Correctness `Package.swift` wiring: add `SwiftSyntax` +
  `SwiftParser` products to the `YcodeMCP` target (swift-syntax
  604.0.0 is already a package dependency).

## Honestly unavailable / still open (exact remainder)

- Failing-tools slice (still running at wrap-up): env/process logs,
  screenrecord, screenshot window/region, use_mcp/use_app completion,
  Composio/Workers clients, dependency_audit, reverse_analyze verdict,
  image/YAML/plist verification. Its spec is in the tree; its report
  and any final edits are pending.
- Misc slice (still running at wrap-up): generate_xcodeproj (its
  report preview says the generator was found absent and NOT
  re-implemented in the remaining time), AppTestStore simulation,
  SQLite follow-ups, Canvas seam, approval UI, LSPClient adaptation,
  demo-views verdict, persistence layer. Report pending.
- Artboards window (`ArtboardWindowController`) — not written
  (time-box forbade new files); all dependencies in place.
- Three windows-slice test files — not written (time-box).
- Full ranked web search (needs a Dylan-supplied Brave/Bing/Google
  key); Apple full-text doc search (no public API); `swiftc -dump-ast`
  path; semantic symbol rename (needs a type checker/index); undo for
  non-`commit()` operations and >1 MB / non-UTF-8 content; Supabase
  `executeSQL` (needs an RPC enabled in Dylan's project); password-
  reset completion UI (announced, no sheet); local-automation
  `WorkflowManager` engine; VZ guest boot/display; live artboard
  preview session (on-demand render only); Seatbelt sandboxing
  (needs a `sandbox-exec` decision); `docs.search` (Wave 19 owns it).

## What Dylan must supply (unchanged + new)

Configured LLM provider (OpenRouter key / OpenCode server / Hermes /
Apple Intelligence / SCCloud endpoint); GitHub PAT (contents:write,
actions:read, repo for createRepository); Netlify/Vercel tokens
(Deploy window, keychain-backed); Google OAuth client secret;
Gemini/Anthropic/OpenAI/Mistral/Qwen keys; Composio/Workers keys if
those tools are to answer; Brave/Bing/Google key for full ranked
search. Nothing secret is embedded anywhere in this wave.
