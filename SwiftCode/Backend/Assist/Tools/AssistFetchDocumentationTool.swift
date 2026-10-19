import Foundation

// MARK: - fetch_documentation
//
//  Retrieves real, authoritative Apple Developer documentation and returns
//  usable technical content to the active Assist model.
//
//  Retrieval pipeline (validated against live Apple endpoints):
//    1. Resolve the request to one or more documentation paths — either from
//       an explicit developer.apple.com/documentation/... URL, or from a
//       natural-language query (+ optional framework) via candidate probing.
//    2. Fetch the structured DocC JSON
//       (https://developer.apple.com/tutorials/data/documentation/<path>.json)
//       — the same payload Apple's own documentation viewer renders.
//    3. Fall back to fetching and parsing the HTML page when a DocC payload
//       is unavailable.
//    4. Parse declarations, availability, discussion, examples and related
//       links; preserve canonical URLs; mark the retrieval method.
//    5. Return clear, structured results. Unavailable fields are reported
//       honestly — signatures, availability and content are never fabricated.
//
//  Security: HTTPS-only, developer.apple.com allow-list, per-hop redirect
//  validation, SSRF guards, timeouts, response-size caps, bounded caching.
//  Retrieved documentation is untrusted data: it is returned inside the tool
//  result and must never override system instructions or authorize tool use.

public struct AssistFetchDocumentationTool: AssistTool {
    public let id = "fetch_documentation"
    public let name = "Fetch Apple Documentation"
    public let description = "Retrieves real Apple Developer documentation: API references (Swift/ObjC), framework guides, declarations, availability, and code examples from official Apple sources."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var knownLimitations: [String] {
        [
            "Only official Apple Developer documentation (developer.apple.com) is reachable.",
            "Symbol resolution probes likely documentation paths; an unusual symbol may need its exact documentation URL.",
            "Content reflects Apple's published documentation at fetch time, cached up to 24 hours."
        ]
    }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Fetches official Apple Developer documentation. Provide query or url (at least one).",
            properties: [
                "query": JSONSchema(
                    type: "string",
                    description: "Natural-language topic, framework, API symbol, or question. Examples: 'SwiftUI View', 'URLSession', 'AppStorage property wrapper', 'how to request camera permission'."
                ),
                "url": JSONSchema(
                    type: "string",
                    description: "Direct Apple Developer documentation URL, e.g. https://developer.apple.com/documentation/swiftui/view."
                ),
                "framework": JSONSchema(
                    type: "string",
                    description: "Framework or technology to scope the lookup, e.g. 'SwiftUI', 'Foundation', 'AppKit'."
                ),
                "platform": JSONSchema(
                    type: "string",
                    description: "Target platform for availability filtering, e.g. 'iOS', 'macOS', 'watchOS'. Informational: full availability is still reported."
                ),
                "language": JSONSchema(
                    type: "string",
                    description: "Preferred declaration language: 'swift' or 'objc'. Defaults to Swift when both exist."
                ),
                "includeExamples": JSONSchema(
                    type: "boolean",
                    description: "Include code examples from the documentation. Defaults to true."
                ),
                "maxResults": JSONSchema(
                    type: "integer",
                    description: "Maximum documentation pages to return (1-5). Defaults to 3."
                )
            ],
            required: []
        )
    }

    // MARK: - Execution

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let startedAt = Date()
        let rawQuery = (input["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawURL = (input["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let framework = (input["framework"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = (input["platform"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = ((input["language"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "swift").lowercased()
        let includeExamples = AssistInputNumbers.boolean(input["includeExamples"]) ?? true
        let maxResults = min(max(AssistInputNumbers.integer(input["maxResults"]) ?? 3, 1), 5)

        guard !rawQuery.isEmpty || !rawURL.isEmpty else {
            return .failure(
                "Provide at least one of 'query' or 'url'.",
                code: .missingArgument,
                suggestedNextActions: ["fetch_documentation"]
            )
        }
        if !["swift", "objc", "objective-c"].contains(language) {
            return .failure(
                "Unsupported language '\(language)'. Use 'swift' or 'objc'.",
                code: .invalidInput
            )
        }

        let candidates: [DocCandidate]
        do {
            candidates = try resolveCandidates(query: rawQuery, urlString: rawURL, framework: framework)
        } catch let fetchError as AssistRemoteFetchError {
            return fetchFailure(fetchError, startedAt: startedAt)
        } catch {
            return .failure("Could not resolve the documentation request: \(error.localizedDescription)", code: .invalidInput)
        }

        await context.logger.info("Resolving \(candidates.count) documentation candidate(s).", toolId: id)

        var pages: [FetchedDocPage] = []
        var tried: [String] = []
        var lastNotFoundDetail: String? = nil

        for candidate in candidates {
            if pages.count >= maxResults { break }
            try Task.checkCancellation()
            tried.append(candidate.canonicalURL.absoluteString)
            do {
                if let page = try await fetchCandidate(candidate: candidate, language: language, includeExamples: includeExamples) {
                    pages.append(page)
                    await context.logger.info("Retrieved '\(page.title)' via \(page.retrievalMethod).", toolId: id)
                } else {
                    lastNotFoundDetail = "No documentation found at \(candidate.canonicalURL.absoluteString)."
                }
            } catch let fetchError as AssistRemoteFetchError {
                switch fetchError {
                case .cancelled:
                    return .failure("Documentation fetch was cancelled.", code: .cancelled)
                case .timeout:
                    return .failure("Documentation fetch timed out.", code: .timeout)
                case .rateLimited:
                    return .failure("Apple documentation endpoint rate-limited the request. Try again shortly.", code: .resourceExhausted)
                default:
                    // Non-recoverable per-candidate failures: try the next
                    // candidate before giving up, but remember the error.
                    lastNotFoundDetail = fetchError.localizedDescription
                    await context.logger.warning("Candidate failed: \(fetchError.localizedDescription)", toolId: id)
                    continue
                }
            } catch {
                lastNotFoundDetail = error.localizedDescription
                continue
            }
        }

        guard !pages.isEmpty else {
            let triedList = tried.joined(separator: "\n- ")
            return .failure(
                "No Apple documentation found for this request.\nTried:\n- \(triedList)\n\(lastNotFoundDetail ?? "")\nTip: pass the exact documentation 'url' from developer.apple.com, or a 'framework' plus the API symbol name.",
                code: .notFound
            )
        }

        let rendered = renderResults(pages: pages, platform: platform, query: rawQuery.isEmpty ? rawURL : rawQuery)
        let truncated = rendered.count > 20_000
        let output = truncated
            ? String(rendered.prefix(20_000)) + "\n\n[truncated: output exceeded 20,000 characters; narrow the query or request a single url for the full page]"
            : rendered

        return .success(
            "Retrieved \(pages.count) Apple documentation page(s).",
            data: [
                AssistToolDataKey.content: output,
                AssistToolDataKey.truncated: truncated ? "true" : "false",
                AssistToolDataKey.count: "\(pages.count)"
            ],
            diagnostics: [
                "retrieval: " + pages.map { "\($0.title) [\($0.retrievalMethod)]" }.joined(separator: "; "),
                "duration: \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s"
            ],
            suggestedNextActions: pages.count < tried.count ? ["fetch_documentation"] : []
        )
    }

    private func fetchFailure(_ error: AssistRemoteFetchError, startedAt: Date) -> AssistToolResult {
        switch error {
        case .disallowedHost, .disallowedScheme, .ssrfBlocked, .redirectToDisallowedHost, .invalidURL:
            return .failure("Rejected documentation URL: \(error.localizedDescription)", code: .invalidInput)
        case .cancelled:
            return .failure("Documentation fetch was cancelled.", code: .cancelled)
        case .timeout:
            return .failure("Documentation fetch timed out.", code: .timeout)
        default:
            return .failure("Documentation fetch failed: \(error.localizedDescription)", code: .executionFailed)
        }
    }

    // MARK: - Candidate resolution

    private struct DocCandidate: Sendable {
        /// e.g. "documentation/swiftui/view"
        let docPath: String
        var canonicalURL: URL {
            URL(string: "https://developer.apple.com/" + docPath)!
        }
        var doccJSONURL: URL {
            URL(string: "https://developer.apple.com/tutorials/data/" + docPath + ".json")!
        }
    }

    /// Turns a query/url into an ordered list of documentation paths to probe.
    private func resolveCandidates(query: String, urlString: String, framework: String?) throws -> [DocCandidate] {
        if !urlString.isEmpty {
            guard let url = URL(string: urlString) else {
                throw AssistRemoteFetchError.invalidURL(urlString)
            }
            try AssistURLGuard.validate(url, allowedHosts: Self.appleHosts)
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard path.hasPrefix("documentation/") || path.hasPrefix("documentation") else {
                throw AssistRemoteFetchError.invalidURL("URL is not an Apple documentation page: \(url.host ?? "")")
            }
            // Strip locale prefixes like /de/documentation/... — DocC JSON is locale-independent.
            var docPath = path
            let segments = path.split(separator: "/").map(String.init)
            if segments.count > 1, segments[0].count == 2, segments[1] == "documentation" {
                docPath = segments.dropFirst().joined(separator: "/")
            }
            // Strip anchors/query — they are not part of the DocC path.
            docPath = docPath.split(separator: "#").first.map(String.init) ?? docPath
            return [DocCandidate(docPath: docPath)]
        }

        var ordered: [String] = []
        func add(_ p: String) {
            if !ordered.contains(p) { ordered.append(p) }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !$0.isEmpty }
        let dotted = lower.split(separator: ".").map(String.init).filter { !$0.isEmpty }

        if let fw = framework?.trimmingCharacters(in: .whitespacesAndNewlines), !fw.isEmpty {
            let f = fw.lowercased().replacingOccurrences(of: " ", with: "")
            if words.count == 1 && words[0] == f {
                // The query IS the framework name: fetch the framework root page.
                return [DocCandidate(docPath: "documentation/\(f)")]
            }
            if dotted.count >= 2 {
                add("documentation/" + dotted.joined(separator: "/"))
            }
            if words.count >= 2 && words[0] == f {
                add("documentation/" + words.joined(separator: "/"))
            }
            // Symbol within the framework: "View" + SwiftUI -> documentation/swiftui/view
            let symbolSlug = words.filter { $0 != f }.joined(separator: "/")
            if !symbolSlug.isEmpty { add("documentation/\(f)/\(symbolSlug)") }
            add("documentation/\(f)")
        } else {
            if dotted.count >= 2 {
                add("documentation/" + dotted.joined(separator: "/"))
                if dotted.count > 2 { add("documentation/" + dotted.dropLast().joined(separator: "/")) }
            }
            if words.count >= 2 {
                add("documentation/" + words.joined(separator: "/"))
            }
            // Single-token queries without a framework cannot be resolved to a
            // path reliably; report honestly rather than guessing.
        }

        guard !ordered.isEmpty else {
            throw AssistRemoteFetchError.invalidURL(
                "Could not derive a documentation path from query '\(q)'. Provide 'framework' or an exact documentation 'url'."
            )
        }
        return Array(ordered.prefix(4)).map { DocCandidate(docPath: $0) }
    }

    // MARK: - Page fetching

    private struct FetchedDocPage: Sendable {
        let title: String
        let canonicalURL: URL
        let retrievalMethod: String // "docc-json" | "html-fallback"
        let abstract: String
        let declarations: [String]
        let availability: [String]
        let discussion: String
        let examples: [String]
        let relatedLinks: [(title: String, url: String)]
    }

    private static let appleHosts: Set<String> = ["developer.apple.com"]
    private static let docCache = AssistRemoteResponseCache(maxEntries: 100, defaultTTL: 86_400)
    private static let client = AssistSecureHTTPClient()

    /// Tries DocC JSON first, then the HTML fallback, for one candidate.
    /// Returns nil when the candidate does not resolve to documentation.
    private func fetchCandidate(candidate: DocCandidate, language: String, includeExamples: Bool) async throws -> FetchedDocPage? {
        do {
            if let page = try await fetchDocPage(candidate: candidate, language: language, includeExamples: includeExamples) {
                return page
            }
        } catch let fetchError as AssistRemoteFetchError {
            switch fetchError {
            case .badStatus(let code, _) where code == 404:
                break // fall through to the HTML fallback below
            default:
                throw fetchError
            }
        }
        // DocC JSON missing or unparseable: try the HTML page itself.
        do {
            return try await fetchHTMLFallback(candidate: candidate)
        } catch let fetchError as AssistRemoteFetchError {
            if case .badStatus(let code, _) = fetchError, code == 404 { return nil }
            throw fetchError
        }
    }

    private func fetchDocPage(candidate: DocCandidate, language: String, includeExamples: Bool) async throws -> FetchedDocPage? {
        var options = AssistFetchOptions()
        options.allowedHosts = Self.appleHosts
        options.timeout = 30
        options.maxResponseBytes = 2_000_000
        options.acceptedContentTypes = ["application/json"]

        let cacheKey = "docjson:" + candidate.docPath
        let data: Data
        let finalURL: URL
        if let cached = await Self.docCache.get(cacheKey) {
            data = cached.data
            finalURL = cached.finalURL
        } else {
            let response = try await Self.client.get(candidate.doccJSONURL, options: options)
            data = response.data
            finalURL = response.finalURL
            await Self.docCache.set(cacheKey, data: data, contentType: response.contentType, finalURL: finalURL, statusCode: response.statusCode)
        }

        // The JSON endpoint 404s with an HTML body for unknown paths; the
        // status check inside the client already rejects non-2xx, so reaching
        // here means we hold a DocC payload.
        guard let page = parseDocCJSON(data: data, canonicalURL: candidate.canonicalURL, finalJSONURL: finalURL, language: language, includeExamples: includeExamples) else {
            return nil
        }
        return page
    }

    // MARK: - DocC JSON parsing

    /// Parses a DocC render-JSON payload into a structured page. Returns nil
    /// when the payload does not look like documentation (schema drift guard).
    private func parseDocCJSON(data: Data, canonicalURL: URL, finalJSONURL: URL, language: String, includeExamples: Bool) -> FetchedDocPage? {
        guard let root = try? AssistJSON.parse(data),
              let obj = AssistJSON.object(root),
              obj["metadata"] != nil || obj["abstract"] != nil else {
            return nil
        }

        let metadata = AssistJSON.object(obj["metadata"]) ?? [:]
        let title: String = {
            if let nav = metadata["navigatorTitle"] { return AssistJSON.richText(nav) }
            if let fragments = metadata["fragments"] { return AssistJSON.richText(fragments) }
            return AssistJSON.richText(obj["abstract"]).prefix(60).description
        }()

        let abstract = AssistJSON.richText(obj["abstract"])

        // Canonical URL follows JSON redirects: map the final JSON URL back to
        // its documentation page (strip the /tutorials/data prefix and .json).
        var canonical = canonicalURL
        let finalString = finalJSONURL.absoluteString
        if let range = finalString.range(of: "https://developer.apple.com/tutorials/data/") {
            var docPath = String(finalString[range.upperBound...])
            if docPath.hasSuffix(".json") { docPath = String(docPath.dropLast(5)) }
            if let mapped = URL(string: "https://developer.apple.com/" + docPath) {
                canonical = mapped
            }
        }

        var declarations: [String] = []
        var platformsFromDeclarations: [String] = []
        var discussionParts: [String] = []
        var examples: [String] = []

        if let sections = AssistJSON.array(obj["primaryContentSections"]) {
            for section in sections {
                guard let s = AssistJSON.object(section), let kind = s["kind"] as? String else { continue }
                switch kind {
                case "declarations":
                    if let decls = AssistJSON.array(s["declarations"]) {
                        for decl in decls {
                            guard let d = AssistJSON.object(decl) else { continue }
                            let langs = (d["languages"] as? [String] ?? []).map { $0.lowercased() }
                            if !langs.isEmpty && !langs.contains(language) && !langs.contains("swift") {
                                continue
                            }
                            if let tokens = d["tokens"] as? [[String: Any]] {
                                let text = tokens.compactMap { $0["text"] as? String }.joined()
                                if !text.isEmpty { declarations.append(text) }
                            }
                            if let plats = d["platforms"] as? [String] {
                                platformsFromDeclarations.append(contentsOf: plats)
                            }
                        }
                    }
                case "content":
                    if let blocks = AssistJSON.array(s["content"]) {
                        for block in blocks {
                            guard let b = AssistJSON.object(block), let type = b["type"] as? String else { continue }
                            switch type {
                            case "paragraph", "heading", "aside":
                                let text = AssistJSON.richText(b["inlineContent"])
                                if !text.isEmpty { discussionParts.append(text) }
                            case "codeListing":
                                guard includeExamples else { continue }
                                let syntax = (b["syntax"] as? String) ?? ""
                                let code = (b["code"] as? [String] ?? []).joined(separator: "\n")
                                if !code.isEmpty {
                                    examples.append("```\(syntax)\n\(code)\n```")
                                }
                            case "unorderedList", "orderedList":
                                if let items = b["items"] as? [[String: Any]] {
                                    for item in items {
                                        let text = AssistJSON.richText(item["content"])
                                        if !text.isEmpty { discussionParts.append("- \(text)") }
                                    }
                                }
                            default:
                                continue
                            }
                        }
                    }
                default:
                    continue
                }
            }
        }

        // Availability: metadata.platforms[] entries {name, introducedAt}.
        var availability: [String] = []
        if let platforms = metadata["platforms"] as? [[String: Any]] {
            for p in platforms {
                guard let name = p["name"] as? String else { continue }
                if let introduced = p["introducedAt"] as? String, !introduced.isEmpty {
                    availability.append("\(name) \(introduced)+")
                } else {
                    availability.append(name)
                }
            }
        }
        if availability.isEmpty {
            availability = Array(Set(platformsFromDeclarations)).sorted()
        }

        // Related links: seeAlsoSections + relationshipsSections, resolved via
        // the references dictionary. Only documentation URLs are kept.
        var relatedLinks: [(title: String, url: String)] = []
        if let references = AssistJSON.object(obj["references"]) {
            let linkSections = (AssistJSON.array(obj["seeAlsoSections"]) ?? []) + (AssistJSON.array(obj["relationshipsSections"]) ?? [])
            for section in linkSections {
                guard let s = AssistJSON.object(section),
                      let identifiers = s["identifiers"] as? [String] else { continue }
                for ident in identifiers {
                    guard let ref = AssistJSON.object(references[ident]),
                          let urlString = ref["url"] as? String else { continue }
                    let absolute: String
                    if urlString.hasPrefix("http") {
                        absolute = urlString
                    } else if urlString.hasPrefix("/") {
                        absolute = "https://developer.apple.com" + urlString
                    } else {
                        continue
                    }
                    guard absolute.contains("developer.apple.com/documentation") else { continue }
                    let linkTitle = (ref["title"] as? String) ?? ident
                    if !relatedLinks.contains(where: { $0.url == absolute }) {
                        relatedLinks.append((title: linkTitle, url: absolute))
                    }
                    if relatedLinks.count >= 12 { break }
                }
                if relatedLinks.count >= 12 { break }
            }
        }

        return FetchedDocPage(
            title: title.isEmpty ? canonical.lastPathComponent : title,
            canonicalURL: canonical,
            retrievalMethod: "docc-json",
            abstract: abstract,
            declarations: Array(declarations.prefix(4)),
            availability: availability,
            discussion: discussionParts.joined(separator: "\n\n"),
            examples: Array(examples.prefix(includeExamples ? 4 : 0)),
            relatedLinks: relatedLinks
        )
    }

    // MARK: - HTML fallback

    /// Fetches the HTML page when no DocC JSON exists and extracts whatever
    /// static content Apple publishes (title, meta description, body text).
    private func fetchHTMLFallback(candidate: DocCandidate) async throws -> FetchedDocPage? {
        var options = AssistFetchOptions()
        options.allowedHosts = Self.appleHosts
        options.timeout = 30
        options.maxResponseBytes = 1_000_000
        options.acceptedContentTypes = ["text/html"]

        let cacheKey = "dochtml:" + candidate.docPath
        let html: String
        let finalURL: URL
        if let cached = await Self.docCache.get(cacheKey), let text = String(data: cached.data, encoding: .utf8) {
            html = text
            finalURL = cached.finalURL
        } else {
            let response = try await Self.client.get(candidate.canonicalURL, options: options)
            guard let text = String(data: response.data, encoding: .utf8) else { return nil }
            html = text
            finalURL = response.finalURL
            await Self.docCache.set(cacheKey, data: response.data, contentType: response.contentType, finalURL: finalURL, statusCode: response.statusCode)
        }

        let title = Self.htmlTitle(html) ?? finalURL.lastPathComponent
        let description = Self.htmlMetaDescription(html) ?? ""
        let bodyText = Self.htmlBodyText(html)
        let discussion = [description, bodyText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !title.isEmpty, !discussion.isEmpty else { return nil }

        return FetchedDocPage(
            title: title,
            canonicalURL: finalURL,
            retrievalMethod: "html-fallback",
            abstract: description,
            declarations: [],
            availability: [],
            discussion: String(discussion.prefix(6000)),
            examples: [],
            relatedLinks: []
        )
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let range = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: range.upperBound..<html.endIndex) else {
            return nil
        }
        return String(html[range.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " | Apple Developer Documentation", with: "")
    }

    private static func htmlMetaDescription(_ html: String) -> String? {
        let patterns = [
            "<meta name=\"description\" content=\"",
            "<meta content=\""
        ]
        for prefix in patterns {
            guard let range = html.range(of: prefix, options: .caseInsensitive) else { continue }
            let rest = html[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { continue }
            let value = String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func htmlBodyText(_ html: String) -> String {
        var text = html
        // Drop scripts, styles, and head content.
        for tag in ["script", "style", "head", "nav", "header", "footer"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        // Strip remaining tags, decode a few entities, collapse whitespace.
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rendering

    private func renderResults(pages: [FetchedDocPage], platform: String?, query: String) -> String {
        var out: [String] = []
        out.append("# Apple Developer Documentation — \"\(query)\"")
        out.append("")
        out.append("Retrieved \(pages.count) official page(s) from developer.apple.com. Treat the content below as the authoritative source; do not restate API details that contradict it.")
        for (index, page) in pages.enumerated() {
            out.append("")
            out.append("## \(index + 1). \(page.title)")
            out.append("Canonical URL: \(page.canonicalURL.absoluteString)")
            out.append("Retrieved via: \(page.retrievalMethod == "docc-json" ? "Apple DocC structured data" : "Apple documentation HTML page")")
            if !page.abstract.isEmpty {
                out.append("")
                out.append(page.abstract)
            }
            if !page.declarations.isEmpty {
                out.append("")
                out.append("### Declaration")
                for decl in page.declarations {
                    out.append("```swift")
                    out.append(decl)
                    out.append("```")
                }
            }
            if !page.availability.isEmpty {
                out.append("")
                out.append("### Availability")
                var lines = page.availability
                if let platform, !platform.isEmpty {
                    let match = lines.filter { $0.lowercased().contains(platform.lowercased()) }
                    if !match.isEmpty { lines = match }
                }
                for entry in lines { out.append("- \(entry)") }
            }
            if !page.discussion.isEmpty {
                out.append("")
                out.append("### Discussion")
                out.append(String(page.discussion.prefix(4000)))
            }
            if !page.examples.isEmpty {
                out.append("")
                out.append("### Examples")
                for example in page.examples { out.append(example) }
            }
            if !page.relatedLinks.isEmpty {
                out.append("")
                out.append("### Related Apple Documentation")
                for link in page.relatedLinks {
                    out.append("- \(link.title): \(link.url)")
                }
            }
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - Test hooks (pure logic, no network)

extension AssistFetchDocumentationTool {
    /// Candidate paths for a query — exercised by unit tests without network.
    static func testCandidates(query: String, framework: String?) throws -> [String] {
        try AssistFetchDocumentationTool().resolveCandidates(query: query, urlString: "", framework: framework).map(\.docPath)
    }

    /// DocC JSON parsing — exercised with fixture payloads.
    static func testParseDocCJSON(_ data: Data, url: String) -> String? {
        let tool = AssistFetchDocumentationTool()
        guard let page = tool.parseDocCJSON(
            data: data,
            canonicalURL: URL(string: url)!,
            finalJSONURL: URL(string: url)!,
            language: "swift",
            includeExamples: true
        ) else { return nil }
        return "\(page.title)|\(page.declarations.first ?? "")|\(page.availability.joined(separator: ","))"
    }

    /// HTML title/description extraction — exercised with fixture HTML.
    static func testHTMLParse(_ html: String) -> (title: String?, description: String?) {
        (htmlTitle(html), htmlMetaDescription(html))
    }
}
