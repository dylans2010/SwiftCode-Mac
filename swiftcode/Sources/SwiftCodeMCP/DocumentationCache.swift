import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Offline documentation cache (Wave 19 slice A)
//
// The 57-topic offline cache for the Documentation Browser. Legacy
// bundled a 476-file `Documentation Assets` tree (Apple Xcode
// framework `Resources/` + Apple documentation content copied
// verbatim) — dropped, not copied. The rewrite fetches the same 57
// topics live from the public DocC endpoints the destination
// already uses, stores the raw payloads locally, and serves them
// offline from the cache.
//
// Fetch path (no new HTTP client, no new endpoint):
// `EnginesDocs.resolveCandidates` → `SearchHTTP.fetch` (the
// `SearchWebTestTransport.session` seam for tests) →
// `EnginesDocs.parseDocCJSON`. When no resolved candidate fetches,
// the builder falls back to `SearchDocs.search` (framework-root
// `references` index + ranking) and fetches the best exact-title
// hit. A topic that resolves through neither path is recorded
// `failed` with the reason — the batch never fails whole for one
// topic, and a failed topic is never invented.
//
// Layout (Application Support, the `LibraryCodeSnippetStore`
// convention): `SwiftCode/DocumentationCache/index.json` +
// `pages/<slug>.json` (one raw DocC JSON payload per cached topic).
// The index is JSON, not Legacy's sqlite: 57 rows need no FTS5
// index, in-memory filtering is instant, and the destination has
// no sqlite writer in this layer (its only `SQLiteDatabase` is the
// HealthStore's). Legacy's sqlite schema is documented in
// `specs/ide/wave19-docs.md` §8 as the reference format.
//
// Spec: `specs/ide/wave19-docs.md` §§3–5, 7.

/// One topic's entry in the cache index.
public struct DocumentationCacheTopic: Codable, Sendable, Hashable {
    public var name: String
    public var kind: String
    public var framework: String
    /// Real DocC path without the leading slash, e.g.
    /// "documentation/swiftui/vstack".
    public var docPath: String
    public var canonicalURL: URL?
    public var fetchedAt: Date?
    public var status: Status
    /// Why the topic is not cached (only when `status == .failed`).
    public var failure: String?

    public enum Status: String, Codable, Sendable {
        case cached
        case failed
    }

    public init(
        name: String, kind: String, framework: String, docPath: String,
        canonicalURL: URL? = nil, fetchedAt: Date? = nil,
        status: Status, failure: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.framework = framework
        self.docPath = docPath
        self.canonicalURL = canonicalURL
        self.fetchedAt = fetchedAt
        self.status = status
        self.failure = failure
    }
}

/// The cache index file (`index.json`).
public struct DocumentationCacheIndex: Codable, Sendable {
    public var version: Int
    public var fetchedAt: Date?
    public var topics: [DocumentationCacheTopic]

    public init(version: Int = 1, fetchedAt: Date? = nil, topics: [DocumentationCacheTopic] = []) {
        self.version = version
        self.fetchedAt = fetchedAt
        self.topics = topics
    }
}

/// The result of fetching one catalogue topic.
public struct DocumentationFetchResult: Sendable {
    public var topic: DocCatalogueTopic
    public var cached: Bool
    public var failure: String?
    public var canonicalURL: URL?

    public init(topic: DocCatalogueTopic, cached: Bool, failure: String? = nil, canonicalURL: URL? = nil) {
        self.topic = topic
        self.cached = cached
        self.failure = failure
        self.canonicalURL = canonicalURL
    }
}

/// The offline documentation cache. An actor: `fetchAll` updates
/// the index after each topic, and concurrent fetches must not
/// interleave the read-modify-write.
public actor DocumentationCache {
    public static let shared = DocumentationCache()

    /// The cache root. Production: Application
    /// Support/SwiftCode/DocumentationCache. Tests inject a temp
    /// directory.
    public let directory: URL?

    public init(directory: URL? = DocumentationCache.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent("DocumentationCache", isDirectory: true)
    }

    // MARK: - Paths

    public var indexURL: URL? { directory?.appendingPathComponent("index.json") }

    public func pageURL(for name: String) -> URL? {
        directory?.appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent(Self.slug(for: name) + ".json")
    }

    /// The page-file slug for a topic name.
    public static func slug(for name: String) -> String { name.lowercased() }

    // MARK: - Index

    public func loadIndex() -> DocumentationCacheIndex? {
        guard let url = indexURL,
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(DocumentationCacheIndex.self, from: data) else {
            return nil
        }
        return index
    }

    public func saveIndex(_ index: DocumentationCacheIndex) {
        guard let url = indexURL,
              let data = try? JSONEncoder().encode(index) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Cached / failed / total counts and the last fetch date, for
    /// the browser's status pill. No cache yet reads as 0/0/57.
    public func cacheStatus() -> (cached: Int, failed: Int, total: Int, lastFetch: Date?) {
        let index = loadIndex()
        let topics = index?.topics ?? []
        return (topics.filter { $0.status == .cached }.count,
                topics.filter { $0.status == .failed }.count,
                DocumentationCatalogue.topics.count,
                index?.fetchedAt)
    }

    // MARK: - Loading symbols from the cache

    /// Builds `[DocSymbol]` from the index + stored page payloads.
    /// A topic whose page file is missing or unparseable is skipped
    /// (never a crash, never an invented symbol). Sorted by name,
    /// as Legacy did. Returns `[]` when nothing is cached yet.
    public func loadSymbols() -> [DocSymbol] {
        guard let index = loadIndex() else { return [] }
        var symbols: [DocSymbol] = []
        for entry in index.topics where entry.status == .cached {
            guard let url = pageURL(for: entry.name),
                  let data = try? Data(contentsOf: url),
                  let topic = DocumentationCatalogue.topics.first(where: { $0.name == entry.name }),
                  let symbol = Self.symbol(from: data, topic: topic, canonicalURL: entry.canonicalURL) else {
                continue
            }
            symbols.append(symbol)
        }
        symbols.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return symbols
    }

    /// The cached page payload for a DocC path, if the topic is
    /// cached. `docPath` may carry a leading slash.
    public func pageData(forDocPath docPath: String) -> Data? {
        let clean = docPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard let index = loadIndex(),
              let entry = index.topics.first(where: {
                  $0.status == .cached && $0.docPath.lowercased() == clean
              }),
              let url = pageURL(for: entry.name) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    // MARK: - Fetching

    /// Fetches every catalogue topic, one at a time (polite: no
    /// parallel hammering of Apple's endpoint), updating the index
    /// after each topic so a crash keeps partial progress.
    /// `progress` reports (done, total, topic, result) after each
    /// topic; it runs on the main actor (the browser's model owns
    /// the progress state). Never throws for a topic failure — the
    /// result carries it; throws only when there is no cache
    /// directory at all.
    public func fetchAll(
        progress: (@MainActor (Int, Int, DocCatalogueTopic, DocumentationFetchResult) -> Void)? = nil
    ) async throws -> [DocumentationFetchResult] {
        guard directory != nil else {
            throw EnginesHTTPError.fetchFailed("No Application Support directory: the documentation cache has nowhere to live.")
        }
        var results: [DocumentationFetchResult] = []
        let topics = DocumentationCatalogue.topics
        for (offset, topic) in topics.enumerated() {
            let result = await fetchTopic(topic)
            results.append(result)
            record(result)
            await progress?(offset + 1, topics.count, topic, result)
            try Task.checkCancellation()
        }
        return results
    }

    /// Fetches one topic (candidates, then the search fallback),
    /// stores its raw DocC JSON, and records the outcome. Never
    /// throws for a fetch failure — the result carries it.
    public func fetchTopic(_ topic: DocCatalogueTopic) async -> DocumentationFetchResult {
        guard directory != nil else {
            return DocumentationFetchResult(topic: topic, cached: false,
                                            failure: "No Application Support directory.")
        }
        do {
            let candidates = try EnginesDocs.resolveCandidates(query: topic.name, urlString: "", framework: topic.framework)
            for candidate in candidates {
                do {
                    guard let data = try await fetchRawJSON(candidate: candidate) else {
                        continue // 404: this candidate does not resolve; try the next.
                    }
                    return store(topic: topic, data: data, candidate: candidate)
                } catch let error as EnginesHTTPError {
                    if case .rateLimited = error {
                        return DocumentationFetchResult(topic: topic, cached: false,
                                                        failure: "Apple documentation endpoint rate-limited the request. Try again shortly.")
                    }
                    continue // badStatus / tooLarge / timeout: try the next candidate.
                } catch {
                    continue
                }
            }
            // Fallback: the framework-root references index + ranking.
            if let hit = try? await SearchDocs.search(query: topic.name, framework: topic.framework, symbolOnly: false).first,
               hit.title.lowercased() == topic.name.lowercased()
                || URL(string: hit.url)?.lastPathComponent.lowercased() == topic.name.lowercased(),
               let hitURL = URL(string: hit.url) {
                let docPath = hitURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let candidate = EnginesDocs.Candidate(docPath: docPath)
                if let data = try? await fetchRawJSON(candidate: candidate) {
                    return store(topic: topic, data: data, candidate: candidate)
                }
            }
            return DocumentationFetchResult(
                topic: topic, cached: false,
                failure: "No DocC page resolved for '\(topic.name)' (\(topic.framework)): all \(candidates.count) candidate paths 404'd and the framework-index search found no exact-title match.")
        } catch let error as EnginesHTTPError {
            switch error {
            case .rateLimited:
                return DocumentationFetchResult(topic: topic, cached: false,
                                                failure: "Apple documentation endpoint rate-limited the request. Try again shortly.")
            case .invalidURL(let message):
                return DocumentationFetchResult(topic: topic, cached: false, failure: message)
            default:
                return DocumentationFetchResult(topic: topic, cached: false, failure: Self.describe(error))
            }
        } catch {
            return DocumentationFetchResult(topic: topic, cached: false, failure: error.localizedDescription)
        }
    }

    /// Fetches one candidate's raw DocC JSON. 404 → nil (the
    /// candidate does not resolve); 429 → `rateLimited`; other
    /// non-2xx → `badStatus`. The `SearchHTTP` seam applies, so
    /// tests stub this without a live fetch.
    private func fetchRawJSON(candidate: EnginesDocs.Candidate) async throws -> Data? {
        let fetched = try await SearchHTTP.fetch(
            SearchHTTP.get(candidate.doccJSONURL, accept: "application/json"),
            maxBytes: SearchDocs.maxBytes, allowedHosts: EnginesDocs.appleHosts)
        guard (200...299).contains(fetched.status) else {
            if fetched.status == 429 { throw EnginesHTTPError.rateLimited }
            if fetched.status == 404 { return nil }
            throw EnginesHTTPError.badStatus(fetched.status)
        }
        return fetched.data
    }

    /// Parses + converts a fetched payload, stores the raw JSON,
    /// and returns the fetch result. A payload that does not parse
    /// as DocC is a failure, not a cached topic.
    private func store(topic: DocCatalogueTopic, data: Data,
                       candidate: EnginesDocs.Candidate) -> DocumentationFetchResult {
        guard Self.symbol(from: data, topic: topic, canonicalURL: candidate.canonicalURL) != nil else {
            return DocumentationFetchResult(
                topic: topic, cached: false,
                failure: "The DocC JSON for '\(topic.name)' did not parse as documentation (schema drift guard).")
        }
        guard let url = pageURL(for: topic.name) else {
            return DocumentationFetchResult(topic: topic, cached: false,
                                            failure: "No Application Support directory.")
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return DocumentationFetchResult(topic: topic, cached: false,
                                            failure: "Could not write the cached page for '\(topic.name)': \(error.localizedDescription)")
        }
        return DocumentationFetchResult(topic: topic, cached: true, canonicalURL: candidate.canonicalURL)
    }

    /// Records one fetch result in the index (read-modify-write;
    /// the actor serializes concurrent fetchers).
    private func record(_ result: DocumentationFetchResult) {
        var index = loadIndex() ?? DocumentationCacheIndex()
        let entry = DocumentationCacheTopic(
            name: result.topic.name, kind: result.topic.kind, framework: result.topic.framework,
            docPath: result.canonicalURL.map {
                $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } ?? result.topic.docPath,
            canonicalURL: result.canonicalURL, fetchedAt: result.cached ? Date() : nil,
            status: result.cached ? .cached : .failed, failure: result.failure)
        if let at = index.topics.firstIndex(where: { $0.name == result.topic.name }) {
            index.topics[at] = entry
        } else {
            index.topics.append(entry)
        }
        index.fetchedAt = Date()
        saveIndex(index)
    }

    // MARK: - DocC JSON → DocSymbol

    /// Converts a fetched DocC JSON payload into a `DocSymbol`.
    /// Pure (no I/O): tests drive it from canned fixtures. Returns
    /// nil when the payload does not parse as DocC. `canonicalURL`
    /// is the fetched page's real URL (the search-fallback hit's
    /// path can differ from the catalogue's derived path); when
    /// nil it is derived from the topic.
    public nonisolated static func symbol(from data: Data, topic: DocCatalogueTopic, canonicalURL: URL? = nil) -> DocSymbol? {
        let candidate = EnginesDocs.Candidate(docPath: topic.docPath)
        let canonical = canonicalURL ?? candidate.canonicalURL
        guard let page = EnginesDocs.parseDocCJSON(data: data, canonicalURL: canonical,
                                                   finalJSONURL: candidate.doccJSONURL, language: "swift",
                                                   includeExamples: true),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let doccKind = (root["kind"] as? String) ?? ""
        let kind = inferKind(doccKind: doccKind, declarations: page.declarations)
        let platforms = parsePlatforms(page.availability, framework: topic.framework)
        let (inheritsFrom, conformsTo) = relationships(in: root)
        let codeSample: String = {
            guard let first = page.examples.first else { return "" }
            // Examples arrive fenced (```swift … ```) from the
            // parser; the sample is the code without the fence.
            // A page with no code listing has no sample — the UI
            // hides the section instead of showing a stub.
            var lines = first.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            return lines.joined(separator: "\n")
        }()
        return DocSymbol(
            name: topic.name, kind: kind, framework: topic.framework,
            summary: page.abstract,
            syntax: page.declarations.joined(separator: "\n"),
            platforms: platforms,
            inheritsFrom: inheritsFrom, conformsTo: conformsTo,
            codeSample: codeSample,
            availability: page.availability.joined(separator: ", "),
            seeAlso: page.relatedLinks.map { $0.title },
            docPath: "/" + (page.canonicalURL.path.isEmpty ? topic.docPath : String(page.canonicalURL.path.dropFirst("/")))
        )
    }

    /// DocC `kind` → the browser's kind. `article`/`overview` stay
    /// articles; a `symbol` infers from its first declaration line
    /// (Legacy's indexer rule); anything else defaults to
    /// `"class"`, Legacy's default.
    public nonisolated static func inferKind(doccKind: String, declarations: [String]) -> String {
        switch doccKind {
        case "article", "overview": return "article"
        case "symbol":
            guard let first = declarations.first else { return "class" }
            if first.contains("protocol ") { return "protocol" }
            if first.contains("struct ") { return "struct" }
            if first.contains("class ") { return "class" }
            if first.contains("func ") { return "func" }
            if first.contains("actor ") { return "actor" }
            if first.contains("macro ") { return "macro" }
            if first.contains("enum ") { return "enum" }
            return "class"
        default:
            return doccKind.isEmpty ? "class" : "article"
        }
    }

    /// `"iOS 13.0+"` entries → `[platform: version]` (version
    /// without the `+`). An entry with no version falls back to
    /// the framework default for that platform. Empty when the
    /// page lists no availability at all — then the caller uses
    /// the framework defaults wholesale.
    public nonisolated static func parsePlatforms(_ availability: [String], framework: String) -> [String: String] {
        guard !availability.isEmpty else {
            return DocumentationCatalogue.platformDefaults[framework] ?? [:]
        }
        var out: [String: String] = [:]
        for entry in availability {
            let parts = entry.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { continue }
            var version = parts.count > 1 ? parts[1] : ""
            if version.hasSuffix("+") { version = String(version.dropLast()) }
            if version.isEmpty {
                version = DocumentationCatalogue.platformDefaults[framework]?[name] ?? ""
            }
            if !version.isEmpty { out[name] = version }
        }
        return out
    }

    /// `relationshipsSections` → (inheritsFrom, conformsTo).
    /// The titles come from the `references` dictionary; an
    /// identifier with no reference is skipped, never invented.
    public nonisolated static func relationships(in root: [String: Any]) -> (String?, [String]) {
        guard let sections = root["relationshipsSections"] as? [[String: Any]],
              let references = root["references"] as? [String: Any] else {
            return (nil, [])
        }
        func titles(of sectionTitle: String) -> [String] {
            guard let section = sections.first(where: { ($0["title"] as? String) == sectionTitle }),
                  let identifiers = section["identifiers"] as? [String] else {
                return []
            }
            return identifiers.compactMap { ident in
                (references[ident] as? [String: Any])?["title"] as? String
            }
        }
        return (titles(of: "Inherits From").first, titles(of: "Conforms To"))
    }

    private static func describe(_ error: EnginesHTTPError) -> String {
        switch error {
        case .invalidURL(let message): return message
        case .timeout: return "Apple documentation endpoint timed out."
        case .rateLimited: return "Apple documentation endpoint rate-limited the request. Try again shortly."
        case .badStatus(let code): return "Apple documentation endpoint failed: HTTP \(code)."
        case .tooLarge(let max): return "Apple documentation endpoint failed: response exceeded the \(max)-byte cap."
        case .invalidResponse: return "Apple documentation endpoint failed: invalid HTTP response."
        case .fetchFailed(let message): return "Apple documentation endpoint failed: \(message)"
        }
    }

    // MARK: - DocC → HTML (the web pane's renderer)

    /// Renders a `docc://` path from the cache as a self-contained
    /// HTML page (no JavaScript, no external resources, no Apple
    /// CSS/JS — SwiftCode's own small renderer over the cached
    /// DocC JSON). The home path renders the framework list; an
    /// unknown path renders a 404 page naming the path; a topic
    /// whose page file is missing renders a "not cached yet" page.
    /// Related links become `docc://` links so navigation stays
    /// in-app.
    public func renderedHTML(docPath: String) -> String {
        let clean = docPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if clean.isEmpty || clean == "documentation" || clean == "documentation/developerdocumentation" {
            return homeHTML()
        }
        if let framework = DocumentationCatalogue.frameworks.first(where: {
            "documentation/" + $0.lowercased() == clean
        }) {
            return frameworkHTML(framework: framework)
        }
        guard let index = loadIndex(),
              let entry = index.topics.first(where: { $0.docPath.lowercased() == clean }) else {
            return notFoundHTML(path: docPath)
        }
        guard let data = pageData(forDocPath: clean),
              let topic = DocumentationCatalogue.topics.first(where: { $0.name == entry.name }),
              let symbol = Self.symbol(from: data, topic: topic, canonicalURL: entry.canonicalURL),
              let page = parsePage(data: data, topic: topic) else {
            return notCachedHTML(name: entry.name, framework: entry.framework)
        }
        return topicHTML(symbol: symbol, page: page)
    }

    private func parsePage(data: Data, topic: DocCatalogueTopic) -> EnginesDocs.Page? {
        let candidate = EnginesDocs.Candidate(docPath: topic.docPath)
        return EnginesDocs.parseDocCJSON(data: data, canonicalURL: candidate.canonicalURL,
                                         finalJSONURL: candidate.doccJSONURL, language: "swift",
                                         includeExamples: true)
    }

    private func frameworkHTML(framework: String) -> String {
        let topics = DocumentationCatalogue.topics.filter { $0.framework == framework }
        let index = loadIndex()
        let cachedHere = topics.filter { topic in
            index?.topics.contains { $0.name == topic.name && $0.status == .cached } == true
        }.count
        let links = topics.map { topic in
            "<li><a href=\"docc://developer.apple.com/\(topic.docPath)\">\(escape(topic.name))</a> — \(escape(topic.kind))</li>"
        }.joined(separator: "\n")
        return pageShell(title: framework, body: """
        <h1>\(escape(framework))</h1>
        <p>\(cachedHere) of \(topics.count) topics cached offline.</p>
        <ul>
        \(links)
        </ul>
        """)
    }

    private func homeHTML() -> String {
        let (cached, failed, total, _) = cacheStatus()
        var cards = ""
        for framework in DocumentationCatalogue.frameworks {
            let names = DocumentationCatalogue.topics.filter { $0.framework == framework }
            let links = names.map { topic in
                "<li><a href=\"docc://developer.apple.com/\(topic.docPath)\">\(escape(topic.name))</a></li>"
            }.joined(separator: "\n")
            cards += """
            <section><h2>\(escape(framework))</h2><ul>
            \(links)
            </ul></section>
            """
        }
        return pageShell(title: "Developer Documentation", body: """
        <h1>Developer Documentation</h1>
        <p>\(cached) of \(total) topics cached offline\(failed > 0 ? " (\(failed) failed to fetch)" : ""). Use the sidebar to browse, or download the full set from the browser's Download button.</p>
        \(cards)
        """)
    }

    private func topicHTML(symbol: DocSymbol, page: EnginesDocs.Page) -> String {
        var body = "<h1>\(escape(symbol.name))</h1>"
        body += "<p class=\"meta\">\(escape(symbol.kind)) · \(escape(symbol.framework)) · \(escape(symbol.availability))</p>"
        if !symbol.summary.isEmpty {
            body += "<p>\(escape(symbol.summary))</p>"
        }
        if !symbol.syntax.isEmpty {
            body += "<h2>Declaration</h2><pre><code>\(escape(symbol.syntax))</code></pre>"
        }
        if !page.discussion.isEmpty {
            body += "<h2>Discussion</h2><p>\(escape(page.discussion))</p>"
        }
        if !page.examples.isEmpty {
            body += "<h2>Examples</h2>"
            for example in page.examples {
                body += "<pre><code>\(escape(example))</code></pre>"
            }
        }
        if !page.relatedLinks.isEmpty {
            let links = page.relatedLinks.map { link in
                let docc = link.url
                    .replacingOccurrences(of: "https://developer.apple.com/", with: "docc://developer.apple.com/")
                    .replacingOccurrences(of: "http://developer.apple.com/", with: "docc://developer.apple.com/")
                return "<li><a href=\"\(escape(docc))\">\(escape(link.title))</a></li>"
            }.joined(separator: "\n")
            body += "<h2>See Also</h2><ul>\(links)</ul>"
        }
        body += "<p class=\"meta\"><a href=\"https://developer.apple.com\(escape(symbol.docPath))\">Open on developer.apple.com</a></p>"
        return pageShell(title: symbol.name, body: body)
    }

    private func notCachedHTML(name: String, framework: String) -> String {
        pageShell(title: name, body: """
        <h1>\(escape(name))</h1>
        <p>This topic (\(escape(framework))) is not cached offline yet. Use the browser's Download button to fetch the 57 offline topics, or search the live documentation instead.</p>
        """)
    }

    private func notFoundHTML(path: String) -> String {
        pageShell(title: "Not found", body: """
        <h1>Page not found</h1>
        <p>No cached documentation page matches <code>\(escape(path))</code>. The offline cache covers 57 Apple topics; use the sidebar or the live documentation search for anything else.</p>
        """)
    }

    private func pageShell(title: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>
        body { font: -apple-system-body; font-family: -apple-system, sans-serif; margin: 32px auto; max-width: 760px; padding: 0 24px; color: CanvasText; background: Canvas; line-height: 1.55; }
        h1 { font-size: 28px; margin: 0 0 4px; } h2 { font-size: 18px; margin: 28px 0 8px; }
        .meta { color: GrayText; font-size: 13px; }
        pre { background: #8882; border-radius: 8px; padding: 14px; overflow-x: auto; }
        code { font-family: ui-monospace, monospace; font-size: 13px; }
        a { color: -webkit-link; } ul { padding-left: 20px; }
        section { margin-bottom: 24px; }
        </style></head><body>
        \(body)
        </body></html>
        """
    }

    /// Plain HTML escaping for rendered DocC text. No templating
    /// engine, no interpolation of unescaped content.
    public nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
