import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Search-web support (gap-closure wave, family 3: SEARCH TOOLS)
//
// The four Agentic search tools (`web_search`,
// `documentation_search`, `api_reference_search`, `package_search`)
// shipped in Wave 8 as honest failures: Legacy's `WebSearch` called
// an unofficial DuckDuckGo proxy (`ddg-api.herokuapp.com`) that is
// not a supported search backend, and the other three returned
// canned strings without searching anything. This file wires each
// tool to a real, keyless, public endpoint — verified live from this
// environment on 2026-11-06 (see `specs/ide/gap-closure-search.md`
// for the full evidence table) — and fails honestly where no such
// endpoint exists.
//
// Behaviour source: Legacy
// `SwiftCode/Tools/Agentic/WebSearch.swift`,
// `DocumentationSearch.swift`, `APIReferenceSearch.swift`,
// `PackageSearch.swift` (Dylan's own code, ported under MIT).
// Legacy's IDs, descriptions, and required parameters are kept
// verbatim; each tool gains optional parameters only
// (`framework`/`limit`), the Wave 10 `repository` precedent.
//
// Endpoints (all keyless, all verified live 2026-11-06):
//
// * `web_search` — DuckDuckGo Instant Answer API
//   (`api.duckduckgo.com/?q=…&format=json`): a documented public
//   API, no key. It answers topics with a summary (abstract,
//   related topics, instant-answer results); it is NOT a full
//   ranked web search. DuckDuckGo's `html`/`lite` result pages are
//   bot-gated in this environment (HTTP 202 + a "complete the
//   challenge" page) and are deliberately NOT scraped: the
//   challenge must not be solved, and scraping a bot-gated page
//   would violate its terms. When the Instant Answer API has
//   nothing for a query, the tool fails honestly and names the
//   keyed providers that would answer it (Brave Search API, Bing
//   Web Search API, Google Custom Search) instead of inventing
//   results.
// * `documentation_search` / `api_reference_search` — Apple's
//   published DocC render JSON (`developer.apple.com/tutorials/
//   data/<path>.json`), the same path `fetch_documentation` uses
//   (`EnginesDocs` / `EnginesHTTP` in
//   `SwiftCodeTools+EnginesSupport.swift`). Apple publishes no public
//   full-text documentation search API: the developer site's
//   search runs on an undocumented internal host whose guessed
//   paths 404, so it is not used. Search here is candidate
//   resolution (`EnginesDocs.resolveCandidates`) plus a title
//   search over a framework root page's `references` index, with
//   each candidate fetched as DocC JSON and ranked by title /
//   abstract match. `api_reference_search` keeps only pages whose
//   DocC `kind` is `symbol`.
// * `package_search` — the Swift Package Index search page
//   (`swiftpackageindex.com/search?query=…`, server-rendered HTML,
//   parsed, never invented) with the GitHub public repository
//   search API (`api.github.com/search/repositories`, keyless
//   JSON) as fallback. SPI's JSON API (`/api/search`) answers
//   401 without authentication, so it is not used; the search
//   page is the reachable keyless surface of the index. GitHub
//   matches are repositories, not index-verified packages, and
//   are labelled as such.
//
// Conventions, following Waves 5/8:
//
// * HTTPS only, fixed hosts, 30 s timeouts, response caps
//   (1 MB web/SPI, 2 MB DocC/GitHub) instead of unbounded
//   buffering. Redirects stay on the endpoint's own host
//   (`EnginesHTTP`'s guard).
// * No result is ever invented. A backend that returns nothing
//   usable produces an honest failure (web/docs) or an empty
//   result with count 0 (package search: the index genuinely
//   has no match), never a canned string.
// * Pure parsing lives here so tests can drive it from canned
//   HTTP fixtures without a server; the network fetch goes
//   through `SearchHTTP.fetch`, which honours the test seam
//   (`SearchWebTestTransport.session`). No test performs a live
//   fetch and no test reads a real credential.
// * The DocC search deliberately does NOT use
//   `fetchDocumentationCandidate` (`SwiftCodeTools+Engines.swift`):
//   that helper has no transport seam, so tests could not stub
//   it. The candidate fetch here is the same DocC-JSON shape
//   (same URL, same cap, same parser) with the seam threaded
//   through, and no `EnginesDocCache` entry (search results are
//   not re-fetched per page the way `fetch_documentation` is).

// MARK: - Transport seam (tests only)

/// The URLSession the search fetchers use when set; nil in
/// production (the fetchers then build their own ephemeral session
/// with the redirect guard, exactly like `EnginesHTTP.fetch`).
/// Tests install a `URLProtocol`-backed session here
/// (`SearchToolsGapTests`) and reset it in `defer`, the
/// `gitHubTestSession` shape from Wave 10.
enum SearchWebTestTransport {
    nonisolated(unsafe) static var session: URLSession?
}

/// The search fetchers' HTTP layer: `EnginesHTTP.fetch` with the
/// test seam threaded through.
enum SearchHTTP {
    static let userAgent = "SwiftCode-MCP/1.0"

    static func fetch(_ request: URLRequest, maxBytes: Int, allowedHosts: Set<String>) async throws -> EnginesFetchedResponse {
        try await EnginesHTTP.fetch(request, maxBytes: maxBytes, allowedHosts: allowedHosts,
                                    session: SearchWebTestTransport.session)
    }

    /// A GET with a timeout and a User-Agent, ready to fetch.
    static func get(_ url: URL, accept: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        return request
    }
}

// MARK: - Shared text helpers

enum SearchText {
    /// Query terms: lowercased words, punctuation stripped.
    static func terms(of query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Decodes the HTML entities a search page can put in a name or
    /// summary (`&amp;`, `&hellip;`, `&#39;`, `&#x27;`, …). Unknown
    /// entities are left as-is rather than dropped.
    static func decodeEntities(_ text: String) -> String {
        var out = text
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                               "&apos;": "'", "&nbsp;": " ", "&hellip;": "…", "&ldquo;": "“",
                               "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’",
                               "&ndash;": "–", "&mdash;": "—"] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#NNN; and &#xHH;.
        for (pattern, radix) in [("&#(\\d+);", 10), ("&#x([0-9a-fA-F]+);", 16)] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out as NSString
            var result = ""
            var cursor = 0
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                let whole = match.range
                guard whole.location >= cursor, match.numberOfRanges > 1,
                      match.range(at: 1).location != NSNotFound else { continue }
                let digits = ns.substring(with: match.range(at: 1))
                let value = Int(digits, radix: radix) ?? 0
                // `UnicodeScalar` has no `Int` initializer: convert
                // only in range (digits are unsigned, so `value` is
                // never negative; anything past U+10FFFF is not a
                // scalar and decodes to nothing).
                let scalar = (value <= 0x10FFFF ? UnicodeScalar(UInt32(value)) : nil).map { String($0) } ?? ""
                result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
                result += scalar
                cursor = whole.location + whole.length
            }
            result += ns.substring(from: cursor)
            out = result
        }
        return out
    }
}

// MARK: - web_search: DuckDuckGo Instant Answer API

/// One instant-answer result: the DuckDuckGo Instant Answer API's
/// `Results` / `RelatedTopics` entries, flattened.
struct SearchWebResult: Sendable {
    var text: String
    var url: String
}

/// The parsed DuckDuckGo Instant Answer payload.
struct SearchWebAnswer: Sendable {
    var abstract: String
    var abstractURL: String
    var abstractSource: String
    var answer: String
    var results: [SearchWebResult]
}

enum SearchWebDDG {
    static let host = "api.duckduckgo.com"
    static let allowedHosts: Set<String> = [host]
    static let maxBytes = 1_000_000

    /// `https://api.duckduckgo.com/?q=…&format=json&no_html=1&skip_disambig=1`.
    static func searchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        return components.url
    }

    /// Parses the Instant Answer JSON: the abstract, the direct
    /// answer, `Results`, and `RelatedTopics` (whose groups nest
    /// their topics under `Topics`). Entries without a URL are
    /// dropped; duplicates are removed, first occurrence wins.
    static func parse(data: Data) -> SearchWebAnswer? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let abstract = (root["AbstractText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let abstractURL = (root["AbstractURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let abstractSource = (root["AbstractSource"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = (root["Answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [SearchWebResult] = []
        var seenURLs = Set<String>()
        func add(text: String?, url: String?) {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
                  !seenURLs.contains(url) else { return }
            seenURLs.insert(url)
            results.append(SearchWebResult(text: text, url: url))
        }
        if let direct = root["Results"] as? [[String: Any]] {
            for entry in direct { add(text: entry["Text"] as? String, url: entry["FirstURL"] as? String) }
        }
        if let topics = root["RelatedTopics"] as? [[String: Any]] {
            for entry in topics {
                if let nested = entry["Topics"] as? [[String: Any]] {
                    for sub in nested { add(text: sub["Text"] as? String, url: sub["FirstURL"] as? String) }
                } else {
                    add(text: entry["Text"] as? String, url: entry["FirstURL"] as? String)
                }
            }
        }
        return SearchWebAnswer(abstract: abstract, abstractURL: abstractURL, abstractSource: abstractSource,
                               answer: answer, results: results)
    }

    /// Fetches the Instant Answer payload for `query`. Throws
    /// `EnginesHTTPError.rateLimited` on 429 so the handler can say
    /// so; any other non-2xx is `badStatus`.
    static func search(query: String) async throws -> SearchWebAnswer {
        guard let url = searchURL(query: query) else {
            throw EnginesHTTPError.invalidURL("Could not build a DuckDuckGo Instant Answer URL for query '\(query)'.")
        }
        let fetched = try await SearchHTTP.fetch(SearchHTTP.get(url, accept: "application/json"),
                                                 maxBytes: maxBytes, allowedHosts: allowedHosts)
        guard (200...299).contains(fetched.status) else {
            if fetched.status == 429 { throw EnginesHTTPError.rateLimited }
            throw EnginesHTTPError.badStatus(fetched.status)
        }
        guard let answer = parse(data: fetched.data) else {
            throw EnginesHTTPError.invalidResponse
        }
        return answer
    }
}

// MARK: - documentation_search / api_reference_search: DocC JSON search

/// One documentation search hit: a fetched DocC page, ranked.
struct SearchDocsHit: Sendable {
    var title: String
    var url: String
    var abstract: String
    var availability: String
    /// The DocC `kind` of the page (`symbol`, `article`, …).
    var kind: String
    /// Rank score; higher is a better title/abstract match.
    var score: Int
}

enum SearchDocs {
    static let maxBytes = 2_000_000

    /// DocC `kind` values that are API references. DocC marks every
    /// API symbol page `symbol` (types, methods, properties,
    /// operators, macros alike); articles are `article`, overviews
    /// `overview`, sample code `sampleCode`.
    static let symbolKinds: Set<String> = ["symbol"]

    /// The DocC `kind` of a render-JSON payload (`symbol`,
    /// `article`, …), or nil when the payload has none.
    static func doccKind(data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["kind"] as? String
    }

    /// Fetches one candidate's DocC JSON and parses it into a page.
    /// Returns nil when the JSON 404s or does not parse as DocC
    /// (the candidate simply does not resolve); 429 fails fast;
    /// other statuses are recorded by the caller via the thrown
    /// error. The DocC-JSON shape (URL, cap, parser) is
    /// `fetch_documentation`'s, with the test seam threaded through
    /// and no response cache.
    static func fetchPage(candidate: EnginesDocs.Candidate) async throws -> (page: EnginesDocs.Page, kind: String)? {
        let fetched = try await SearchHTTP.fetch(
            SearchHTTP.get(candidate.doccJSONURL, accept: "application/json"),
            maxBytes: maxBytes, allowedHosts: EnginesDocs.appleHosts)
        guard (200...299).contains(fetched.status) else {
            if fetched.status == 429 { throw EnginesHTTPError.rateLimited }
            if fetched.status == 404 { return nil }
            throw EnginesHTTPError.badStatus(fetched.status)
        }
        guard let page = EnginesDocs.parseDocCJSON(data: fetched.data, canonicalURL: candidate.canonicalURL,
                                                   finalJSONURL: fetched.finalURL, language: "swift",
                                                   includeExamples: false) else {
            return nil
        }
        return (page, doccKind(data: fetched.data) ?? "")
    }

    /// The framework root page's `references` entries whose title
    /// matches the query terms, as extra candidates. The root JSON
    /// is a curated index (SwiftUI's lists 73 references, only 7
    /// of them symbols), so this supplements candidate resolution
    /// rather than replacing it. Returns at most 6 candidates.
    static func referenceCandidates(framework: String, terms: [String], data: Data) -> [EnginesDocs.Candidate] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let references = root["references"] as? [String: Any] else { return [] }
        let rootPath = "/documentation/\(framework.lowercased().replacingOccurrences(of: " ", with: ""))"
        var found: [EnginesDocs.Candidate] = []
        for (_, value) in references {
            guard let ref = value as? [String: Any],
                  let urlString = ref["url"] as? String,
                  urlString.hasPrefix("/documentation/"),
                  urlString.lowercased() != rootPath,
                  let title = ref["title"] as? String else { continue }
            let haystack = (title + " " + urlString).lowercased()
            guard terms.contains(where: { haystack.contains($0) }) else { continue }
            let docPath = String(urlString.dropFirst())
            let candidate = EnginesDocs.Candidate(docPath: docPath)
            if !found.contains(where: { $0.docPath == candidate.docPath }) {
                found.append(candidate)
            }
            if found.count >= 6 { break }
        }
        return found
    }

    /// Scores a fetched page against the query terms: an exact
    /// title match wins, then all terms in the title, then any
    /// term in the title, plus one when all terms appear in the
    /// abstract. Every fetched candidate is kept (a path-resolved
    /// candidate is relevant even at score 0); the score only
    /// orders the results.
    static func score(title: String, abstract: String, query: String, terms: [String]) -> Int {
        let titleLower = title.lowercased()
        let abstractLower = abstract.lowercased()
        var score = 0
        if titleLower == query.lowercased() {
            score += 3
        } else if !terms.isEmpty && terms.allSatisfy({ titleLower.contains($0) }) {
            score += 2
        } else if terms.contains(where: { titleLower.contains($0) }) {
            score += 1
        }
        if !terms.isEmpty && !abstract.isEmpty && terms.allSatisfy({ abstractLower.contains($0) }) {
            score += 1
        }
        return score
    }

    /// Searches Apple's published DocC data for `query`. Resolves
    /// candidates from the query (+ optional framework), adds
    /// title matches from the framework root's `references` index
    /// when a framework is given, fetches each candidate's DocC
    /// JSON, and ranks the pages. When `symbolOnly` is true
    /// (`api_reference_search`) only `symbol`-kind pages are kept.
    /// Throws `EnginesHTTPError.invalidURL` when no candidate can
    /// be resolved at all (single-token query, no framework), and
    /// returns an empty array when candidates resolve but none
    /// fetches as a page.
    static func search(query: String, framework: String?, symbolOnly: Bool) async throws -> [SearchDocsHit] {
        let candidates = try EnginesDocs.resolveCandidates(query: query, urlString: "", framework: framework)
        var ordered = candidates
        let terms = SearchText.terms(of: query)
        if let framework, !framework.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let root = EnginesDocs.Candidate(docPath: "documentation/\(framework.lowercased().replacingOccurrences(of: " ", with: ""))")
            if let fetched = try? await SearchHTTP.fetch(
                SearchHTTP.get(root.doccJSONURL, accept: "application/json"),
                maxBytes: maxBytes, allowedHosts: EnginesDocs.appleHosts),
               (200...299).contains(fetched.status) {
                for extra in referenceCandidates(framework: framework, terms: terms, data: fetched.data) {
                    if !ordered.contains(where: { $0.docPath == extra.docPath }) {
                        ordered.append(extra)
                    }
                }
            }
            // A framework-root fetch failure is not fatal: the
            // resolved candidates below still run.
        }
        // The framework root page itself is the index, not a
        // result: do not fetch it as a hit when other candidates
        // exist. (When the query IS the framework name it is the
        // only candidate, and it stays.)
        if let framework, !framework.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ordered.count > 1 {
            let rootPath = "documentation/\(framework.lowercased().replacingOccurrences(of: " ", with: ""))"
            ordered.removeAll { $0.docPath == rootPath }
        }
        var hits: [SearchDocsHit] = []
        for candidate in ordered {
            try Task.checkCancellation()
            do {
                guard let (page, kind) = try await fetchPage(candidate: candidate) else { continue }
                if symbolOnly && !symbolKinds.contains(kind) { continue }
                hits.append(SearchDocsHit(
                    title: page.title,
                    url: page.canonicalURL.absoluteString,
                    abstract: page.abstract,
                    availability: page.availability.first ?? "",
                    kind: kind,
                    score: score(title: page.title, abstract: page.abstract, query: query, terms: terms)))
            } catch let error as EnginesHTTPError {
                switch error {
                case .rateLimited:
                    throw error
                default:
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return hits.sorted { ($0.score, $0.title) > ($1.score, $1.title) }
    }
}

// MARK: - package_search: Swift Package Index + GitHub search

/// One package search hit, from either backend.
struct SearchPackageHit: Sendable {
    var name: String
    var identifier: String
    var summary: String
    var stars: Int?
    var activity: String
    /// The package's page on the backend that returned it.
    var url: String
}

enum SearchPackages {
    static let spiHost = "swiftpackageindex.com"
    static let spiAllowedHosts: Set<String> = [spiHost]
    static let gitHubHost = "api.github.com"
    static let gitHubAllowedHosts: Set<String> = [gitHubHost]
    static let maxBytes = 1_000_000

    /// `https://swiftpackageindex.com/search?query=…`.
    static func spiSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = spiHost
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        return components.url
    }

    /// `https://api.github.com/search/repositories?q=<query>
    /// language:swift&sort=stars&order=desc&per_page=<limit>`.
    static func gitHubSearchURL(query: String, limit: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = gitHubHost
        components.path = "/search/repositories"
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(query) language:swift"),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: String(limit)),
        ]
        return components.url
    }

    /// Parses the Swift Package Index search page: the
    /// `<ul id="package-list">` entries. Each entry is
    /// `<li><a href="/owner/repo"><h4>name</h4><p>summary</p>`
    /// plus a `<ul class="metadata">` with the `owner/repo`
    /// identifier, the activity line, and the star count. Returns
    /// an empty array when the list is absent or unparseable (the
    /// caller falls back to GitHub rather than guessing whether
    /// that means "no matches" or "markup drift").
    static func parseSPIHTML(_ html: String) -> [SearchPackageHit] {
        guard let listRange = html.range(of: "<ul id=\"package-list\">") else { return [] }
        let section = String(html[listRange.upperBound...])
        guard let headerRegex = try? NSRegularExpression(
            pattern: "<li><a href=\"(/[^\\\"]+)\"><h4>([^<]+)</h4><p>([^<]*)</p>",
            options: [.dotMatchesLineSeparators]),
              let starsRegex = try? NSRegularExpression(pattern: "class=\"stars\"><small>([\\d,]+) stars</small>"),
              let activityRegex = try? NSRegularExpression(pattern: "class=\"activity\"><small>([^<]+)</small>"),
              let identifierRegex = try? NSRegularExpression(pattern: "class=\"identifier\"><small>([^<]+)</small>") else {
            return []
        }
        let nsSection = section as NSString
        let headers = headerRegex.matches(in: section, range: NSRange(location: 0, length: nsSection.length))
        var hits: [SearchPackageHit] = []
        for (index, header) in headers.enumerated() {
            guard header.numberOfRanges >= 4,
                  let hrefRange = Range(header.range(at: 1), in: section),
                  let nameRange = Range(header.range(at: 2), in: section),
                  let summaryRange = Range(header.range(at: 3), in: section) else { continue }
            let href = String(section[hrefRange])
            let name = SearchText.decodeEntities(String(section[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            let summary = SearchText.decodeEntities(String(section[summaryRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            // The entry's metadata runs until the next entry header
            // (or the end of the list section).
            let spanStart = header.range.location + header.range.length
            let spanEnd = index + 1 < headers.count ? headers[index + 1].range.location : nsSection.length
            guard spanEnd > spanStart else { continue }
            let span = nsSection.substring(with: NSRange(location: spanStart, length: spanEnd - spanStart))
            let nsSpan = span as NSString
            func first(_ regex: NSRegularExpression, group: Int = 1) -> String? {
                guard let m = regex.firstMatch(in: span, range: NSRange(location: 0, length: nsSpan.length)),
                      m.numberOfRanges > group,
                      let r = Range(m.range(at: group), in: span) else { return nil }
                return String(span[r])
            }
            let identifier = first(identifierRegex) ?? String(href.dropFirst())
            let activity = first(activityRegex) ?? ""
            let starsText = first(starsRegex)?.replacingOccurrences(of: ",", with: "")
            hits.append(SearchPackageHit(
                name: name,
                identifier: identifier,
                summary: summary,
                stars: starsText.flatMap { Int($0) },
                activity: activity,
                url: "https://\(spiHost)\(href)"))
        }
        return hits
    }

    /// Parses the GitHub repository search JSON: `items[]` with
    /// `full_name`, `description`, `stargazers_count`,
    /// `html_url`. Returns nil when the payload is not a search
    /// result at all.
    static func parseGitHubJSON(_ data: Data) -> [SearchPackageHit]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item -> SearchPackageHit? in
            guard let fullName = item["full_name"] as? String,
                  let htmlURL = item["html_url"] as? String else { return nil }
            let name = (fullName.split(separator: "/").last.map(String.init)) ?? fullName
            return SearchPackageHit(
                name: name,
                identifier: fullName,
                summary: (item["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                stars: item["stargazers_count"] as? Int,
                activity: "",
                url: htmlURL)
        }
    }

    /// Fetches the Swift Package Index search page and parses it.
    /// Returns nil on any non-2xx status (the caller falls back to
    /// GitHub); throws only on transport failure.
    static func searchSPI(query: String) async throws -> [SearchPackageHit]? {
        guard let url = spiSearchURL(query: query) else { return nil }
        let fetched = try await SearchHTTP.fetch(SearchHTTP.get(url, accept: "text/html"),
                                                 maxBytes: maxBytes, allowedHosts: spiAllowedHosts)
        guard (200...299).contains(fetched.status) else { return nil }
        guard let html = String(data: fetched.data, encoding: .utf8) else { return [] }
        return parseSPIHTML(html)
    }

    /// Fetches the GitHub public repository search for Swift
    /// repositories matching `query`. Unauthenticated search is
    /// rate-limited (10 requests/minute); a 403 whose body says
    /// "rate limit" and a 429 both surface as
    /// `EnginesHTTPError.rateLimited`.
    static func searchGitHub(query: String, limit: Int) async throws -> [SearchPackageHit] {
        guard let url = gitHubSearchURL(query: query, limit: limit) else {
            throw EnginesHTTPError.invalidURL("Could not build a GitHub search URL for query '\(query)'.")
        }
        var request = SearchHTTP.get(url, accept: "application/vnd.github+json")
        request.setValue("SwiftCode-MCP/1.0", forHTTPHeaderField: "User-Agent")
        let fetched = try await SearchHTTP.fetch(request, maxBytes: 2_000_000, allowedHosts: gitHubAllowedHosts)
        if fetched.status == 429 { throw EnginesHTTPError.rateLimited }
        if fetched.status == 403 {
            let body = String(data: fetched.data, encoding: .utf8) ?? ""
            if body.localizedCaseInsensitiveContains("rate limit") { throw EnginesHTTPError.rateLimited }
            throw EnginesHTTPError.badStatus(403)
        }
        guard (200...299).contains(fetched.status) else {
            throw EnginesHTTPError.badStatus(fetched.status)
        }
        guard let hits = parseGitHubJSON(fetched.data) else {
            throw EnginesHTTPError.invalidResponse
        }
        return hits
    }

    /// Searches for packages: the Swift Package Index first, the
    /// GitHub public repository search when the index page fails
    /// or yields no parseable entries. The returned source names
    /// the backend that answered (`swift-package-index` or
    /// `github-search`). An empty array means the backends that
    /// answered found no match — never an invented result.
    static func search(query: String, limit: Int) async throws -> (hits: [SearchPackageHit], source: String) {
        var spiNote = "returned no usable results"
        do {
            if let spiHits = try await searchSPI(query: query), !spiHits.isEmpty {
                return (Array(spiHits.prefix(limit)), "swift-package-index")
            }
        } catch {
            // SPI transport failure: fall through to GitHub rather
            // than failing on the first backend, but remember why.
            spiNote = "fetch failed (\(error))"
        }
        do {
            let gitHubHits = try await searchGitHub(query: query, limit: limit)
            return (gitHubHits, "github-search")
        } catch let error as EnginesHTTPError {
            throw EnginesHTTPError.fetchFailed(
                "Swift Package Index \(spiNote); GitHub search failed (\(error)).")
        }
    }
}
