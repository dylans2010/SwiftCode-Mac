import Foundation
import YcodeIDECore
import Testing
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct DocumentationCacheTests {

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

    func stubFor(_ routes: [String: (status: Int, body: String)]) -> @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        { request in
            let key = (request.url?.host ?? "") + (request.url?.path ?? "")
            if let route = routes[key] {
                return (route.status, ["Content-Type": "application/json"], Data(route.body.utf8))
            }
            return (404, [:], Data("not found".utf8))
        }
    }

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

    let notDoccJSON = "{\"hello\": \"world\"}"

    func makeTempCache() -> (DocumentationCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentationCacheTests-\(UUID().uuidString)", isDirectory: true)
        return (DocumentationCache(directory: dir), dir)
    }

    func vstackTopic() -> DocCatalogueTopic {
        DocumentationCatalogue.topics.first { $0.name == "VStack" }!
    }

    @Test("The catalogue holds the 57 sqlite-verified topics across 12 frameworks")
    func catalogueHas57Topics() {
        #expect(DocumentationCatalogue.topics.count == 57)
        #expect(DocumentationCatalogue.frameworks.count == 12)
        #expect(Set(DocumentationCatalogue.topics.map(\.name)).count == 57, "topic names must be unique")
        #expect(Set(DocumentationCatalogue.topics.map(\.framework)).count == 12)
        let byName = Dictionary(uniqueKeysWithValues: DocumentationCatalogue.topics.map { ($0.name, $0) })
        #expect(byName["VStack"]?.kind == "struct")
        #expect(byName["VStack"]?.framework == "SwiftUI")
        #expect(byName["VStack"]?.docPath == "documentation/swiftui/vstack")
        #expect(byName["SwiftUI"]?.kind == "article")
        #expect(byName["SwiftUI"]?.docPath == "documentation/swiftui")
        #expect(byName["URLSession"]?.framework == "Foundation")
        #expect(byName["Model"]?.framework == "SwiftData")
        #expect(byName["MTLDevice"]?.framework == "Metal")
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
        let defaulted = DocumentationCache.parsePlatforms(["iOS"], framework: "SwiftUI")
        #expect(defaulted["iOS"] == "13.0")
        let empty = DocumentationCache.parsePlatforms([], framework: "SwiftUI")
        #expect(empty == DocumentationCatalogue.platformDefaults["SwiftUI"])
    }

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

        let pageURL = await cache.pageURL(for: "VStack")
        #expect(pageURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        let index = await cache.loadIndex()
        #expect(index?.topics.first { $0.name == "VStack" }?.status == .cached)

        let symbols = await cache.loadSymbols()
        #expect(symbols.count == 1)
        #expect(symbols.first?.name == "VStack")
        #expect(symbols.first?.kind == "struct")
        let status = await cache.cacheStatus()
        #expect(status.cached == 1)
    }

    @Test("A topic that resolves nowhere fails honestly and caches nothing")
    func fetchTopic404FailsHonestly() async {
        installSearchStub(stubFor([:]))
        defer { resetSearchStub() }
        let (cache, dir) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = await cache.fetchTopic(vstackTopic())
        #expect(!result.cached)
        #expect(result.failure?.contains("VStack") == true)
        #expect(await cache.loadSymbols().isEmpty)
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
