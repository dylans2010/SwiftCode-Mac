import Foundation
import Testing
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SearchToolsGapTests {

    static func firstText(_ result: MCPToolResult) -> String {
        result.content.first?["text"]?.string ?? ""
    }

    static func installSearchStub(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) {
        StubSearchProtocol.requests = []
        StubSearchProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSearchProtocol.self]
        SearchWebTestTransport.session = URLSession(configuration: config)
    }

    static func resetSearchStub() {
        StubSearchProtocol.handler = nil
        StubSearchProtocol.requests = []
        SearchWebTestTransport.session = nil
    }

    static func expectToolError(_ what: String, _ check: (String) -> Bool,
                                _ body: @escaping @MainActor () async throws -> MCPToolResult) async {
        do {
            _ = try await body()
            #expect(Bool(false), "expected MCPToolError (\(what)) but the call succeeded")
        } catch let error as MCPToolError {
            #expect(check(error.message), "error message did not match (\(what)): \(error.message)")
        } catch {
            #expect(Bool(false), "expected MCPToolError (\(what)) but got \(error)")
        }
    }

    static func stubFor(_ routes: [String: (status: Int, body: String)]) -> @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        { request in
            let key = (request.url?.host ?? "") + (request.url?.path ?? "")
            if let route = routes[key] {
                return (route.status, ["Content-Type": "application/json"], Data(route.body.utf8))
            }
            return (404, [:], Data("not found".utf8))
        }
    }

    static let ddgFixture = """
    {
      "Abstract": "Swift is a programming language.",
      "AbstractText": "Swift is a high-level general-purpose programming language created for Apple platforms.",
      "AbstractURL": "https://en.wikipedia.org/wiki/Swift_(programming_language)",
      "AbstractSource": "Wikipedia",
      "Answer": "",
      "AnswerType": "",
      "Results": [
        {"FirstURL": "https://www.swift.org/", "Text": "Swift.org - The Swift Programming Language"}
      ],
      "RelatedTopics": [
        {"FirstURL": "https://en.wikipedia.org/wiki/Objective-C", "Text": "Objective-C - A general-purpose programming language."},
        {"Name": "Languages", "Topics": [
          {"FirstURL": "https://en.wikipedia.org/wiki/Kotlin_(programming_language)", "Text": "Kotlin - A cross-platform programming language."},
          {"FirstURL": "https://www.swift.org/", "Text": "Swift.org - duplicate URL, dropped"}
        ]}
      ]
    }
    """

    static let ddgEmptyFixture = """
    {"Abstract": "", "AbstractText": "", "AbstractURL": "", "AbstractSource": "",
     "Answer": "", "AnswerType": "", "Results": [], "RelatedTopics": []}
    """

    static func doccFixture(kind: String, title: String, abstract: String) -> String {
        """
        {
          "kind": "\(kind)",
          "identifier": {"interfaceLanguage": "swift", "url": "doc://com.apple.SwiftUI/documentation/SwiftUI/View"},
          "metadata": {
            "navigatorTitle": "\(title)",
            "title": "\(title)",
            "platforms": [{"name": "iOS", "introducedAt": "13.0"}]
          },
          "abstract": [{"type": "text", "text": "\(abstract)"}],
          "primaryContentSections": [],
          "references": {}
        }
        """
    }

    static let doccRootFixture = """
    {
      "kind": "technology",
      "identifier": {"interfaceLanguage": "swift", "url": "doc://com.apple.SwiftUI/documentation/SwiftUI"},
      "metadata": {"navigatorTitle": "SwiftUI", "title": "SwiftUI"},
      "abstract": [{"type": "text", "text": "Declare the user interface and behavior for your app."}],
      "references": {
        "doc://com.apple.SwiftUI/documentation/SwiftUI/View": {
          "title": "View", "url": "/documentation/swiftui/view", "kind": "symbol"
        },
        "doc://com.apple.SwiftUI/documentation/SwiftUI/Button": {
          "title": "Button", "url": "/documentation/swiftui/button", "kind": "symbol"
        },
        "doc://com.apple.SwiftUI/documentation/SwiftUI/View-Fundamentals": {
          "title": "View Fundamentals", "url": "/documentation/swiftui/view-fundamentals", "kind": "article"
        }
      }
    }
    """

    static let spiFixture = """
    <section class="search-results"><p>Results for &ldquo;<strong>argument parser</strong>&rdquo;&hellip;</p>
    <div class="two-column mobile-reversed"><section class="package-results"><h4>Matching packages</h4>
    <ul id="package-list"><li><a href="/apple/swift-argument-parser"><h4>swift-argument-parser</h4><p>Straightforward, type-safe argument parsing for Swift</p><ul class="metadata"><li class="identifier"><small>apple/swift-argument-parser</small></li><li class="activity"><small>Active 12 days ago</small></li><li class="stars"><small>3,802 stars</small></li><li class="has-documentation"><small>Has documentation</small></li></ul></a></li><li><a href="/example/args-and-more"><h4>args-and-more</h4><p>Parsing &amp; more, for CLIs</p><ul class="metadata"><li class="identifier"><small>example/args-and-more</small></li><li class="activity"><small>Active 3 months ago</small></li><li class="stars"><small>42 stars</small></li></ul></a></li></ul>
    </section></div></section>
    """

    static let gitHubSearchFixture = """
    {"total_count": 2, "incomplete_results": false, "items": [
      {"id": 241928033, "name": "swift-argument-parser", "full_name": "apple/swift-argument-parser",
       "description": "Straightforward, type-safe argument parsing for Swift",
       "stargazers_count": 3802, "html_url": "https://github.com/apple/swift-argument-parser"},
      {"id": 999, "name": "swift-arg-parser", "full_name": "stackotter/swift-arg-parser",
       "description": "Straightforward, type-safe argument parsing for Swift. Renamed to avoid dependency conflicts.",
       "stargazers_count": 1, "html_url": "https://github.com/stackotter/swift-arg-parser"}
    ]}
    """

    static let gitHubEmptyFixture = """
    {"total_count": 0, "incomplete_results": false, "items": []}
    """

    @Test func ddgParsesAbstractTopicsAndNestedGroups() {
        let answer = SearchWebDDG.parse(data: Data(Self.ddgFixture.utf8))
        #expect(answer != nil)
        guard let answer else { return }
        #expect(answer.abstract.hasPrefix("Swift is a high-level"))
        #expect(answer.abstractURL == "https://en.wikipedia.org/wiki/Swift_(programming_language)")
        #expect(answer.abstractSource == "Wikipedia")
        #expect(answer.results.count == 3)
        #expect(answer.results[0].url == "https://www.swift.org/")
        #expect(answer.results.contains { $0.url.contains("Objective-C") })
        #expect(answer.results.contains { $0.url.contains("Kotlin") })
        #expect(answer.results.filter { $0.url == "https://www.swift.org/" }.count == 1)
    }

    @Test func ddgParseRejectsGarbage() {
        #expect(SearchWebDDG.parse(data: Data("not json".utf8)) == nil)
        #expect(SearchWebDDG.parse(data: Data("[]".utf8)) == nil)
    }

    @Test func ddgSearchURLIsKeylessInstantAnswer() {
        let url = SearchWebDDG.searchURL(query: "swift language")
        #expect(url?.host == "api.duckduckgo.com")
        #expect(url?.absoluteString.contains("format=json") == true)
        #expect(url?.absoluteString.contains("swift%20language") == true)
    }

    @Test func webSearchReturnsInstantAnswer() async throws {
        Self.installSearchStub(Self.stubFor(["api.duckduckgo.com/": (200, Self.ddgFixture)]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchWeb(MCPToolCall(name: "web_search",
                                                          arguments: ["query": .string("swift programming language")]))
        #expect(!result.isError)
        #expect(result.structured?["resultCount"]?.int == 3)
        #expect(result.structured?["abstract"]?.string?.hasPrefix("Swift is a high-level") == true)
        let text = Self.firstText(result)
        #expect(text.contains("Swift is a high-level"))
        #expect(text.contains("https://www.swift.org/"))
        #expect(StubSearchProtocol.requests.count == 1)
        #expect(StubSearchProtocol.requests.first?.url?.host == "api.duckduckgo.com")
    }

    @Test func webSearchRespectsLimit() async throws {
        Self.installSearchStub(Self.stubFor(["api.duckduckgo.com/": (200, Self.ddgFixture)]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchWeb(MCPToolCall(name: "web_search",
                                                          arguments: ["query": .string("swift"), "limit": .int(1)]))
        #expect(result.structured?["resultCount"]?.int == 1)
    }

    @Test func webSearchFailsHonestlyWhenInstantAnswerIsEmpty() async throws {
        Self.installSearchStub(Self.stubFor(["api.duckduckgo.com/": (200, Self.ddgEmptyFixture)]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("empty instant answer",
                                   { $0.contains("keyed provider") && $0.contains("No results were invented") }) {
            try await host.searchWeb(MCPToolCall(name: "web_search",
                                                 arguments: ["query": .string("some query with no summary")]))
        }
    }

    @Test func webSearchSurfacesHTTPFailure() async throws {
        Self.installSearchStub(Self.stubFor(["api.duckduckgo.com/": (500, "{}")]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("HTTP 500", { $0.contains("HTTP 500") }) {
            try await host.searchWeb(MCPToolCall(name: "web_search",
                                                 arguments: ["query": .string("swift")]))
        }
    }

    @Test func webSearchMissingQuery() async throws {
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("missing query", { $0 == "Missing query" }) {
            try await host.searchWeb(MCPToolCall(name: "web_search", arguments: [:]))
        }
    }

    @Test func docsSearchResolvesDottedQuery() async throws {
        let view = Self.doccFixture(kind: "symbol", title: "View",
                                    abstract: "A view that displays content.")
        Self.installSearchStub(Self.stubFor([
            "developer.apple.com/tutorials/data/documentation/swiftui/view.json": (200, view),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchDocumentation(MCPToolCall(name: "documentation_search",
                                                                    arguments: ["query": .string("SwiftUI.View")]))
        #expect(!result.isError)
        #expect(result.structured?["count"]?.int == 1)
        let text = Self.firstText(result)
        #expect(text.contains("## 1. View"))
        #expect(text.contains("https://developer.apple.com/documentation/swiftui/view"))
        #expect(text.contains("A view that displays content."))
        #expect(text.contains("iOS 13.0+"))
    }

    @Test func apiReferenceSearchDropsNonSymbolPages() async throws {
        let article = Self.doccFixture(kind: "article", title: "View Fundamentals",
                                       abstract: "Learn how views work.")
        Self.installSearchStub(Self.stubFor([
            "developer.apple.com/tutorials/data/documentation/swiftui/view.json": (200, article),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let docs = try await host.searchDocumentation(MCPToolCall(name: "documentation_search",
                                                                  arguments: ["query": .string("SwiftUI.View")]))
        #expect(docs.structured?["count"]?.int == 1)
        await Self.expectToolError("article is not an API symbol", { $0.contains("not API symbols") }) {
            try await host.searchAPIReference(MCPToolCall(name: "api_reference_search",
                                                          arguments: ["query": .string("SwiftUI.View")]))
        }
    }

    @Test func docsSearchFrameworkRootAddsTitleMatches() async throws {
        let view = Self.doccFixture(kind: "symbol", title: "View",
                                    abstract: "A view that displays content.")
        let fundamentals = Self.doccFixture(kind: "article", title: "View Fundamentals",
                                            abstract: "Learn how views work.")
        Self.installSearchStub(Self.stubFor([
            "developer.apple.com/tutorials/data/documentation/swiftui.json": (200, Self.doccRootFixture),
            "developer.apple.com/tutorials/data/documentation/swiftui/view.json": (200, view),
            "developer.apple.com/tutorials/data/documentation/swiftui/view-fundamentals.json": (200, fundamentals),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchDocumentation(MCPToolCall(
            name: "documentation_search",
            arguments: ["query": .string("View"), "framework": .string("SwiftUI")]))
        #expect(!result.isError)
        #expect(result.structured?["count"]?.int == 2)
        let text = Self.firstText(result)
        #expect(text.contains("## 1. View"))
        #expect(text.contains("View Fundamentals"))
        #expect(!text.contains("Button"))
    }

    @Test func docsSearchSingleTokenWithoutFrameworkFailsHonestly() async throws {
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("single-token query", { $0.contains("Provide 'framework'") }) {
            try await host.searchDocumentation(MCPToolCall(name: "documentation_search",
                                                           arguments: ["query": .string("View")]))
        }
    }

    @Test func docsSearchNoPageFoundFailsHonestly() async throws {
        Self.installSearchStub(Self.stubFor([:]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("no page found", { $0.contains("No Apple documentation found") }) {
            try await host.searchDocumentation(MCPToolCall(name: "documentation_search",
                                                           arguments: ["query": .string("SwiftUI.NoSuchSymbol")]))
        }
    }

    @Test func docsScoreOrdersExactTitleFirst() {
        #expect(SearchDocs.score(title: "View", abstract: "A view.", query: "View", terms: ["view"]) == 4)
        #expect(SearchDocs.score(title: "View Fundamentals", abstract: "About views.", query: "View", terms: ["view"])
                > SearchDocs.score(title: "Button", abstract: "A control.", query: "View", terms: ["view"]))
        #expect(SearchDocs.score(title: "Button", abstract: "A control.", query: "View", terms: ["view"]) == 0)
    }

    @Test func spiParsesPackageList() {
        let hits = SearchPackages.parseSPIHTML(Self.spiFixture)
        #expect(hits.count == 2)
        #expect(hits[0].name == "swift-argument-parser")
        #expect(hits[0].identifier == "apple/swift-argument-parser")
        #expect(hits[0].summary == "Straightforward, type-safe argument parsing for Swift")
        #expect(hits[0].stars == 3802)
        #expect(hits[0].activity == "Active 12 days ago")
        #expect(hits[0].url == "https://swiftpackageindex.com/apple/swift-argument-parser")
        #expect(hits[1].summary == "Parsing & more, for CLIs")
        #expect(hits[1].stars == 42)
    }

    @Test func spiParseReturnsEmptyWithoutList() {
        #expect(SearchPackages.parseSPIHTML("<html><body>No results here.</body></html>").isEmpty)
        #expect(SearchPackages.parseSPIHTML("").isEmpty)
    }

    @Test func gitHubParseExtractsItems() {
        let hits = SearchPackages.parseGitHubJSON(Data(Self.gitHubSearchFixture.utf8))
        #expect(hits?.count == 2)
        #expect(hits?[0].identifier == "apple/swift-argument-parser")
        #expect(hits?[0].stars == 3802)
        #expect(hits?[0].url == "https://github.com/apple/swift-argument-parser")
        #expect(SearchPackages.parseGitHubJSON(Data("{\"nope\": true}".utf8)) == nil)
    }

    @Test func packageSearchPrefersSPI() async throws {
        Self.installSearchStub(Self.stubFor([
            "swiftpackageindex.com/search": (200, Self.spiFixture),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchPackage(MCPToolCall(name: "package_search",
                                                              arguments: ["query": .string("argument parser")]))
        #expect(!result.isError)
        #expect(result.structured?["count"]?.int == 2)
        #expect(result.structured?["source"]?.string == "swift-package-index")
        #expect(Self.firstText(result).contains("swift-argument-parser"))
        #expect(StubSearchProtocol.requests.allSatisfy { $0.url?.host == "swiftpackageindex.com" })
    }

    @Test func packageSearchFallsBackToGitHub() async throws {
        Self.installSearchStub(Self.stubFor([
            "swiftpackageindex.com/search": (500, "error"),
            "api.github.com/search/repositories": (200, Self.gitHubSearchFixture),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchPackage(MCPToolCall(name: "package_search",
                                                              arguments: ["query": .string("argument parser")]))
        #expect(!result.isError)
        #expect(result.structured?["count"]?.int == 2)
        #expect(result.structured?["source"]?.string == "github-search")
        #expect(Self.firstText(result).contains("apple/swift-argument-parser"))
        #expect(Self.firstText(result).contains("not index-verified packages"))
    }

    @Test func packageSearchEmptyBothBackendsIsEmptyNotAnError() async throws {
        Self.installSearchStub(Self.stubFor([
            "swiftpackageindex.com/search": (200, "<html><body>No results here.</body></html>"),
            "api.github.com/search/repositories": (200, Self.gitHubEmptyFixture),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        let result = try await host.searchPackage(MCPToolCall(name: "package_search",
                                                              arguments: ["query": .string("no-such-package-xyz")]))
        #expect(!result.isError)
        #expect(result.structured?["count"]?.int == 0)
        #expect(result.structured?["source"]?.string == "github-search")
        #expect(Self.firstText(result).contains("No packages found"))
    }

    @Test func packageSearchBothBackendsFailHonestly() async throws {
        Self.installSearchStub(Self.stubFor([
            "swiftpackageindex.com/search": (500, "error"),
            "api.github.com/search/repositories": (403, "{\"message\": \"API rate limit exceeded\"}"),
        ]))
        defer { Self.resetSearchStub() }
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("both backends failed",
                                   { $0.contains("Swift Package Index") && $0.contains("rate-limited") }) {
            try await host.searchPackage(MCPToolCall(name: "package_search",
                                                     arguments: ["query": .string("argument parser")]))
        }
    }

    @Test func packageSearchMissingQuery() async throws {
        let host = SwiftCodeMCPHost()
        await Self.expectToolError("missing query", { $0 == "Missing query" }) {
            try await host.searchPackage(MCPToolCall(name: "package_search", arguments: [:]))
        }
    }
}

final class StubSearchProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, headers: [String: String], body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
