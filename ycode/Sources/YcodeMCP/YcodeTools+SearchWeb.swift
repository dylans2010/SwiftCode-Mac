import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The gap-closure implementations of the four Agentic search tools
/// (family 3: SEARCH TOOLS).
///
/// Behaviour source: Legacy `SwiftCode/Tools/Agentic/WebSearch.swift`,
/// `DocumentationSearch.swift`, `APIReferenceSearch.swift`,
/// `PackageSearch.swift` (Dylan's own code, ported under MIT).
/// Legacy's IDs, descriptions, and required parameters are kept
/// verbatim; each tool gains optional parameters only
/// (`framework`/`limit`), the Wave 10 `repository` precedent.
/// The network clients and parsers live in
/// `YcodeTools+SearchWebSupport.swift`; the wiring that points the
/// four registrations in `YcodeTools+AgenticNetwork.swift` at these
/// handlers is coordinator-owned (this file must not edit it).
///
/// All four tools are read-only network reads (`openWorld`), need
/// no workspace, and never write. No result is ever invented:
/// `web_search` fails honestly when the DuckDuckGo Instant Answer
/// API has nothing for the query, the documentation tools fail
/// honestly when no DocC page resolves, and `package_search`
/// returns an empty result (count 0) only when both backends
/// answered and found no match.
extension YcodeMCPHost {
    // MARK: - `web_search`

    func searchWeb(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let query = call.string("query") else {
            throw MCPToolError("Missing query")
        }
        let limit = min(max(call.int("limit") ?? 8, 1), 20)
        let answer: SearchWebAnswer
        do {
            answer = try await SearchWebDDG.search(query: query)
        } catch let error as EnginesHTTPError {
            throw MCPToolError(searchWebFailure(error))
        }
        let results = Array(answer.results.prefix(limit))
        guard !answer.abstract.isEmpty || !answer.answer.isEmpty || !results.isEmpty else {
            // The Instant Answer API genuinely has nothing for this
            // query. That is not "no web results exist" — the API
            // only answers topics with a summary — so fail honestly
            // and name what would answer it instead of returning an
            // empty success that reads as a searched-and-found-
            // nothing.
            throw MCPToolError(
                "DuckDuckGo's keyless Instant Answer API has no summary or related results for '\(query)'. " +
                "It answers topics with a summary; it is not a full ranked web search, and DuckDuckGo's html/lite " +
                "result pages are bot-gated (they answer with a human challenge) so they cannot be used. " +
                "A full web search needs a keyed provider (Brave Search API, Bing Web Search API, or Google Custom Search) — " +
                "no key has been supplied. No results were invented.")
        }
        var lines = ["# Web search — \"\(query)\" (DuckDuckGo Instant Answer)"]
        if !answer.abstract.isEmpty {
            lines.append("")
            lines.append(answer.abstract)
            if !answer.abstractURL.isEmpty {
                lines.append("Source: \(answer.abstractSource.isEmpty ? answer.abstractURL : answer.abstractSource) — \(answer.abstractURL)")
            }
        }
        if !answer.answer.isEmpty {
            lines.append("")
            lines.append("Answer: \(answer.answer)")
        }
        if !results.isEmpty {
            lines.append("")
            lines.append("## Results (\(results.count))")
            for result in results {
                lines.append("- \(result.text) — \(result.url)")
            }
        }
        let formatted = results.map { "\($0.text) — \($0.url)" }.joined(separator: "\n")
        return .structured(["abstract": .string(answer.abstract),
                            "abstractURL": .string(answer.abstractURL),
                            "answer": .string(answer.answer),
                            "results": .string(formatted),
                            "resultCount": .int(results.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func searchWebFailure(_ error: EnginesHTTPError) -> String {
        switch error {
        case .invalidURL(let message):
            return message
        case .timeout:
            return "DuckDuckGo Instant Answer API timed out."
        case .rateLimited:
            return "DuckDuckGo Instant Answer API rate-limited the request. Try again shortly."
        case .badStatus(let code):
            return "DuckDuckGo Instant Answer API failed: HTTP \(code)."
        case .tooLarge(let max):
            return "DuckDuckGo Instant Answer API failed: response exceeded the \(max)-byte cap."
        case .invalidResponse:
            return "DuckDuckGo Instant Answer API failed: invalid HTTP response."
        case .fetchFailed(let message):
            return "DuckDuckGo Instant Answer API failed: \(message)"
        }
    }

    // MARK: - `documentation_search` / `api_reference_search`

    func searchDocumentation(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await searchDocs(call, symbolOnly: false)
    }

    func searchAPIReference(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await searchDocs(call, symbolOnly: true)
    }

    func searchDocs(_ call: MCPToolCall, symbolOnly: Bool) async throws -> MCPToolResult {
        guard let query = call.string("query") else {
            throw MCPToolError("Missing query")
        }
        let framework = call.string("framework")
        let limit = min(max(call.int("limit") ?? 5, 1), 10)
        let hits: [SearchDocsHit]
        do {
            hits = try await SearchDocs.search(query: query, framework: framework, symbolOnly: symbolOnly)
        } catch let error as EnginesHTTPError {
            switch error {
            case .invalidURL(let message):
                // The resolver's own message already names what it
                // needs (a framework or an exact URL).
                throw MCPToolError(message)
            case .rateLimited:
                throw MCPToolError("Apple documentation endpoint rate-limited the request. Try again shortly.")
            default:
                throw MCPToolError(fetchDocumentationFailure(error))
            }
        }
        if hits.isEmpty {
            if symbolOnly {
                throw MCPToolError(
                    "No API reference pages found for '\(query)'. The documentation pages that matched are not API symbols " +
                    "(articles, guides, or overviews). Try documentation_search for articles and guides, or pass a 'framework' " +
                    "plus the API symbol name.")
            }
            throw MCPToolError(
                "No Apple documentation found for '\(query)'.\nTip: pass a 'framework' plus the API symbol name " +
                "(e.g. query 'View', framework 'SwiftUI'), or use fetch_documentation with an exact developer.apple.com URL.")
        }
        let shown = Array(hits.prefix(limit))
        var lines = ["# Apple Developer Documentation search — \"\(query)\""]
        lines.append("Retrieved \(shown.count) page(s) from developer.apple.com (DocC JSON).")
        for (index, hit) in shown.enumerated() {
            lines.append("")
            lines.append("## \(index + 1). \(hit.title)")
            lines.append("URL: \(hit.url)")
            lines.append("Kind: \(hit.kind.isEmpty ? "page" : hit.kind)")
            if !hit.availability.isEmpty { lines.append("Availability: \(hit.availability)") }
            if !hit.abstract.isEmpty {
                lines.append("")
                lines.append(hit.abstract)
            }
        }
        let formatted = shown.map { "\($0.title) — \($0.url)" }.joined(separator: "\n")
        return .structured(["results": .string(formatted), "count": .int(shown.count)],
                           summary: lines.joined(separator: "\n"))
    }

    // MARK: - `package_search`

    func searchPackage(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let query = call.string("query") else {
            throw MCPToolError("Missing query")
        }
        let limit = min(max(call.int("limit") ?? 10, 1), 25)
        let found: (hits: [SearchPackageHit], source: String)
        do {
            found = try await SearchPackages.search(query: query, limit: limit)
        } catch let error as EnginesHTTPError {
            throw MCPToolError(searchPackageFailure(error))
        }
        let hits = found.hits
        let sourceNote = found.source == "swift-package-index"
            ? "via the Swift Package Index"
            : "via the GitHub public repository search (matches are repositories, not index-verified packages)"
        var lines = ["# Package search — \"\(query)\" (\(sourceNote))"]
        if hits.isEmpty {
            lines.append("No packages found for '\(query)'.")
            return .structured(["results": .string(""), "count": .int(0), "source": .string(found.source)],
                               summary: lines.joined(separator: "\n"))
        }
        for (index, hit) in hits.enumerated() {
            lines.append("")
            lines.append("## \(index + 1). \(hit.name) (\(hit.identifier))")
            lines.append("URL: \(hit.url)")
            var meta: [String] = []
            if let stars = hit.stars { meta.append("\(stars) stars") }
            if !hit.activity.isEmpty { meta.append(hit.activity) }
            if !meta.isEmpty { lines.append(meta.joined(separator: " · ")) }
            if !hit.summary.isEmpty {
                lines.append("")
                lines.append(hit.summary)
            }
        }
        let formatted = hits.map { hit in
            var line = "\(hit.name) (\(hit.identifier)) — \(hit.url)"
            if let stars = hit.stars { line += " — \(stars) stars" }
            if !hit.summary.isEmpty { line += " — \(hit.summary)" }
            return line
        }.joined(separator: "\n")
        return .structured(["results": .string(formatted), "count": .int(hits.count), "source": .string(found.source)],
                           summary: lines.joined(separator: "\n"))
    }

    func searchPackageFailure(_ error: EnginesHTTPError) -> String {
        switch error {
        case .invalidURL(let message):
            return message
        case .timeout:
            return "Package search timed out."
        case .rateLimited:
            return "Package search rate-limited the request: GitHub's unauthenticated search allows 10 requests/minute. Try again shortly."
        case .badStatus(let code):
            return "Package search failed: HTTP \(code)."
        case .tooLarge(let max):
            return "Package search failed: response exceeded the \(max)-byte cap."
        case .invalidResponse:
            return "Package search failed: invalid HTTP response."
        case .fetchFailed(let message):
            return "Package search failed: \(message)"
        }
    }
}
