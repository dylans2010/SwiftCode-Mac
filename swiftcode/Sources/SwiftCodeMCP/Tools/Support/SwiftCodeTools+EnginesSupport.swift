import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore

enum EnginesMutation {
    static func symbolBodyRange(for symbol: String, in content: String) -> Range<String.Index>? {
        guard let symbolRange = content.range(of: symbol) else { return nil }
        guard let braceStart = content[symbolRange.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = braceStart
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return symbolRange.lowerBound..<content.index(after: idx)
                }
            }
            idx = content.index(after: idx)
        }
        return nil
    }
}

enum EnginesPatch {
    static func unifiedDiff(old: String, new: String, file: String) -> String {
        MyersDiff.unifiedDiff(old: old, new: new, file: file)
    }
}

enum EnginesXcodeProject {
    struct Located: Sendable {
        var url: URL
        var isWorkspace: Bool

        var xcodebuildArgs: [String] {
            isWorkspace ? ["-workspace", url.path] : ["-project", url.path]
        }
    }

    static func locate(in workspaceRoot: URL) -> Located? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }
        if let ws = workspaces.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
            return Located(url: ws, isWorkspace: true)
        }
        if let proj = projects.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
            return Located(url: proj, isWorkspace: false)
        }
        return nil
    }
}

enum EnginesHTTPError: Error, Sendable {
    case invalidURL(String)
    case badStatus(Int)
    case timeout
    case rateLimited
    case tooLarge(Int)
    case invalidResponse
    case fetchFailed(String)
}

struct EnginesFetchedResponse: Sendable {
    var data: Data
    var finalURL: URL
    var status: Int
    var contentType: String?
}

final class EnginesRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowedHosts: Set<String>?
    init(allowedHosts: Set<String>?) { self.allowedHosts = allowedHosts }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let hosts = allowedHosts else { completionHandler(request); return }
        if let host = request.url?.host?.lowercased(), hosts.contains(host) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

enum EnginesHTTP {
    static func fetch(_ request: URLRequest, maxBytes: Int, allowedHosts: Set<String>?,
                      session: URLSession? = nil) async throws -> EnginesFetchedResponse {
        if let session {
            return try await fetch(request, maxBytes: maxBytes, using: session)
        }
        let live = URLSession(configuration: .ephemeral,
                              delegate: EnginesRedirectGuard(allowedHosts: allowedHosts), delegateQueue: nil)
        defer { live.finishTasksAndInvalidate() }
        return try await fetch(request, maxBytes: maxBytes, using: live)
    }

    private static func fetch(_ request: URLRequest, maxBytes: Int, using session: URLSession) async throws -> EnginesFetchedResponse {
        let holder = EnginesTaskHolder()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<EnginesFetchedResponse, Error>) in
                    let task = session.dataTask(with: request) { data, response, error in
                        if let error {
                            if let urlError = error as? URLError, urlError.code == .cancelled {
                                return c.resume(throwing: CancellationError())
                            }
                            if let urlError = error as? URLError, urlError.code == .timedOut {
                                return c.resume(throwing: EnginesHTTPError.timeout)
                            }
                            return c.resume(throwing: EnginesHTTPError.fetchFailed(error.localizedDescription))
                        }
                        guard let http = response as? HTTPURLResponse, let data else {
                            return c.resume(throwing: EnginesHTTPError.invalidResponse)
                        }
                        if data.count > maxBytes {
                            return c.resume(throwing: EnginesHTTPError.tooLarge(maxBytes))
                        }
                        c.resume(returning: EnginesFetchedResponse(
                            data: data, finalURL: http.url ?? request.url!,
                            status: http.statusCode,
                            contentType: http.value(forHTTPHeaderField: "Content-Type")))
                    }
                    holder.set(task)
                    task.resume()
                }
            } onCancel: {
                holder.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        }
    }
}

final class EnginesTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func set(_ t: URLSessionTask) {
        lock.lock()
        task = t
        let c = cancelled
        lock.unlock()
        if c { t.cancel() }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }
}

enum EnginesDocs {
    static let appleHosts: Set<String> = ["developer.apple.com"]

    struct Candidate: Sendable {
        let docPath: String
        var canonicalURL: URL {
            URL(string: "https://developer.apple.com/" + docPath)!
        }
        var doccJSONURL: URL {
            URL(string: "https://developer.apple.com/tutorials/data/" + docPath + ".json")!
        }
    }

    struct Page: Sendable {
        var title: String
        var canonicalURL: URL
        var retrievalMethod: String
        var abstract: String
        var declarations: [String]
        var availability: [String]
        var discussion: String
        var examples: [String]
        var relatedLinks: [(title: String, url: String)]
    }

    static func resolveCandidates(query: String, urlString: String, framework: String?) throws -> [Candidate] {
        if !urlString.isEmpty {
            guard let url = URL(string: urlString) else {
                throw EnginesHTTPError.invalidURL(urlString)
            }
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), appleHosts.contains(host) else {
                throw EnginesHTTPError.invalidURL("URL is not an Apple Developer documentation URL: \(urlString)")
            }
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard path.hasPrefix("documentation/") || path == "documentation" else {
                throw EnginesHTTPError.invalidURL("URL is not an Apple documentation page: \(url.host ?? "")")
            }
            var docPath = path
            let segments = path.split(separator: "/").map(String.init)
            if segments.count > 1, segments[0].count == 2, segments[1] == "documentation" {
                docPath = segments.dropFirst().joined(separator: "/")
            }
            docPath = docPath.split(separator: "#").first.map(String.init) ?? docPath
            return [Candidate(docPath: docPath)]
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
                return [Candidate(docPath: "documentation/\(f)")]
            }
            if dotted.count >= 2 {
                add("documentation/" + dotted.joined(separator: "/"))
            }
            if words.count >= 2 && words[0] == f {
                add("documentation/" + words.joined(separator: "/"))
            }
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
        }

        guard !ordered.isEmpty else {
            throw EnginesHTTPError.invalidURL(
                "Could not derive a documentation path from query '\(q)'. Provide 'framework' or an exact documentation 'url'."
            )
        }
        return Array(ordered.prefix(4)).map { Candidate(docPath: $0) }
    }

    static func parseDocCJSON(data: Data, canonicalURL: URL, finalJSONURL: URL,
                              language: String, includeExamples: Bool) -> Page? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let obj = root as? [String: Any],
              obj["metadata"] != nil || obj["abstract"] != nil else {
            return nil
        }

        let metadata = (obj["metadata"] as? [String: Any]) ?? [:]
        let title: String = {
            if let nav = metadata["navigatorTitle"] { return richText(nav) }
            if let fragments = metadata["fragments"] { return richText(fragments) }
            return String(richText(obj["abstract"]).prefix(60))
        }()

        let abstract = richText(obj["abstract"])

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

        if let sections = obj["primaryContentSections"] as? [Any] {
            for section in sections {
                guard let s = section as? [String: Any], let kind = s["kind"] as? String else { continue }
                switch kind {
                case "declarations":
                    if let decls = s["declarations"] as? [Any] {
                        for decl in decls {
                            guard let d = decl as? [String: Any] else { continue }
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
                    if let blocks = s["content"] as? [Any] {
                        for block in blocks {
                            guard let b = block as? [String: Any], let type = b["type"] as? String else { continue }
                            switch type {
                            case "paragraph", "heading", "aside":
                                let text = richText(b["inlineContent"])
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
                                        let text = richText(item["content"])
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

        var relatedLinks: [(title: String, url: String)] = []
        if let references = obj["references"] as? [String: Any] {
            let linkSections = ((obj["seeAlsoSections"] as? [Any]) ?? []) + ((obj["relationshipsSections"] as? [Any]) ?? [])
            for section in linkSections {
                guard let s = section as? [String: Any],
                      let identifiers = s["identifiers"] as? [String] else { continue }
                for ident in identifiers {
                    guard let ref = references[ident] as? [String: Any],
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

        return Page(
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

    static func richText(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String { return text }
            if let inline = dict["inlineContent"] { return richText(inline) }
            return ""
        }
        if let arr = value as? [Any] { return arr.map { richText($0) }.joined() }
        return ""
    }

    static func htmlTitle(_ html: String) -> String? {
        guard let range = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: range.upperBound..<html.endIndex) else {
            return nil
        }
        return String(html[range.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " | Apple Developer Documentation", with: "")
    }

    static func htmlMetaDescription(_ html: String) -> String? {
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

    static func htmlBodyText(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "head", "nav", "header", "footer"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func render(pages: [Page], platform: String?, query: String) -> String {
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

actor EnginesDocCache {
    struct Entry: Sendable {
        var data: Data
        var finalURL: URL
        var expires: Date
    }

    static let shared = EnginesDocCache()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let maxEntries = 100
    private let ttl: TimeInterval = 86_400

    func get(_ key: String) -> Entry? {
        guard let entry = entries[key], entry.expires > Date() else {
            entries[key] = nil
            order.removeAll { $0 == key }
            return nil
        }
        return entry
    }

    func set(_ key: String, data: Data, finalURL: URL) {
        if entries[key] == nil {
            order.append(key)
            while order.count > maxEntries, let oldest = order.first {
                order.removeFirst()
                entries[oldest] = nil
            }
        }
        entries[key] = Entry(data: data, finalURL: finalURL, expires: Date().addingTimeInterval(ttl))
    }
}

enum EnginesReverseOperation: String, CaseIterable, Sendable {
    case inspectArtifact = "inspect_artifact"
    case inspectMacho = "inspect_macho"
    case inspectPlist = "inspect_plist"
    case inspectSignature = "inspect_signature"
    case listArchitectures = "list_architectures"
    case demangleSwift = "demangle_swift"
    case inspectGoBinary = "inspect_go_binary"
    case inspectManagedArtifact = "inspect_managed_artifact"
    case inspectManagedMembers = "inspect_managed_members"
    case inspectSQLiteDatabase = "inspect_sqlite_database"
    case inspectWithObjdump = "inspect_with_objdump"
}

enum EnginesReverseObjdumpOperation: String, CaseIterable, Sendable {
    case fileHeaders = "file_headers"
    case sectionHeaders = "section_headers"
    case symbols
    case relocations
    case dwarf
    case disassemble
    case disassembleAll = "disassemble_all"
}

struct ReverseValidationError: Error, CustomStringConvertible, Sendable {
    let message: String
    var description: String { message }
}

enum EnginesReverseValidator {
    private static let blockedPrefixes: [String] = [
        "/System", "/sbin", "/usr", "/bin", "/etc", "/var", "/Library", "/private", "/dev",
    ]

    private static let refusalPatterns: [String] = [
        "bypass drm", "circumvent drm", "remove drm", "break drm",
        "bypass license", "circumvent license", "license check", "licence check",
        "crack", "keygen", "serial key",
        "anti-cheat", "anticheat", "game cheat", "cheat engine",
        "bypass authentication", "bypass auth", "bypass login",
        "bot protection", "bypass captcha",
    ]

    static func validateTarget(path: String?, workspaceRoot: URL) -> Result<String, ReverseValidationError> {
        func fail(_ message: String, remediation: String? = nil) -> Result<String, ReverseValidationError> {
            .failure(ReverseValidationError(message: message + (remediation.map { "\nRemediation: \($0)" } ?? "")))
        }
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fail(
                "No target supplied. Usage: @Reverse <absolute path to a file you are authorized to analyze> <what to investigate>.",
                remediation: "Example: @Reverse /Users/you/Downloads/myapp Inspect how this authorized binary loads its configuration."
            )
        }
        guard path.hasPrefix("/") else {
            return fail(
                "Target must be an absolute path (got '\(path)').",
                remediation: "Pass the full path, e.g. /Users/you/Downloads/myapp."
            )
        }
        guard !path.contains("..") else {
            return fail(
                "Target path must not contain '..' segments.",
                remediation: "Pass the canonical absolute path without traversal segments."
            )
        }
        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath()
        let resolvedPath = resolved.path
        for prefix in blockedPrefixes where resolvedPath == prefix || resolvedPath.hasPrefix(prefix + "/") {
            return fail(
                "Target '\(resolvedPath)' is inside a blocked system directory (\(prefix)).",
                remediation: "Analyze a copy in your project, Downloads, Desktop, or Documents instead."
            )
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if resolvedPath.hasPrefix(home + "/.") {
            return fail(
                "Target '\(resolvedPath)' is inside a hidden home directory, which is never in scope for Reverse.",
                remediation: "Move the artifact into Downloads, Desktop, Documents, or the open project."
            )
        }
        let allowedRoots: [String] = [
            workspaceRoot.resolvingSymlinksInPath().path,
            (home as NSString).appendingPathComponent("Downloads"),
            (home as NSString).appendingPathComponent("Desktop"),
            (home as NSString).appendingPathComponent("Documents"),
        ]
        let inScope = allowedRoots.contains { root in
            resolvedPath == root || resolvedPath.hasPrefix(root + "/")
        }
        guard inScope else {
            return fail(
                "Target '\(resolvedPath)' is outside the Reverse scope (open project, ~/Downloads, ~/Desktop, ~/Documents).",
                remediation: "Move the artifact into one of those locations, or open the containing project in SwiftCode."
            )
        }
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return fail(
                "Target does not exist: \(resolvedPath)",
                remediation: "Check the path and try again."
            )
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            return fail(
                "Target is a directory, not a file: \(resolvedPath)",
                remediation: "Pass the path of a single binary or artifact file."
            )
        }
        return .success(resolvedPath)
    }

    static func refusalMessage(forTask task: String) -> String? {
        let lower = task.lowercased()
        for pattern in refusalPatterns where lower.contains(pattern) {
            return "Reverse cannot help with that request: analyzing software to circumvent DRM, license checks, anti-cheat systems, or authentication is outside REA's permitted use (see REA DISCLAIMER.md) and outside this integration's scope.\nRemediation: Rephrase the investigation around behavior you are authorized to examine (e.g. configuration loading, file-format parsing, or error handling of software you own)."
        }
        return nil
    }

    static func clampTimeout(_ value: AnyJSON?) -> TimeInterval {
        let raw: Double?
        if let d = value?.double { raw = d } else if let i = value?.int { raw = Double(i) } else { raw = nil }
        guard let raw else { return 300 }
        return min(max(raw, 10), 1800)
    }
}
