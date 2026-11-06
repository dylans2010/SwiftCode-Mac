import Foundation
import SwiftCodeIDECore
import Testing
@testable import SwiftCodeMCP

/// Wave 19, Slice A: tests for the offline documentation cache
/// (`DocumentationCache` + `DocumentationCatalogue` +
/// `DocumentationSymbols`).
///
/// Behaviour source: Legacy `Documentation.sqlite` (57 rows,
/// verified read-only with python3 sqlite3) and
/// `SwiftCode/Resources/DocSymbols.json` (same 57 names), plus the
/// destination's own live DocC fetch path (`EnginesDocs` /
/// `SearchDocs` / `SearchHTTP`).
///
/// The FIXTURES below are canned (that is the point: the tests must
/// not touch the live network); the IMPLEMENTATION under test is
/// not — it parses real DocC render-JSON payloads, resolves
/// candidates the way the live path does, and fails honestly when a
/// topic does not resolve. Every request goes through
/// `StubSearchProtocol` via `SearchWebTestTransport.session` (the
/// `SearchToolsGapTests` shape, reused here — same test target).
/// Each test uses its own temp directory as the cache root, so no
/// test touches Application Support or another test's cache.
///
/// No Swift toolchain exists in this environment, so these tests
/// are static-checked only here; `swift test` stays pending on
/// Dylan's Mac.
@MainActor
@Suite(.serialized) struct DocumentationCacheTests {

    // MARK: - Stub transport (same shape as SearchToolsGapTests)

    func installSearchStub(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) {
        StubSearchProtocol.requests = []
        StubSearchProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSearchProtocol.self]
        SearchWebTestTransport.session = URLSession(configuration: config)
    }

    func resetSearchStub() {
        StubSearchProtocol.handler = nil
        StubSearchProtocol.requests = []
        SearchWebTestTransport.session = nil
    }

    /// A stub answer for one host+path, 404 for anything else.
    func stubFor(_ routes: [String: (status: Int, body: String)]) -> @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        { request in
            let key = (request.url?.host ?? "") + (request.url?.path ?? "")
            if let route = routes[key] {
                return (route.status, ["Content-Type": "application/json"], Data(route.body.utf8))
            }
            return (404, [:], Data("not found".utf8))
        }
    }

    // MARK: - Fixtures (canned DocC render-JSON)

    /// A VStack page in the shape of the live DocC JSON for
    /// `documentation/swiftui/vstack`: a symbol with one
    /// declaration, metadata availability, a discussion paragraph,
    /// one Swift code listing, a "Conforms To" relationship, and a
    /// "See Also" section. The payload is synthetic test data — it
    /// exercises the parser and the conversion, and makes no claim
    /// about the live page's current wording.
    let vstackFixture = """
    {
      "kind": "symbol",
      "identifier": {"interfaceLanguage": "swift", "url": "doc://com.apple.SwiftUI/documentation/SwiftUI/VStack"},
      "metadata": {
        "navigatorTitle": "VStack",
        "title": "VStack",
        "platforms": [{"name": "iOS", "introducedAt": "13.0"}, {"name": "macOS", "introducedAt": "10.15"}]
      },
      "abstract": [{"type": "text", "text": "A view that arranges its subviews in a vertical line."}],
      "primaryContentSections": [
        {"kind": "declarations", "declarations": [
          {"languages": ["swift"],
           "tokens": [{"text": "struct VStack<Content> where Content : View"}],
           "platforms": ["iOS 13.0+", "macOS 10.15+"]}
        ]},
        {"kind": "content", "content": [
          {"type": "paragraph", "inlineContent": [{"type": "text", "text": "Use a VStack to stack views vertically."}]},
          {"type": "codeListing", "syntax": "swift", "code": ["VStack {", "    Text(\\"Hello\\")", "}"]}
        ]}
      ],
      "relationshipsSections": [
        {"title": "Conforms To", "identifiers": ["doc://com.apple.SwiftUI/documentation/SwiftUI/View"]}
      ],
      "seeAlsoSections": [
        {"title": "See Also", "identifiers": ["doc://com.apple.SwiftUI/documentation/SwiftUI/HStack", "doc://com.apple.SwiftUI/documentation/SwiftUI/ZStack"]}
      ],
      "references": {
        "doc://com.apple.SwiftUI/documentation/SwiftUI/View": {"title": "View", "url": "/documentation/swiftui/view"},
        "doc://com.apple.SwiftUI/documentation/SwiftUI/HStack": {"title": "HStack", "url": "/documentation/swiftui/hstack"},
        "doc://com.apple.SwiftUI/documentation/SwiftUI/ZStack": {"title": "ZStack", "url": "/documentation/swiftui/zstack"}
      }
    }
    """

    /// Valid JSON that is not DocC (no `metadata`, no `abstract`).
    let notDoccJSON = "{\"hello\": \"world\"}"

    // MARK: - Helpers

    func makeTempCache() -> (DocumentationCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentationCacheTests-\(UUID().uuidString)", isDirectory: true)
        return (DocumentationCache(directory: dir), dir)
    }

    func vstackTopic() -> DocCatalogueTopic {
        DocumentationCatalogue.topics.first { $0.name == "VStack" }!
    }

    // MARK: - Catalogue

    @Test("The catalogue holds the 57 sqlite-verified topics across 12 frameworks")
    func catalogueHas57Topics() {
        #expect(DocumentationCatalogue.topics.count == 57)
        #expect(DocumentationCatalogue.frameworks.count == 12)
        #expect(Set(DocumentationCatalogue.topics.map(\.name)).count == 57, "topic names must be unique")
        #expect(Set(DocumentationCatalogue.topics.map(\.framework)).count == 12)
        // Spot checks against the sqlite (name, kind, framework).
        let byName = Dictionary(uniqueKeysWithValues: DocumentationCatalogue.topics.map { ($0.name, $0) })
        #expect(byName["VStack"]?.kind == "struct")
        #expect(byName["VStack"]?.framework == "SwiftUI")
        #expect(byName["VStack"]?.docPath == "documentation/swiftui/vstack")
        #expect(byName["SwiftUI"]?.kind == "article")
        #expect(byName["SwiftUI"]?.docPath == "documentation/swiftui")
        #expect(byName["URLSession"]?.framework == "Foundation")
        #expect(byName["Model"]?.framework == "SwiftData")
        #expect(byName["MTLDevice"]?.framework == "Metal")
        // Every topic's docPath is a real DocC path under its framework.
        for topic in DocumentationCatalogue.topics {
            #expect(topic.docPath.hasPrefix("documentation/\(topic.framework.lowercased())"),
                    "docPath \(topic.docPath) must live under its framework")
        }
    }

    @Test("The sidebar sections cover all 57 topics and only those")
    func sectionsCoverCatalogue() {
        let sections = DocumentationCatalogue.defaultSections()
        #expect(sections.count == 5)
        let listed = sections.flatMap(\.collections).flatMap(\.groups).flatMap(\.items).map(\.title)
        #expect(Set(listed) == Set(DocumentationCatalogue.topics.map(\.name)))
        #expect(listed.count == 57)
    }

    // MARK: - Conversion

    @Test("DocC JSON converts to a DocSymbol: kind, platforms, relationships, fenced sample, see-also")
    func symbolConversionFromDocCJSON() {
        let symbol = try #require(DocumentationCache.symbol(from: Data(vstackFixture.utf8), topic: vstackTopic()))
        #expect(symbol.name == "VStack")
        #expect(symbol.kind == "struct")
        #expect(symbol.framework == "SwiftUI")
        #expect(symbol.summary == "A view that arranges its subviews in a vertical line.")
        #expect(symbol.syntax.contains("struct VStack<Content>"))
        #expect(symbol.platforms["iOS"] == "13.0")
        #expect(symbol.platforms["macOS"] == "10.15")
        #expect(symbol.inheritsFrom == nil)
        #expect(symbol.conformsTo == ["View"])
        // The code sample is the listing with its fences stripped;
        // a page with no listing has an empty sample (never a stub).
        #expect(symbol.codeSample == "VStack {\n    Text(\"Hello\")\n}")
        #expect(symbol.seeAlso.contains("HStack"))
        #expect(symbol.seeAlso.contains("ZStack"))
        #expect(symbol.docPath == "/documentation/swiftui/vstack")
    }

    @Test("Non-DocC payloads do not convert (schema drift guard)")
    func symbolConversionRejectsNonDocC() {
        #expect(DocumentationCache.symbol(from: Data(notDoccJSON.utf8), topic: vstackTopic()) == nil)
        #expect(DocumentationCache.symbol(from: Data("not json at all".utf8), topic: vstackTopic()) == nil)
        #expect(DocumentationCache.symbol(from: Data(), topic: vstackTopic()) == nil)
    }

    @Test("Kind inference follows the DocC kind and the first declaration line")
    func kindInference() {
        #expect(DocumentationCache.inferKind(doccKind: "article", declarations: []) == "article")
        #expect(DocumentationCache.inferKind(doccKind: "overview", declarations: []) == "article")
        #expect(DocumentationCache.inferKind(doccKind: "symbol", declarations: ["protocol View"]) == "protocol")
        #expect(DocumentationCache.inferKind(doccKind: "symbol", declarations: ["struct VStack"]) == "struct")
        #expect(DocumentationCache.inferKind(doccKind: "symbol", declarations: ["class UIView"]) == "class")
        #expect(DocumentationCache.inferKind(doccKind: "symbol", declarations: ["func foo()"]) == "func")
        #expect(DocumentationCache.inferKind(doccKind: "symbol", declarations: ["actor Counter"]) == "actor")
        #expect(DocumentationCache.inferKind(doccKind: "symbol", declarations: []) == "class")
        #expect(DocumentationCache.inferKind(doccKind: "", declarations: []) == "class")
    }

    @Test("Platform parsing strips the +, and falls back to the framework defaults")
    func platformParsing() {
        let parsed = DocumentationCache.parsePlatforms(["iOS 13.0+", "macOS 10.15"], framework: "SwiftUI")
        #expect(parsed["iOS"] == "13.0")
        #expect(parsed["macOS"] == "10.15")
        // No version at all → the framework default for that platform.
        let defaulted = DocumentationCache.parsePlatforms(["iOS"], framework: "SwiftUI")
        #expect(defaulted["iOS"] == "13.0")
        // No availability at all → the whole framework default table.
        let empty = DocumentationCache.parsePlatforms([], framework: "SwiftUI")
        #expect(empty == DocumentationCatalogue.platformDefaults["SwiftUI"])
    }

    // MARK: - Fetching and storage (stubbed transport)

    @Test("An empty cache loads nothing and reports 0 of 57")
    func emptyCacheLoadsNothing() async {
        let (cache, dir) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(await cache.loadSymbols().isEmpty)
        let status = await cache.cacheStatus()
        #expect(status.cached == 0)
        #expect(status.failed == 0)
        #expect(status.total == 57)
        #expect(status.lastFetch == nil)
    }

    @Test("Fetching a topic caches its raw JSON and loads back as a symbol")
    func fetchTopicCachesPage() async {
        installSearchStub(stubFor([
            "developer.apple.com/tutorials/data/documentation/swiftui/vstack.json": (200, vstackFixture),
        ]))
        defer { resetSearchStub() }
        let (cache, dir) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = await cache.fetchTopic(vstackTopic())
        #expect(result.cached)
        #expect(result.failure == nil)
        #expect(result.canonicalURL?.path == "/documentation/swiftui/vstack")

        // The raw payload is on disk, and the index records it.
        let pageURL = await cache.pageURL(for: "VStack")
        #expect(pageURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        let index = await cache.loadIndex()
        #expect(index?.topics.first { $0.name == "VStack" }?.status == .cached)

        // And it loads back as the converted symbol.
        let symbols = await cache.loadSymbols()
        #expect(symbols.count == 1)
        #expect(symbols.first?.name == "VStack")
        #expect(symbols.first?.kind == "struct")
        let status = await cache.cacheStatus()
        #expect(status.cached == 1)
    }

    @Test("A topic that resolves nowhere fails honestly and caches nothing")
    func fetchTopic404FailsHonestly() async {
        // Every candidate 404s; the framework-index fallback 404s too.
        installSearchStub(stubFor([:]))
        defer { resetSearchStub() }
        let (cache, dir) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = await cache.fetchTopic(vstackTopic())
        #expect(!result.cached)
        #expect(result.failure?.contains("VStack") == true)
        #expect(await cache.loadSymbols().isEmpty)
        // The failure is recorded in the index, not swallowed.
        let status = await cache.cacheStatus()
        #expect(status.failed == 1)
        let index = await cache.loadIndex()
        #expect(index?.topics.first { $0.name == "VStack" }?.failure?.isEmpty == false)
    }

    @Test("A 429 names the rate limit instead of inventing a page")
    func fetchTopicRateLimited() async {
        installSearchStub(stubFor([
            "developer.apple.com/tutorials/data/documentation/swiftui/vstack.json": (429, ""),
        ]))
        defer { resetSearchStub() }
        let (cache, dir) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = await cache.fetchTopic(vstackTopic())
        #expect(!result.cached)
        #expect(result.failure?.lowercased().contains("rate-limit") == true)
    }

    // MARK: - Rendering

    @Test("The renderer serves home, framework, topic, and 404 pages from the cache")
    func renderedHTML() async {
        installSearchStub(stubFor([
            "developer.apple.com/tutorials/data/documentation/swiftui/vstack.json": (200, vstackFixture),
        ]))
        defer { resetSearchStub() }
        let (cache, dir) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await cache.fetchTopic(vstackTopic())

        let home = await cache.renderedHTML(docPath: "")
        #expect(home.contains("Developer Documentation"))
        #expect(home.contains("SwiftUI"))
        #expect(home.contains("1 of 57"))

        let framework = await cache.renderedHTML(docPath: "documentation/swiftui")
        #expect(framework.contains("SwiftUI"))
        #expect(framework.contains("VStack"))
        #expect(framework.contains("docc://developer.apple.com/documentation/swiftui/vstack"))

        let topic = await cache.renderedHTML(docPath: "documentation/swiftui/vstack")
        #expect(topic.contains("VStack"))
        #expect(topic.contains("A view that arranges its subviews in a vertical line."))
        #expect(topic.contains("struct VStack"))

        let unknown = await cache.renderedHTML(docPath: "documentation/swiftui/nonexistent")
        #expect(unknown.contains("Page not found"))
        #expect(unknown.contains("documentation/swiftui/nonexistent"))

        // A known topic whose fetch failed says so instead of 404ing:
        // it is in the index (failed) but has no cached page file.
        let textTopic = DocumentationCatalogue.topics.first { $0.name == "Text" }!
        let textResult = await cache.fetchTopic(textTopic)
        #expect(!textResult.cached)
        let uncached = await cache.renderedHTML(docPath: "documentation/swiftui/text")
        #expect(uncached.contains("Text"))
        #expect(uncached.contains("not cached offline"))
    }

    @Test("HTML escaping keeps DocC text out of markup")
    func htmlEscaping() {
        #expect(DocumentationCache.escape("<b>&\"quoted\"</b>") == "&lt;b&gt;&amp;&quot;quoted&quot;&lt;/b&gt;")
    }
}
