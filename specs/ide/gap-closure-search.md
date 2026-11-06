# Gap closure: search tools (family 3)

Date: 2026-11-06. Slice: gap-closure family 3 (SEARCH TOOLS).
Destination: SwiftCode-Mac main @ f9f66c05 (SwiftCode base, SwiftPM).
Legacy (read-only): SwiftCode-Legacy @ d51a8f0d. Legacy source is Dylan's
own code; direct porting was authorised by Dylan under MIT.

This spec covers the four Agentic search tools Wave 8 registered as
honest failures: `web_search`, `documentation_search`,
`api_reference_search`, `package_search`. All four are now wired to
real, keyless, public endpoints (verified live from this environment
— see §0). The MCP catalogue stays at 433 tools: no tool is added or
removed; the four registrations change only where noted (§6, coordinator
applies).

## 0. Evidence collected live in this slice

All probes ran from this VM on 2026-11-06 with `curl` (no key, no
sign-in). Status codes and payload shapes below are what the
implementation relies on.

- DuckDuckGo `html` endpoint
  (`https://html.duckduckgo.com/html/?q=swift+language`): HTTP **202**,
  14,250 bytes — a bot-challenge page ("Unfortunately, bots use
  DuckDuckGo too. Please complete the following challenge to confirm
  this search was made by a human. Select all squares containing a
  duck"), zero result links. The `lite` endpoint
  (`https://lite.duckduckgo.com/lite/?q=swift+language`): HTTP **202**,
  14,256 bytes, same challenge. Conclusion: the html/lite result
  pages are bot-gated here and are deliberately NOT scraped — the
  challenge must not be solved, and scraping a bot-gated page would
  violate its terms.
- DuckDuckGo Instant Answer API
  (`https://api.duckduckgo.com/?q=swift+programming+language&format=json&no_html=1&skip_disambig=1`):
  HTTP **200**, 13,317 bytes, real JSON: an `AbstractText` ("Swift is
  a high-level general-purpose, multi-paradigm, compiled programming
  language created by Chris Lattner in 2010 …"), 17 `RelatedTopics`,
  1 `Results` entry. Conclusion: the documented, keyless, public
  Instant Answer API is the usable DuckDuckGo surface. It answers
  topics with a summary; it is NOT a full ranked web search.
- Swift Package Index JSON API
  (`https://swiftpackageindex.com/api/search?query=swift-argument-parser`):
  HTTP **401**, "401 - Unauthorized - User not authenticated".
  Conclusion: the JSON API needs authentication; it is not used.
- Swift Package Index search page
  (`https://swiftpackageindex.com/search?query=swift-argument-parser`):
  HTTP **200**, 12,554 bytes (same size with a plain
  `SwiftCode-MCP/1.0` User-Agent), server-rendered results in
  `<ul id="package-list">`: `apple/swift-argument-parser`
  ("Straightforward, type-safe argument parsing for Swift", "Active
  12 days ago", "3,802 stars", "Has documentation") plus forks and
  keyword matches. Conclusion: the search page is the reachable
  keyless surface of the index; its markup is parsed, never invented.
- GitHub public repository search API
  (`https://api.github.com/search/repositories?q=swift+argument+parser+language:swift&per_page=3`):
  HTTP **200**, `application/json`, `total_count` 77, first item
  `apple/swift-argument-parser` with `stargazers_count` 3802.
  Conclusion: keyless JSON search works; unauthenticated search is
  rate-limited (10 requests/minute per GitHub's docs) and 403s with
  a "rate limit" body when exhausted.
- Apple DocC render JSON:
  `https://developer.apple.com/tutorials/data/documentation/swiftui.json`
  → HTTP **200**, 39,770 bytes, `references` has 73 entries (7
  `symbol`, 55 `article`, 1 `technologies`, 1 `overview`, 9
  unkinded images); `…/documentation/swiftui/view.json` → HTTP
  **200**, 161,071 bytes, `"kind": "symbol"`. Conclusion: the DocC
  JSON path `fetch_documentation` already uses is the real,
  keyless documentation surface.
- Apple Developer site search: the search page embeds
  `window.SEARCH_CONFIG = {"api": "https://devintserv.msc.sbz.apple.com", …}`.
  Guessed paths on that host (`/search?query=swiftui%20view&locale=en-us`,
  `/search?query=swiftui%20view`) both answer HTTP **404** with an
  empty body. Conclusion: Apple's site search runs on an
  undocumented internal host whose path cannot be verified; it is
  NOT used. Apple publishes no public full-text documentation search
  API.
- Also probed and NOT used: Brave search HTML
  (`https://search.brave.com/search?q=swift+language`, HTTP 200,
  313 KB) is a JS-rendered results page with no documented keyless
  API — scraping it is not a stable backend. Bing search HTML
  (`https://www.bing.com/search?q=swift+language`, HTTP 200) has
  results in the markup, but automated scraping of Bing results
  HTML is against its terms for automated access — not used.
  Brave Search API, Bing Web Search API, and Google Custom Search
  all need keys Dylan has not supplied (§9).

Legacy (read live, `SwiftCode/Tools/Agentic/`):

- `WebSearch.swift`: `GET https://ddg-api.herokuapp.com/search?q=…`
  (an unofficial DuckDuckGo proxy, not a supported backend) and
  returns the raw body. Not reproduced: no request is sent there.
- `DocumentationSearch.swift`, `APIReferenceSearch.swift`,
  `PackageSearch.swift`: each `run` returns a canned string
  ("Documentation for: …" / "API Reference for: …" / "Package search
  results for: …") without searching anything. Not reproduced: those
  strings would be fake behaviour.

## 1. `web_search` — now working (DuckDuckGo Instant Answer)

Client: `SearchWebDDG` in `SwiftCodeTools+SearchWebSupport.swift`;
handler: `searchWeb(_:)` in `SwiftCodeTools+SearchWeb.swift`.

- Endpoint: `https://api.duckduckgo.com/?q=<query>&format=json&no_html=1&skip_disambig=1`,
  HTTPS only, 30 s timeout, 1 MB cap, redirects on
  `api.duckduckgo.com` only, `User-Agent: SwiftCode-MCP/1.0`.
- Parsing (`SearchWebDDG.parse`): `AbstractText` / `AbstractURL` /
  `AbstractSource` / `Answer`, plus `Results` and `RelatedTopics`
  (whose groups nest topics under `Topics`, flattened). Entries
  without a URL are dropped; duplicate URLs are removed, first
  occurrence wins.
- Result (structured): `abstract`, `abstractURL`, `answer`,
  `results` (formatted `text — url` lines), `resultCount`
  (default `limit` 8, clamped 1…20).
- Honest failure, no invented results: when the API returns an
  empty abstract, empty answer, and no results/topics, the tool
  fails with a message that says the Instant Answer API has
  nothing for the query, that it is not a full ranked web search,
  that the html/lite pages are bot-gated, and that a full search
  needs a keyed provider (Brave Search API, Bing Web Search API,
  or Google Custom Search) — no key has been supplied. An empty
  success is deliberately NOT returned: "no results" from this
  endpoint does not mean "no web results exist".
- 429 → "rate-limited, try again shortly"; other non-2xx → HTTP
  code; unparseable body → invalid-response failure.
- Missing `query` → Legacy's exact `"Missing query"`.

## 2. `documentation_search` — now working (DocC JSON search)

Client: `SearchDocs` in `SwiftCodeTools+SearchWebSupport.swift`;
handler: `searchDocumentation(_:)` in `SwiftCodeTools+SearchWeb.swift`.

- Surface: Apple's published DocC render JSON
  (`developer.apple.com/tutorials/data/<path>.json`), the same path
  `fetch_documentation` uses. Reused, not reimplemented:
  `EnginesDocs.resolveCandidates` (query → candidate DocC paths),
  `EnginesDocs.parseDocCJSON`, `EnginesHTTP.fetch` (2 MB cap).
- Search, not just fetch: (1) resolve candidates from the query
  (+ optional `framework`); (2) when a framework is given, fetch
  the framework root DocC JSON and search its `references` index
  for title matches against the query terms (up to 6 extra
  candidates — the root index is curated: SwiftUI's lists 73
  references, only 7 of them symbols, so this supplements candidate
  resolution rather than replacing it); the root page itself is not
  returned as a hit when other candidates exist. (3) Fetch each
  candidate's DocC JSON, parse it, rank by title/abstract match
  (exact title 3, all terms in title 2, any term in title 1, all
  terms in abstract +1). Every fetched candidate is kept; the score
  only orders the results.
- Result (structured): `results` (formatted `title — url` lines),
  `count` (default `limit` 5, clamped 1…10). The human summary
  carries title, canonical URL, DocC `kind`, availability, and
  abstract per hit.
- Honest failures: a single-token query with no framework cannot be
  resolved to a path — the resolver's own message is surfaced
  ("Could not derive a documentation path … Provide 'framework' or
  an exact documentation 'url'."). Candidates that resolve but do
  not fetch as pages → "No Apple documentation found … Tip: pass a
  'framework' plus the API symbol name". 429 fails fast with the
  `fetch_documentation` rate-limit wording.
- Deliberate limits, recorded here: there is no HTML fallback (the
  JSON endpoint is the search surface; a page with no DocC JSON is
  skipped, not scraped), and no `EnginesDocCache` entry (search
  results are not re-fetched per page the way `fetch_documentation`
  is). `fetchDocumentationCandidate` (`SwiftCodeTools+Engines.swift`)
  is deliberately NOT reused: it has no transport seam, so tests
  could not stub it. The candidate fetch here is the same
  DocC-JSON shape (same URL, same cap, same parser) with the seam
  threaded through.
- Missing `query` → `"Missing query"`.

## 3. `api_reference_search` — now working (DocC JSON, symbols only)

Same client and handler shape as §2 (`searchAPIReference(_:)`,
`symbolOnly: true`). The only difference: after fetching a
candidate, pages whose DocC `kind` is not `symbol` are dropped.
DocC marks every API symbol page `symbol` (types, methods,
properties, operators, macros alike); articles are `article`,
overviews `overview`, sample code `sampleCode`. When pages matched
but none is a symbol, the tool fails honestly ("No API reference
pages found … The documentation pages that matched are not API
symbols … Try documentation_search …") instead of returning an
article as a reference.

## 4. `package_search` — now working (SPI, GitHub fallback)

Client: `SearchPackages` in `SwiftCodeTools+SearchWebSupport.swift`;
handler: `searchPackage(_:)` in `SwiftCodeTools+SearchWeb.swift`.

- Primary: the Swift Package Index search page
  (`https://swiftpackageindex.com/search?query=…`, 1 MB cap).
  Parser (`parseSPIHTML`): the `<ul id="package-list">` entries —
  `<a href="/owner/repo"><h4>name</h4><p>summary</p>` plus the
  `<ul class="metadata">` identifier, activity line, and star
  count (commas stripped, `3,802` → `3802`). HTML entities in
  names/summaries are decoded (`&amp;`, `&hellip;`, `&#39;`,
  `&#x27;`, …; unknown entities are left as-is). An absent or
  unparseable list yields zero entries — the caller falls back to
  GitHub rather than guessing whether that means "no matches" or
  "markup drift".
- Fallback: the GitHub public repository search API
  (`https://api.github.com/search/repositories?q=<query> language:swift&sort=stars&order=desc&per_page=<limit>`,
  2 MB cap, `Accept: application/vnd.github+json`). Parser
  (`parseGitHubJSON`): `items[]` → `full_name`, `description`,
  `stargazers_count`, `html_url`. A 403 whose body says "rate
  limit" and a 429 both surface as rate-limited (unauthenticated
  search allows 10 requests/minute).
- Result (structured): `results` (formatted lines with name,
  identifier, URL, stars, summary), `count`, `source`
  (`swift-package-index` or `github-search`). Default `limit` 10,
  clamped 1…25. GitHub matches are labelled in the summary as
  repositories, not index-verified packages.
- Empty is a success, not a failure: when both backends answer and
  find no match, the tool returns count 0 ("No packages found").
  When both backends fail, it fails honestly naming both ("Swift
  Package Index returned no usable results / fetch failed …;
  GitHub search failed …"). An SPI transport failure falls through
  to GitHub; a GitHub failure is the failure.
- Missing `query` → `"Missing query"`.
- Not done: the Wave 10 GitHub token is NOT used opportunistically
  to raise the search rate limit (keyless first, per the brief).
  That is a follow-up, not a gap: unauthenticated search works.

## 5. Transport seam + `EnginesHTTP.fetch` change

`SwiftCodeTools+EnginesSupport.swift` (owned file) gains one
backwards-compatible change: `EnginesHTTP.fetch` takes an optional
`session: URLSession? = nil`. With nil (every production caller,
including both existing `fetch_documentation` call sites) the
behaviour is byte-identical: an ephemeral session with the
`EnginesRedirectGuard`. With a session, that session is used as-is
(a session's delegate is fixed at creation, so no redirect guard is
attached) and never invalidated. The request core (continuation,
cancellation holder, body cap) is shared by both paths.

The seam itself lives in the new support file:
`SearchWebTestTransport.session` (nil in production; tests install
a `URLProtocol`-backed session, the `gitHubTestSession` shape from
Wave 10). `SearchHTTP.fetch` is `EnginesHTTP.fetch` with the seam
threaded through. No other file's fetch behaviour changes.

## 6. Registration patch (coordinator applies — do not edit by hand)

File: `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+AgenticNetwork.swift`.
The four registrations keep Legacy's IDs, descriptions, and
required parameters; each gains optional parameters and an output
schema, `openWorld` read annotations (like `fetch_url`), and the
new handlers. The four Wave 8 honest-fail functions are deleted.

Old (call sites, lines ~203–230):

```swift
            tool("web_search", "Web Search",
                 "Performs a web search.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Search query.")],
                                      required: ["query"])) { h, call in
                try await h.agenticNetworkWebSearch(call)
            },
            tool("documentation_search", "Documentation Search",
                 "Searches for documentation.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Documentation topic to search for.")],
                                      required: ["query"])) { h, call in
                try await h.agenticNetworkDocumentationSearch(call)
            },
            tool("api_reference_search", "API Reference Search",
                 "Searches for API references.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("API symbol or framework to search for.")],
                                      required: ["query"])) { h, call in
                try await h.agenticNetworkAPIReferenceSearch(call)
            },
            tool("package_search", "Package Search",
                 "Searches for packages.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Package name or keyword to search for.")],
                                      required: ["query"])) { h, call in
                try await h.agenticNetworkPackageSearch(call)
            },
```

New:

```swift
            tool("web_search", "Web Search",
                 "Performs a web search.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Search query."),
                                       "limit": Schema.integer("Maximum results to return (default: 8, max: 20).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["abstract": Schema.str, "abstractURL": Schema.str, "answer": Schema.str,
                                        "results": Schema.str, "resultCount": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.searchWeb(call)
            },
            tool("documentation_search", "Documentation Search",
                 "Searches for documentation.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Documentation topic to search for."),
                                       "framework": Schema.string("Optional framework to search within (e.g. 'SwiftUI')."),
                                       "limit": Schema.integer("Maximum results to return (default: 5, max: 10).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["results": Schema.str, "count": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.searchDocumentation(call)
            },
            tool("api_reference_search", "API Reference Search",
                 "Searches for API references.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("API symbol or framework to search for."),
                                       "framework": Schema.string("Optional framework to search within (e.g. 'SwiftUI')."),
                                       "limit": Schema.integer("Maximum results to return (default: 5, max: 10).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["results": Schema.str, "count": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.searchAPIReference(call)
            },
            tool("package_search", "Package Search",
                 "Searches for packages.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Package name or keyword to search for."),
                                       "limit": Schema.integer("Maximum results to return (default: 10, max: 25).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["results": Schema.str, "count": Schema.int, "source": Schema.str]),
                 annotations: externalRead) { h, call in
                try await h.searchPackage(call)
            },
```

(`externalRead` is already defined at the top of
`agenticNetworkTools`.)

Delete the four Wave 8 honest-fail functions
`agenticNetworkWebSearch`, `agenticNetworkDocumentationSearch`,
`agenticNetworkAPIReferenceSearch`, `agenticNetworkPackageSearch`
(the `// MARK: - Honestly failing: search tools` section, keeping
`agenticNetworkDependencyAudit` — that tool belongs to family 2,
not this slice). Also update the file's header doc: the
HONESTLY-FAILING (5) list becomes HONESTLY-FAILING (1)
(`dependency_audit` only), and the four "NOT wired" bullets for
`web_search` / `documentation_search` / `api_reference_search` /
`package_search` are replaced by the wired behaviour (see §1–§4
above; the ddg-api.herokuapp.com note stays as history: Legacy
called it, the port does not).

## 7. Tests

`swiftcode/Tests/SwiftCodeMCPTests/SearchToolsGapTests.swift` — 22 tests,
all against canned HTTP fixtures via `StubSearchProtocol`
(`URLProtocol`, the `StubGitHubProtocol` shape) and
`SearchWebTestTransport.session`. No live network, no real
credential. Counted from `@Test` functions:

| Area | Tests | Covers |
|---|---|---|
| DDG parsing (pure) | 3 | Abstract/topics/nested `Topics` groups flattened, duplicate URLs dropped; garbage rejected; search URL is the keyless Instant Answer endpoint |
| `web_search` handler (stubbed) | 5 | Instant-answer success (structured count, abstract, URLs, one request to `api.duckduckgo.com`); `limit` respected; empty Instant Answer fails honestly naming keyed providers and "No results were invented"; HTTP 500 surfaced; missing query |
| DocC search (stubbed) | 5 | Dotted query resolves and fetches (`SwiftUI.View` → View page with abstract + `iOS 13.0+`); `api_reference_search` drops an article-kind page while `documentation_search` returns it; framework-root title matches add candidates (View + View Fundamentals, not Button); single-token query without framework fails honestly; unresolvable candidate fails honestly |
| DocC scoring (pure) | 1 | Exact title > title+abstract match > no match |
| SPI parsing (pure) | 2 | Two-entry list, stars `3,802` → `3802`, activity, `&amp;` decoded; absent list → empty |
| GitHub parsing (pure) | 1 | Items extracted; non-search JSON → nil |
| `package_search` handler (stubbed) | 5 | SPI preferred, no GitHub request made; SPI 500 → GitHub fallback with `github-search` source and the not-index-verified label; both backends empty → count 0, not an error; SPI 500 + GitHub 403 rate-limit → honest failure naming both; missing query |

The handlers are driven directly (`host.searchWeb(...)` etc.),
not through `server.callTool`: the four registrations still point
at Wave 8's honest-fail handlers until the coordinator applies
the §6 patch. The registration itself (IDs, Legacy descriptions,
schemas) stays covered by
`SwiftCodeAgenticNetworkTests.toolsAreRegisteredWithLegacySchemas`;
these tests cover the new behaviour the patch wires in. After the
patch lands, the same tests should additionally be driven through
`server.callTool` on Dylan's Mac to prove the wiring (a
follow-up for the coordinator, not a second implementation).

No Swift toolchain exists in this environment, so `swift build` /
`swift test` stay pending on Dylan's Mac; the checks run here are
delimiter balance on all touched files, a secrets/TODO scan, and
`scan-public` (see the slice report).

## 8. Files changed (destination only, uncommitted)

- NEW `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+SearchWebSupport.swift`
  — `SearchWebTestTransport`, `SearchHTTP`, `SearchText`,
  `SearchWebDDG`, `SearchDocs`, `SearchPackages` (+ hit types).
- NEW `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+SearchWeb.swift` —
  `searchWeb`, `searchDocumentation`, `searchAPIReference`,
  `searchDocs`, `searchPackage` handlers (+ failure mappers).
- MODIFIED `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+EnginesSupport.swift`
  — `EnginesHTTP.fetch` gains optional `session: URLSession? = nil`
  (backwards-compatible; production behaviour unchanged).
- NEW `swiftcode/Tests/SwiftCodeMCPTests/SearchToolsGapTests.swift` —
  22 tests + `StubSearchProtocol`.
- NEW `specs/ide/gap-closure-search.md` — this file.
- NOT touched (verified, no change needed):
  `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Search.swift` (workspace
  search tools — a different family; the web/doc/package tools
  are Agentic-network tools), `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+SPMDocs.swift`
  (manifest/dependency tools — `package_search` is a network index
  search, not a manifest tool), `swiftcode/Package.swift` (no new
  target: the new files join the existing `SwiftCodeMCP` target and
  the test joins `SwiftCodeMCPTests` by SwiftPM globbing),
  `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+AgenticNetwork.swift`
  (coordinator-owned; §6 patch delivered instead), the ledger,
  the manifest, Legacy, SwiftCode-New.

## 9. Honestly unavailable / what Dylan must supply

- A full ranked web search. The keyless surface is the DuckDuckGo
  Instant Answer API (summaries for topics that have one). Brave
  Search API, Bing Web Search API, and Google Custom Search all
  need keys Dylan has not supplied. If he supplies one, the
  `web_search` handler gains a keyed provider behind the same
  shape; the honest-failure message already names the three.
- Full-text Apple documentation search. Apple publishes no public
  search API; the site's internal search host 404s on every
  guessed path. DocC search here is candidate resolution plus the
  framework root's curated `references` index — it answers
  "SwiftUI View" and "View + SwiftUI", not free-text questions
  like "how do I make a list in SwiftUI". Single-token queries
  without a framework fail honestly and say so.
- SPI's JSON API needs authentication (401 without it). Package
  search parses the public search page instead; if SPI changes its
  markup, the parser yields zero entries and the GitHub fallback
  answers — the tool degrades, it does not invent.
- GitHub search is unauthenticated (10 requests/minute). The Wave
  10 GitHub token is not reused here; wiring it in is a follow-up
  if the rate limit ever bites.
- Mac `swift build` / `swift test` for everything in §8, plus the
  §6 rewiring patch applied and the §7 tests re-driven through
  `server.callTool` to prove the wiring.

## 10. Evidence

- Level 1 (public documentation / public APIs): DuckDuckGo
  Instant Answer API (documented public API, no key);
  Swift Package Index search page and GitHub repository search API
  (public, keyless); Apple DocC render JSON (the data backing the
  public documentation site, already used by
  `fetch_documentation`); Legacy's four tool files (Dylan's own
  code, direct porting authorised under MIT).
- Level 2 (live endpoint behaviour, probed 2026-11-06): every
  status code, payload shape, and failure in §0 (DDG html/lite
  202 + challenge page; DDG Instant Answer 200 with abstract +
  17 topics; SPI `/api/search` 401; SPI search page 200 with
  `<ul id="package-list">`; GitHub search 200 with
  `total_count` 77; DocC `swiftui.json` 200 with 73 references
  and `view.json` 200 with `"kind": "symbol"`; Apple internal
  search host 404 on guessed paths; Brave/Bing HTML 200 but
  rejected as backends for the reasons in §0).
- No reference Xcode copy, Ghidra, simulator IPSW,
  `research/dirty/`, or Apple Xcode/Simulator observation was
  opened, read, or run. No Apple code or code-shaped text enters
  `swiftcode/` or `specs/`. No real API key, token, or secret appears
  anywhere in this slice's files.
