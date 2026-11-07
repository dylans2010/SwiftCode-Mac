import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SearchWebTestTransport {
    nonisolated(unsafe) static var session: URLSession?
}

enum SearchHTTP {
    static let userAgent = "SwiftCode-MCP/1.0"

    static func fetch(_ request: URLRequest, maxBytes: Int, allowedHosts: Set<String>) async throws -> EnginesFetchedResponse {
        try await EnginesHTTP.fetch(request, maxBytes: maxBytes, allowedHosts: allowedHosts,
                                    session: SearchWebTestTransport.session)
    }

    static func get(_ url: URL, accept: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        return request
    }
}

enum SearchText {
    static func terms(of query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func decodeEntities(_ text: String) -> String {
        var out = text
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                               "&apos;": "'", "&nbsp;": " ", "&hellip;": "…", "&ldquo;": "“",
                               "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’",
                               "&ndash;": "–", "&mdash;": "—"] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
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

struct SearchWebResult: Sendable {
    var text: String
    var url: String
}

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

struct SearchDocsHit: Sendable {
    var title: String
    var url: String
    var abstract: String
    var availability: String
    var kind: String
    var score: Int
}

enum SearchDocs {
    static let maxBytes = 2_000_000

    static let symbolKinds: Set<String> = ["symbol"]

    static func doccKind(data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["kind"] as? String
    }

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
        }
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

struct SearchPackageHit: Sendable {
    var name: String
    var identifier: String
    var summary: String
    var stars: Int?
    var activity: String
    var url: String
}

enum SearchPackages {
    static let spiHost = "swiftpackageindex.com"
    static let spiAllowedHosts: Set<String> = [spiHost]
    static let gitHubHost = "api.github.com"
    static let gitHubAllowedHosts: Set<String> = [gitHubHost]
    static let maxBytes = 1_000_000

    static func spiSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = spiHost
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        return components.url
    }

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

    static func searchSPI(query: String) async throws -> [SearchPackageHit]? {
        guard let url = spiSearchURL(query: query) else { return nil }
        let fetched = try await SearchHTTP.fetch(SearchHTTP.get(url, accept: "text/html"),
                                                 maxBytes: maxBytes, allowedHosts: spiAllowedHosts)
        guard (200...299).contains(fetched.status) else { return nil }
        guard let html = String(data: fetched.data, encoding: .utf8) else { return [] }
        return parseSPIHTML(html)
    }

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

    static func search(query: String, limit: Int) async throws -> (hits: [SearchPackageHit], source: String) {
        var spiNote = "returned no usable results"
        do {
            if let spiHits = try await searchSPI(query: query), !spiHits.isEmpty {
                return (Array(spiHits.prefix(limit)), "swift-package-index")
            }
        } catch {
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
