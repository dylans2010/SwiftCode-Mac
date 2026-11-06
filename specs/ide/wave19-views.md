# Wave 19, slice C — Project Notes workspace + Workspace Profiles views

Port of the two remaining Legacy views from the bulk wave's 3-file missing
list (the third, `DocumentationBrowserView`, belongs to another slice):
`ProjectNotesWorkspaceView` and `WorkspaceProfilesView`.

## 1. `ProjectNotesWorkspaceView`

Legacy: `SwiftCode/Features/AdvancedTools/Views/ProjectNotesWorkspaceView.swift`
(≈1,900 lines including the window manager/controller).
Destination: `swiftcode/Sources/SwiftCodeUI/Notes/ProjectNotesWorkspaceView.swift`.

### Behaviour (Legacy, preserved)

Three-column workspace: sidebar (smart folders + notebooks + saved searches
+ tags cloud) | notes list (search, sort, category filter, batch select,
pin/favourite/archive/duplicate/delete) | editor + inspector.

- **Filtering** (view-owned `filteredNotes`): notebook filter unless a
  smart folder overrides it; smart folders All / Pinned / Favorites /
  Archived / Recent (recency order) / Todo / Daily Notes / Scratch Pad;
  category filter; `#tag` search (exact tag match); full-text search over
  title, content, category, tags, linked files and linked symbols;
  sorting by title / updated / created / word count (Recent keeps its own
  order). The `Todo` filter keeps Legacy's exact expression, including
  its operator-precedence quirk (`&&` binds tighter than `||`, so it is
  `category == "Todo" || (content.contains("- [ ]") && !isArchived)`).
- **Sidebar**: smart-folder rows; notebooks with inline rename,
  per-notebook note counts, delete (deletes the notebook's notes too, via
  state); saved searches (tap applies, × deletes); tags cloud (`#tag`
  applies a tag search); new-notebook sheet.
- **Notes list**: search field with clear + save-search bookmark; sort and
  category pickers; batch-select mode with delete-selected; note cards
  (title, summary with `#` lines stripped, category chip, updated date,
  pin/favourite markers); context menu (pin, favourite, archive,
  duplicate, select-multiple, delete).
- **Editor**: toolbar (title + pin/favourite toggles, word/read/character
  counts; focus / reading / presentation modes; sidebar + inspector
  toggles; Edit/Save); formatting row while editing (checklist, table,
  code block, NOTE/WARNING/TIP callouts, template picker from
  `ProjectNoteTemplates.builtInTemplates`, category picker); reading mode
  (rendered Markdown); presentation mode (centred large title + rendered
  Markdown); edit mode (text editor + live Markdown preview side by
  side); no-note empty state.
- **Inspector tabs**: AI Copilot, Links, Attachments (Files), History.
  - Links: outbound linked notes (tap selects, × unlinks), backlinks,
    project references (linked files / symbols / git commits, each
    removable; file tap posts `com.swiftcode.openFileInWorkspace` with
    the path, as in Legacy); link-note and add-reference sheets.
  - Attachments: add via `NSOpenPanel` (copied into the notes base
    directory by state), preview (images rendered, text shown, anything
    else reports "Binary or unreadable file format"), delete.
  - History: per-note version snapshots with timestamps, character
    counts and Rollback (also restores the editor text).
- **Window**: `ProjectNotesWindowManager.shared.showWindow()` raises the
  existing window or creates one (1000×700, min 800×600, title
  "Project Notes", frame autosave `SwiftCodeProjectNotesWindow` — Legacy's
  `ProjectNotesMainWindow` renamed per the rebrand's clean-break rule).

### Destination wiring

| Legacy dependency | Destination equivalent |
|---|---|
| `ProjectNotesWorkspaceState.shared` | `ProjectNotesWorkspaceState` in `SwiftCodeIDECore/Model/ProjectNotes.swift` — no singleton; the view owns `@State private var state = ProjectNotesWorkspaceState()` (loads its JSON on init). The window manager is a singleton holding one window, so one live state instance exists in practice. Every property/method the view calls was verified present (see Evidence). |
| `ProjectNote` / `ProjectNotebook` / `NoteAttachment` / `NoteVersion` / `SavedSearch` / `ProjectNoteTemplates` | Same file, same fields (templates are the condensed skeletons; full prose bodies were not carried over by the bulk wave). |
| `MarkdownParser.shared.parse` + `MarkdownBlockListView` | Ported whole in this slice: `SwiftCodeUI/Notes/MarkdownRenderer.swift` (+ `MarkdownRenderCache.swift`, `MarkdownRenderOptions.swift`). Needs the `Markdown` product (swift-markdown) on `SwiftCodeUI` — see INTEGRATION.md. |
| `TextEditorRepresentable` (NSTextView wrapper around Legacy's code editor) | **Not carried over.** Legacy's editor is SUPERSEDED by the destination `SourceEditorView`, which lives in the `swiftcode-ide` executable target and is not importable from `SwiftCodeUI`. The notes editor uses SwiftUI `TextEditor` (monospaced, word wrap on) — real editing; the code-editor features (syntax highlighting, search highlight) are not carried over. |
| `LLMService.shared.streamChat` + hardcoded model fallback (`meta-llama/llama-3-70b-instruct`) | **Not ported.** AI tab runs one-shot completions through `LLMToolCompletionService` (`SwiftCodeAssistant`, gap-closure LLM wiring) with `CodingAssistantServices.shared.backends()` — the provider + model chosen in Settings. Legacy streamed tokens live; this tab shows a progress view then the full reply. Failures surface `LLMToolError` verbatim (names the provider + what is missing). No model is ever hardcoded; nothing is generated from canned text. |
| Legacy state `saveSearch` (appended to `savedSearches`) | The destination state's `saveSearch` writes the search *history* instead. The bookmark button saves via a view-local `saveCurrentSearch` (append `SavedSearch` to `state.savedSearches`, Legacy's case-insensitive dedup, `saveData()`). The destination `saveSearch` semantics are a follow-up for the state file. |
| `.liquidGlass(style:cornerRadius:)` | No destination equivalent. Glass surfaces use `.thinMaterial` in a rounded rectangle, the treatment the destination's own SwiftUI views use (specs/ide/liquid-glass-swiftcode.md: SwiftCode draws no glass of its own making). |
| Legacy orange (`.orange` folder/pin/file accents) | `.accentColor`. Other semantic sidebar colours are unchanged. |
| `ProjectNotesWindowManager` / `ProjectNotesWindowController` | Ported, following the destination window-controller pattern (SQLite Explorer / CI / Deployment controllers in `SwiftCodeUI`): manager as `NSObject` + `NSWindowDelegate` extension, controller builds the `NSWindow` and hosts the view in `NSHostingView`. |

## 2. `WorkspaceProfilesView`

Legacy: `SwiftCode/Features/AdvancedTools/Views/WorkspaceProfilesView.swift`.
Destination: `swiftcode/Sources/SwiftCodeUI/Notes/WorkspaceProfilesView.swift`.

### Behaviour (Legacy, preserved verbatim)

Navigation stack with four cards: header (what profiles are); filter/sort
(search over name / build configuration / environment keys; category
segmented picker All / Favorites / Development / Production / Staging;
sort by Name / Recently used / Configuration; Create profile); profiles
list (name, favourite star, Active badge, contents summary "Build: … •
N environment variables • Last used …", per-row Activate / Rename /
Duplicate / Toggle favorite / Delete, tap selects); detail card for the
selected (else active, else first) profile (build configuration, last
used, profile ID, environment variables with Copy all). Create/rename
sheet (name, build configuration, favourite toggle, `KEY=VALUE` per-line
environment editor; lines without `=` are ignored, as in Legacy). JSON
import (single profile or array; matching IDs update, new IDs add; bad
files show the "Couldn't import profiles" alert) and export
(`workspace-profiles.json`, disabled when empty). Delete confirmation
dialog. Toolbar Import / Export / Done.

### Destination wiring

| Legacy dependency | Destination equivalent |
|---|---|
| `WorkspaceProfilesManager.shared` / `WorkspaceProfile` | `SwiftCodeIDECore/Model/WorkspaceProfiles.swift` — same API (`profiles`, `activeProfileID`, `switchTo`, `add`, `update`, `delete`). A profile is a saved selection, not a build-system override. |
| `ModernGroupBoxStyle` | Ported in this slice: `SwiftCodeUI/Notes/ModernGroupBoxStyle.swift`, adapted to the destination (below). |

## 3. Supporting files ported in this slice

- **`MarkdownRenderer.swift`** (585 lines, Legacy
  `SwiftCode/Shared/Markdown/MarkdownRenderer.swift`, verbatim + header):
  `MarkdownBlock` (heading / paragraph / codeBlock / blockQuote /
  bulletList / orderedList / taskList / horizontalRule / table),
  `MarkdownParser.shared.parse`, `MarkdownBlockListView` /
  `MarkdownBlockView` / `MarkdownCodeBlockView` /
  `MarkdownNestedListView`, `MarkdownRenderer` (sync + async cached
  render). Remote images are not fetched inline (alt text kept), as in
  Legacy. Needs swift-markdown on the target.
- **`MarkdownRenderCache.swift`** (56 lines) + **`MarkdownRenderOptions.swift`**
  (21 lines): the LRU cache and options behind the async render path,
  ported whole so the renderer has no divergence.
- **`ModernGroupBoxStyle.swift`** (Legacy `SwiftCode/UI/Styles/ModernGroupBoxStyle.swift`,
  adapted): Legacy drew the box with its own `.liquidGlass(...)`
  modifier and took a `LiquidGlassStyle` / `tint`; both are dropped
  (no destination equivalent) and the box uses `.thinMaterial` in a
  rounded rectangle with a hairline stroke. Only parameter is the corner
  radius (default 12); all call sites use the no-arg init.
  - **Ledger correction:** this file's ledger row claims SUPERSEDED by
    `ycode/Sources/ycode-ide/ShellStyle.swift`, but `ShellStyle.swift`
    defines no `GroupBoxStyle` — verified by repo-wide grep. The row
    should be corrected to IMPLEMENTED (see INTEGRATION.md). The bulk
    DevTools views already call `ModernGroupBoxStyle()`; the type simply
    did not exist, so they could not compile. This slice defines it in
    `SwiftCodeUI`, which does **not** repair the DevTools views
    (`swiftcode-ide` does not depend on `SwiftCodeUI`) — the parent's
    options are in INTEGRATION.md.

## 4. Honest-failure seams (nothing faked)

- **AI Copilot tab**: one-shot, not streaming; when no provider is
  usable the tab shows the provider's own honest failure verbatim.
  There is no canned reply, no fake streaming, no hardcoded model.
- **Notes editor**: SwiftUI `TextEditor`, not Legacy's code editor.
  Syntax highlighting and search highlight are absent, stated in the
  view header, not simulated.
- **`com.swiftcode.openFileInWorkspace`**: posted exactly as in Legacy
  when a linked file is tapped; whether the workspace observes it is
  unverified (same as Legacy).
- **Profiles**: switching records usage and exposes the active profile;
  applying a profile's environment to a build is the caller's job (the
  destination model's own contract).
- **Reachability**: neither surface has a menu entry / hub yet; that is
  the parent's integration step, not a silent omission.

## 5. What this slice did NOT do

- `DocumentationBrowserView` (third file of the bulk missing list) —
  another slice owns it.
- No `Package.swift` edits, no ledger edits, no commits, no pushes
  (rebrand push in flight during this slice). Wiring + rows are listed
  in INTEGRATION.md.
- No Swift tools were run (per the migration constraint). Verification
  is static only: delimiter balance on all six staged files (0/0/0),
  grep checks for forbidden leftovers (`.liquidGlass`,
  `TextEditorRepresentable`, `.orange`, `Ycode` — none), and a
  symbol-by-symbol cross-check of every state / model / manager / LLM
  API the views call against the destination sources (all present).
  Mac build/test is pending on Dylan's Mac.

## Evidence

- Legacy behaviour claims: Legacy sources read directly —
  `SwiftCode/Features/AdvancedTools/Views/ProjectNotesWorkspaceView.swift`,
  `.../WorkspaceProfilesView.swift`,
  `.../ProjectNotesWorkspaceState.swift` (esp. `saveSearch`,
  `executeAICopilotStreaming`), `.../ProjectNotesModels.swift`,
  `SwiftCode/Shared/Markdown/MarkdownRenderer.swift` (+
  `MarkdownRenderCache.swift`, `MarkdownRenderOptions.swift`),
  `SwiftCode/UI/Styles/ModernGroupBoxStyle.swift`,
  `SwiftCode/Features/AdvancedTools/Engines/WorkspaceProfilesManager.swift`.
  (Evidence level: Dylan's own code, direct port authorised under MIT.)
- Destination API claims: destination sources read directly —
  `swiftcode/Sources/SwiftCodeIDECore/Model/ProjectNotes.swift`,
  `.../Model/WorkspaceProfiles.swift`,
  `swiftcode/Sources/SwiftCodeAssistant/LLMToolCompletion.swift`,
  `swiftcode/Sources/SwiftCodeIDECore/Assistant/CodingAssistantServices.swift`
  (`shared`, `backends()`),
  `swiftcode/Sources/SwiftCodeUI/Database/SQLiteExplorerWindowController.swift`
  (window pattern), `swiftcode/Sources/swiftcode-ide/ShellStyle.swift`
  (verified: no `GroupBoxStyle`), `specs/ide/liquid-glass-swiftcode.md`
  (system-materials principle), `swiftcode/Package.swift`
  (target deps, dependency declaration form).
- Clean-room: no `research/` material, Ghidra output, Xcode copy/IPSW,
  or Apple Xcode/Simulator observation was used or opened at any point
  in this slice. All behaviour comes from Legacy (Dylan's own code) and
  destination sources plus public API.
- Static verification (this slice, no Swift tools): delimiter balance
  0/0/0 on all six staged Swift files; zero forbidden leftovers
  (`.liquidGlass`, `TextEditorRepresentable`,
  `ProjectNotesWorkspaceState.shared`, `executeAICopilotStreaming`,
  `.orange` outside one doc comment, `Ycode`/`ycode`); every
  `ProjectNotesWorkspaceState` method/property, `WorkspaceProfilesManager`
  method/property, and LLM entry point the views call was grep-verified
  present in the destination sources.
