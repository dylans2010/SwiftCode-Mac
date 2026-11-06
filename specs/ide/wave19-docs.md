# Wave 19 slice A — Offline documentation (Documentation Assets rewrite-from-spec)

## 1. Goal

Rebuild the offline Documentation Browser as a rewrite-from-spec.
Legacy's `SwiftCode/Resources/Documentation Assets/` tree (476 files,
7.6 MB) is **dropped, not copied**: it is Apple Xcode framework
`Resources/` (`.nib`, `Assets.car`, `.xcplugindata`, `Search.pdf`,
`.strings`, no license file anywhere) plus Apple documentation content
copied verbatim. Bundling it would be redistribution, not use of a
public API. The feature itself is small and re-derivable: the tree's
own README claims a "172,730-record SQLite DB" — verified false.
`Documentation.sqlite` holds **57 rows, one per topic**, and the
destination already fetches the same DocC JSON live from public
endpoints (`EnginesDocs`, `SearchDocs`). This slice fetches those 57
topics live, caches them locally, and serves them offline from the
cache, behind a port of Dylan's own
`DocumentationBrowserView.swift` (2,853 lines, Legacy, MIT) in
destination style.

Scope of this slice:

- **In:** the `docs.search` window (the `docs.search` view, which
  fails honestly today — the MCP `documentation_search` tool is
  already real since gap-closure); the `DocumentationBrowserView`
  port; the offline cache for the 57 topics; the DocC→HTML renderer
  for the web pane; the Snippet Library tab (destination store);
  the AI Co-Pilot tab (real provider, honest failure without one);
  the Project Notes tab as an honest-unavailable panel (its view
  belongs to another slice).
- **Out:** the 476-file tree (dropped); the localhost:8765 preview
  server (dropped — "Open in Safari" opens the live URL instead);
  the `.doccarchive` system file association and the `docc://`
  Info.plist scheme registration (product decisions for Dylan —
  claiming Apple's `docc` scheme system-wide is not this slice's
  call; the in-app `docc://` handling is implemented, the
  system registration is not); a Help-menu entry (follow-up);
  `generate_xcodeproj` and the other gap-closure remainders.

## 2. The 57 topics

The catalogue is the 57 names on which Legacy's `Documentation.sqlite`
and `SwiftCode/Resources/DocSymbols.json` agree exactly (verified:
same 57 names; the 13 framework-level entries differ in `kind` —
sqlite says `article`, the JSON says `class` — the sqlite is
authoritative and the live fetch corrects the kind per topic anyway).
Machine-readable source: `topics-57.tsv` in the staging directory
(name, title, kind, framework, Legacy path).

| Framework | Count | Topics |
|---|---|---|
| SwiftUI | 11 | App, Binding, Button, Environment, List, NavigationStack, State, SwiftUI, Text, VStack, View |
| Foundation | 7 | Data, Date, FileManager, Foundation, JSONDecoder, URL, URLSession |
| UIKit | 6 | UIButton, UIKit, UITableView, UIView, UIViewController, UIWindow |
| Swift | 5 | Actor, Array, Dictionary, Swift, Task |
| AppKit | 4 | AppKit, NSView, NSViewController, NSWindow |
| Combine | 4 | AnyPublisher, Combine, PassthroughSubject, Publisher |
| Metal | 4 | Metal, MTLCommandQueue, MTLDevice, MTLRenderPipelineState |
| SwiftData | 4 | Model, ModelContainer, ModelContext, SwiftData |
| AVFoundation | 3 | AVAudioSession, AVFoundation, AVPlayer |
| AppIntents | 3 | AppIntent, AppIntents, AppShortcut |
| CoreData | 3 | CoreData, NSManagedObject, NSPersistentContainer |
| CoreGraphics | 3 | CGContext, CGRect, CoreGraphics |

Kinds: 19 class, 17 struct, 13 article, 8 protocol. The Legacy
`path` column (`/documentation/developerdocumentation/<name>`) is
the Legacy book slug, **not** a real Apple URL — the rewrite
resolves each topic to its real DocC path at fetch time (§3) and
stores the real canonical path. The sidebar navigation is derived
from these 57 only: Legacy's hardcoded section tree lists topics
outside the 57 (View, App, Text, … as sidebar items under
"Essentials" etc.) — those were navigation into the bundled archive,
not the offline index. The rewrite's sections group the 57 by
Legacy's five section buckets (User Interface, Core & System
Services, Data & Persistence, Graphics & Media, System
Integration) with kind-groups inside each framework. Anything
outside the 57 is reachable through the live `documentation_search`
tool, not the offline sidebar.

## 3. Live fetch path (the only network surface)

The cache builder reuses the destination's existing fetch code —
no new HTTP client, no new endpoint:

- Candidate resolution: `EnginesDocs.resolveCandidates(query:name,
  urlString:"", framework:framework)` — with a framework, "VStack" +
  SwiftUI resolves to `documentation/swiftui/vstack`; a query that
  IS the framework name resolves to the framework root page
  (`documentation/swiftui`). Up to 4 candidates, in order.
- Fetch: `SearchHTTP.fetch(SearchHTTP.get(candidate.doccJSONURL,
  accept: "application/json"), maxBytes: 2_000_000, allowedHosts:
  EnginesDocs.appleHosts)` — HTTPS only, 30 s timeout, 2 MB cap,
  the `SearchWebTestTransport.session` seam for tests. Status
  handling mirrors `SearchDocs.fetchPage`: 2xx parses, 404 means
  "this candidate does not resolve" (try the next), 429 fails the
  batch fast with `rateLimited`, anything else is `badStatus`.
- Fallback: when no resolved candidate fetches, the builder runs
  `SearchDocs.search(query:name, framework:framework,
  symbolOnly:false)` (the framework-root `references` index +
  ranking) and fetches the best hit's DocC JSON by its URL. A topic
  that resolves through neither path is recorded `failed` with the
  reason — the batch never fails whole for one topic, and a failed
  topic is never invented.
- Parse: `EnginesDocs.parseDocCJSON(data:canonicalURL:finalJSONURL:,
  language:"swift", includeExamples:true)` — title, abstract,
  declarations, availability (`metadata.platforms[]`), discussion,
  examples (code listings), related links (seeAlso + relationships,
  max 12, developer.apple.com/documentation only). The raw JSON
  bytes are also kept: the cache stores the fetched payload
  verbatim so the renderer and any later re-parse read the same
  bytes the server sent.

No API key, no account, no undocumented host. Apple publishes no
public full-text documentation search API; the search here is the
same candidate-resolution + framework-index search the destination
already ships.

## 4. Cache layout

Root: `Application Support/SwiftCode/DocumentationCache/` (the same
Application Support convention as `LibraryCodeSnippetStore`'s
`snippets.json`).

```
DocumentationCache/
  index.json            # DocumentationCacheIndex (version 1)
  pages/<slug>.json     # one raw DocC JSON payload per cached topic
```

`<slug>` is the topic name lowercased (`vstack.json`,
`urlsession.json`, `nspersistentcontainer.json`). `index.json`
is written atomically (`.atomic` write) after every fetch run:

```json
{
  "version": 1,
  "fetchedAt": "2026-11-06T12:00:00Z",
  "topics": [
    {
      "name": "VStack", "kind": "struct", "framework": "SwiftUI",
      "docPath": "documentation/swiftui/vstack",
      "canonicalURL": "https://developer.apple.com/documentation/swiftui/vstack",
      "fetchedAt": "2026-11-06T12:00:00Z",
      "status": "cached"
    },
    {
      "name": "Model", "kind": "article", "framework": "SwiftData",
      "docPath": "documentation/swiftdata/model",
      "canonicalURL": null,
      "fetchedAt": null,
      "status": "failed",
      "failure": "All 4 candidates 404'd and the framework-index search found no match."
    }
  ]
}
```

`status` is `cached` or `failed`; a `failed` entry keeps its
`failure` string so the UI can say why. `loadSymbols()` builds
`[DocSymbol]` from the index + the stored page payloads; a topic
whose page file is missing is skipped (the index says `cached`
but the bytes are gone — the loader treats it as failed and
reports it, it does not crash and does not invent a symbol).

Why JSON and not the Legacy sqlite: the corpus is 57 rows.
Regenerating Legacy's exact sqlite schema is documented in §8 as
the reference format, but an FTS5 index over 57 entries buys
nothing — in-memory filtering over 57 symbols is instant — and
the destination has no sqlite writer in the MCP layer (its only
`SQLiteDatabase` is the HealthStore's). The JSON index carries
exactly the fields the browser needs; the Legacy sqlite schema
is preserved here as documentation, not as a runtime dependency.

## 5. DocC JSON → DocSymbol conversion

`DocSymbol` is Legacy's model, ported verbatim (same fields,
same `Codable` shape): `name`, `kind`, `framework`, `summary`,
`syntax`, `platforms: [String: String]`, `inheritsFrom`,
`conformsTo`, `codeSample`, `availability`, `seeAlso`, `docPath`.

Field mapping from a fetched payload (`Page` + raw JSON +
catalogue topic):

| DocSymbol field | Source |
|---|---|
| `name` | Catalogue topic name (the fetch key). |
| `kind` | DocC JSON `kind`: `article`/`overview` → `"article"`; `symbol` → inferred from the first declaration line (`protocol ` → `protocol`, `struct ` → `struct`, `class ` → `class`, `func ` → `func`, `actor ` → `actor`, `macro ` → `macro`, `enum ` → `enum`; no match → `"class"`, Legacy's default). The fetched kind wins over the catalogue's. |
| `framework` | Catalogue framework. |
| `summary` | `Page.abstract`. |
| `syntax` | `Page.declarations` joined with `\n` (first declaration when several). Empty when the page declares nothing. |
| `platforms` | `Page.availability` entries (`"iOS 13.0+"`) parsed to `[platform: version]` (version without the `+`). Empty when the page lists none — then the per-framework defaults below. |
| `availability` | `Page.availability` joined with `", "` (`"iOS 13.0+, macOS 10.15+"`). |
| `inheritsFrom` | Raw JSON `relationshipsSections`: the section titled "Inherits From", first identifier's `references` title. Absent → `nil`. |
| `conformsTo` | Raw JSON `relationshipsSections`: the section titled "Conforms To", all identifier titles. Absent → `[]`. |
| `codeSample` | `Page.examples` first code listing, fences stripped. **Empty when the page has no code listing** — the UI hides the sample section instead of showing Legacy's synthetic `import <Framework>` stub. |
| `seeAlso` | `Page.relatedLinks` titles (max 12). Names that are not in the 57 fall back to a search when tapped, exactly as Legacy did. |
| `docPath` | The fetched canonical path (`/documentation/swiftui/vstack`), not the Legacy book slug. |

Per-framework platform defaults (Legacy's `platformDefaults`,
ported verbatim — used only when a fetched page lists no
availability):

- SwiftUI: iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, visionOS 1.0
- SwiftData: iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, visionOS 1.0
- AppIntents: iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, visionOS 1.0
- Combine: iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, visionOS 1.0
- Swift: iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, visionOS 1.0
- Foundation: iOS 7.0, macOS 10.9, watchOS 2.0, tvOS 9.0, visionOS 1.0
- UIKit: iOS 2.0, macOS 11.0, watchOS 2.0, tvOS 9.0, visionOS 1.0
- AppKit: iOS 13.0, macOS 10.0, watchOS 6.0, tvOS 13.0, visionOS 1.0
- CoreData: iOS 3.0, macOS 10.4, watchOS 2.0, tvOS 9.0, visionOS 1.0
- CoreGraphics: iOS 2.0, macOS 10.0, watchOS 2.0, tvOS 9.0, visionOS 1.0
- Metal: iOS 8.0, macOS 10.11, watchOS 6.0, tvOS 9.0, visionOS 1.0
- AVFoundation: iOS 4.0, macOS 10.7, watchOS 6.0, tvOS 9.0, visionOS 1.0

## 6. The browser window

`DocumentationBrowserWindowManager` (shared singleton) +
`DocumentationBrowserWindowController` (1400×900, min 1200×800,
title "Documentation - Developer Bookshelf (Offline)", frame
autosave `DocumentationBrowserMainWindow`), mirroring Legacy's
manager/controller and the destination's `SQLiteExplorerWindow`
pattern (one shared window, raised when already open; no
workspace gate — the browser needs no project). Content is an
`NSHostingController` over `NativeDocumentationBrowserWorkspaceView`.

The window has four tabs (Legacy's tab bar, segmented, 440 pt):

- **Apple Docs** (the feature). Sidebar: search field (synchronous
  filter — 57 rows need no debounce; Legacy's 80 ms debounce was
  for a corpus orders of magnitude larger; matches name, summary,
  framework, syntax),
  Overview (All Technologies / Bookmarks with count / Recently
  Viewed with count), then the five section buckets with
  framework DisclosureGroups and kind-grouped topic rows.
  Search results replace the section list while a query is
  active. Detail pane: two modes (segmented) — **Offline Web
  Viewer** (default) and **Native Inspector**. The web viewer is
  a `WKWebView` fed by the `docc://` scheme handler (§7); the
  native inspector is pure SwiftUI over the `DocSymbol` (title +
  kind badge, framework + availability, overview, declaration
  syntax + Copy, inherits → current → conforms graph, usage
  sample (hidden when empty), platform grid, see-also chips).
  Top bar: web back/forward/reload/home, mode switcher,
  bookmark toggle, "Open in Safari" (opens the live
  developer.apple.com URL — no local server), offline status
  pill ("On-Device Index • Offline" when the cache is loaded,
  "Cache empty — download to read offline" otherwise),
  cache state + Download/Refresh button with per-topic progress.
  No symbol selected shows the hub home (banner + 12 framework
  cards). `databaseLoadError` is **rendered** (Legacy set it and
  never showed it — silent empty list); the browser shows the
  error and the Download action instead of a blank pane.
  Bookmarks (seeded `VStack`, `URLSession`, `View`, `Task`),
  recents (max 12), and search history (seeded `VStack`,
  `Task`, `JSONDecoder`, `View`) persist in UserDefaults
  (Legacy kept them in `@State` only — session-only; persisting
  them is a deliberate improvement, same keys as the snippets
  store convention).
- **Project Notes.** Honest-unavailable panel: the view belongs
  to the workspace-profiles slice (`ProjectNotesWorkspaceView`,
  one of the three missing Legacy files). The panel says so and
  names the missing view. It does not fake notes.
- **Snippet Library.** Real, backed by the destination's
  `LibraryCodeSnippetStore` (Application
  Support/SwiftCode/snippets.json; Legacy's UserDefaults key is
  superseded). List + search + create/edit/save/favorite/copy,
  Legacy's editor layout (title, language, category, tags,
  code). Categories are the destination's
  `LibrarySnippetCategory` (SwiftUI Views, Networking, Async
  Tasks, Data Models, Utilities); language stays free text with
  Legacy's Swift/SQL/Markdown/AI Prompt suggestions.
- **Local AI Co-Pilot.** Real, through `LLMToolCompletionService`
  (the Wave 9 providers via `CodingAssistantServices.shared`,
  same construction as the MCP accessor). Legacy's version is
  **not** ported: it slept 150 ms and reformatted the symbol's
  own fields, claiming "100% On-Device Mode" and "Fully
  compliant with Swift 6 Concurrency isolation standards" —
  canned text presented as analysis. The rewrite sends the
  selected symbol + prompt to the configured provider and shows
  the reply; with no provider usable it throws
  `LLMToolError` and the tab shows the provider's own
  recovery hint. Presets are Legacy's eight prompts.

`docc://` URLs and `.doccarchive` files: `openURL(_:)` on the
manager posts `.openDocCURLNotification`, exactly as Legacy;
the workspace view handles it (selects the symbol, loads the
`docc://` URL). A `.doccarchive` file is indexed with the same
DocC-JSON indexer over its `data/` directory (the
`indexFromDocumentationDataDirectory` logic, ported) and its
topics become a browsable collection for that window. The
system-level registration (Info.plist scheme / document type)
is out of scope (§1).

## 7. The web pane: DocC→HTML renderer + `docc://` handler

No Apple archive, no Apple renderer templates — the web pane
renders from the cached DocC JSON with SwiftCode's own small
HTML renderer (`DocumentationCache.renderedHTML(docPath:)`):

- A topic page renders: title, kind badge, framework +
  availability, abstract, declaration (monospace block),
  discussion paragraphs, code listings (fenced, monospace),
  related links (as `docc://` links so navigation stays
  in-app). Escaped with a plain HTML escaper; no JavaScript,
  no external resources, no Apple CSS/JS.
- The home path (`/documentation` or
  `/documentation/developerdocumentation`) renders the
  framework list (12 cards linking to the framework pages).
- A framework path (`/documentation/<framework>`) renders that
  framework's topics as `docc://` links with its cached count.
- An unknown path renders a 404 page naming the path and
  offering the live search — never a blank pane, never a
  guessed page.

`DocCURLSchemeHandler` (WKURLSchemeHandler) serves these
rendered pages for `docc://` URLs (MIME `text/html`,
200/404 as above, stop-task handling with the NSLock-guarded
stopped set, ported from Legacy). The
`OfflineDocumentationWKWebView` coordinator keeps Legacy's
navigation policy: `docc://` allowed; `developer.apple.com`
http(s) rewritten to `docc://`; any other http(s) opened in
the default browser; `targetFrame == nil` loads in place.

## 8. Reference formats (Legacy, for the record)

Legacy's `Documentation.sqlite` schema (verified live, 57 rows):

```sql
CREATE TABLE documentation (
    id TEXT PRIMARY KEY,          -- doc://DeveloperDocumentation/documentation/DeveloperDocumentation/<Name>
    name TEXT NOT NULL, title TEXT NOT NULL, kind TEXT NOT NULL,
    framework TEXT NOT NULL, abstract TEXT NOT NULL, syntax TEXT NOT NULL,
    code_sample TEXT NOT NULL, availability TEXT NOT NULL,
    platforms_json TEXT NOT NULL, inherits_from TEXT,
    conforms_to_json TEXT NOT NULL, see_also_json TEXT NOT NULL,
    path TEXT NOT NULL             -- /documentation/developerdocumentation/<lowercase-name>
);
-- FTS5 virtual table documentation_fts over the same 57 rows.
```

The rewrite does not ship or regenerate this sqlite (§4).
Legacy's `DocSymbols.json` (57 entries, same names) is the
second witness for the catalogue; its `kind` for the 13
framework-level entries (`class`) disagrees with the sqlite
(`article`) and is not used.

Deliberately not ported from Legacy's browser file:

- The hardcoded `/Users/dylan/SwiftCode-Mac/...` asset fallback
  path and the `/Applications/SwiftCode.app/...` path
  (`DocSymbolsLoader.getDocumentationAssetsURL` candidates 2–3).
- The localhost:8765 `python3 -m http.server` preview
  (`openInSafari`); "Open in Safari" opens the live URL.
- The silent `databaseLoadError` (set, never rendered).
- The AI tab's canned `generateOfflineInsight` (see §6).
- The synthetic `codeSample` fallback (`import <Framework>` stub)
  when a page has no code listing (see §5).
- Legacy's orange accent / Legacy styling: the port uses the
  destination's restrained palette (the bulk wave removed
  Legacy orange from ported views).

## 9. `docs.search` view wiring

`SwiftCodeSDKViewHost` gains a working `docs.search`:

- `SDKViewSurfaceActions` gains `showDocumentationBrowser()`
  (throws); `WorkspaceSDKViewSurfaceActions` implements it as
  `DocumentationBrowserWindowManager.shared.showWindow()` —
  no workspace gate, like `showCodingDictionary` /
  `showDatabaseExplorer` (the browser needs no project).
- `docs.search` leaves `unavailableReasons` and the
  unavailable switch case; `open(viewID: "docs.search")`
  routes to `actions.showDocumentationBrowser()`.
- The header disposition table is updated (docs.search moves
  to Working; 4 honestly-unavailable remain).
- No Package.swift change: `SwiftCodeUI` already depends on
  `SwiftCodeSDK`, `SwiftCodeAssistant`, `SwiftCodeMCP`,
  `SwiftCodeIDECore`. The MCP `documentation_search` tool
  needs no change (already real since gap-closure); the SDK
  `ui.openView` route with viewId `docs.search` is what this
  wiring enables.

## 10. Files (destination paths; staged under `staging-wave19/docs/`)

| Staged file | Destination path | Target |
|---|---|---|
| `DocumentationSymbols.swift` | `swiftcode/Sources/SwiftCodeIDECore/Model/DocumentationSymbols.swift` | SwiftCodeIDECore (Foundation only) |
| `DocumentationCache.swift` | `swiftcode/Sources/SwiftCodeMCP/DocumentationCache.swift` | SwiftCodeMCP (uses EnginesDocs/SearchHTTP, same target) |
| `DocumentationBrowserView.swift` | `swiftcode/Sources/SwiftCodeUI/Documentation/DocumentationBrowserView.swift` | SwiftCodeUI |
| `DocumentationBrowserWindowController.swift` | `swiftcode/Sources/SwiftCodeUI/Documentation/DocumentationBrowserWindowController.swift` | SwiftCodeUI |
| `DocumentationBrowserWebView.swift` | `swiftcode/Sources/SwiftCodeUI/Documentation/DocumentationBrowserWebView.swift` | SwiftCodeUI |
| `DocumentationBrowserSnippets.swift` | `swiftcode/Sources/SwiftCodeUI/Documentation/DocumentationBrowserSnippets.swift` | SwiftCodeUI |
| `DocumentationBrowserAIAssistant.swift` | `swiftcode/Sources/SwiftCodeUI/Documentation/DocumentationBrowserAIAssistant.swift` | SwiftCodeUI |
| `DocumentationBrowserProjectNotes.swift` | `swiftcode/Sources/SwiftCodeUI/Documentation/DocumentationBrowserProjectNotes.swift` | SwiftCodeUI |
| `SwiftCodeSDKViewHost.swift` (modified) | `swiftcode/Sources/SwiftCodeUI/SDK/SwiftCodeSDKViewHost.swift` (replace) | SwiftCodeUI |
| `DocumentationCacheTests.swift` | `swiftcode/Tests/SwiftCodeMCPTests/DocumentationCacheTests.swift` | SwiftCodeMCPTests |
| `SwiftCodeSDKViewHostTests.swift` (modified) | `swiftcode/Tests/SwiftCodeUITests/SwiftCodeSDKViewHostTests.swift` (replace) | SwiftCodeUITests |
| `wave19-docs.md` (this file) | `specs/ide/wave19-docs.md` | — |

No new target, no new package dependency, no Package.swift
edit. `SwiftCodeMCPTests` already depends on SwiftCodeMCP;
`SwiftCodeUITests` already depends on SwiftCodeUI +
SwiftCodeSDK (verify at apply time).

## 11. Verification (static only — no Swift tools exist here)

- Delimiter balance on every staged Swift file (0/0/0 per
  pair, checked with python).
- `git grep` re-derivation after apply: `docs.search` absent
  from `unavailableReasons`; `DocumentationBrowser` symbols
  present; no `ycode` reintroduced (the staged files use
  SwiftCode names throughout).
- Tests (staged, run on Dylan's Mac with `swift test`):
  catalogue is 57 with the 12 framework counts; DocC JSON →
  `DocSymbol` conversion from canned fixtures (kind inference,
  relationships, platform parsing, empty code sample);
  index encode/decode round-trip; fetch-all with the stub
  transport (all-cached, one-failed, rate-limited); renderer
  output contains title/abstract/declaration and escapes HTML;
  view-host routing (`docs.search` → `showDocumentationBrowser`,
  the other four unavailable unchanged). Assertions compare
  `TestSupport.firstText`, never exact `resultText ==`
  (`.structured()` emits two text blocks).
- Live proof (Dylan's Mac, not this environment): download
  the 57 topics (expect 57 cached, 0 failed, or a named
  failure per topic), open `docs.search` via the SDK, read a
  topic offline (network off), search + filter, open the same
  topic in Safari.

## Evidence

- The 57-row count, the schema, the framework/kind counts,
  and the sqlite-vs-JSON kind disagreement: verified live
  with `python3 sqlite3` (read-only) against Legacy's
  `Documentation.sqlite` and `DocSymbols.json` (evidence
  level 1 — the project's own files, read as data).
- The tree's README claims (172,730 records, 1.73 GB
  Spotlight index): verified false by the same read (no
  such index exists in the tree) — REVIEW scout §1 (level 1).
- The DocC fetch path (`tutorials/data/<docPath>.json`,
  candidate resolution, `parseDocCJSON` shape): the
  destination's own shipped code,
  `SwiftCodeTools+EnginesSupport.swift` (`EnginesDocs`) and
  `SwiftCodeTools+SearchWebSupport.swift` (`SearchDocs`),
  both probed live by gap-closure (level 1 — in-repo code,
  already live-verified).
- The browser's behaviour (1400×900 window, four tabs,
  search/filters/bookmarks/history/inspector/`docc://`
  handler, seeded values): Legacy's
  `DocumentationBrowserView.swift`, Dylan's own code, read
  in full (2,853 lines) (level 1).
- The AI tab's canned output: Legacy's
  `generateOfflineInsight` / `executeLocalAIDocumentationPrompt`
  (150 ms sleep, reformat of the symbol's own fields)
  (level 1 — read in full; the "100% On-Device Mode" and
  Swift 6 compliance claims are in the source text).
- The `docs.search` honest failure: destination's
  `SwiftCodeSDKViewHost.swift` `unavailableReasons` (level 1).
- No Apple code, binaries, Ghidra output, or Xcode/Simulator
  observation was used: the tree's Apple `Resources/` were
  never opened beyond the scout's inventory listing, and no
  file from the tree is copied into the destination.
