import Foundation

// MARK: - Code Indexing Service

@MainActor
final class CodeIndexService: ObservableObject {
    static let shared = CodeIndexService()

    @Published var entries: [IndexEntry] = []
    @Published var isIndexing = false

    private init() {}

    // MARK: - Index Project

    func indexProject(at directoryURL: URL) {
        isIndexing = true
        Task { @MainActor in
            let results = await Self.scanDirectory(directoryURL)
            self.entries = results
            self.isIndexing = false
        }
    }

    // MARK: - Index Single File

    func indexFile(content: String, filePath: String) -> [IndexEntry] {
        Self.parseSwiftSymbols(in: content, filePath: filePath)
    }

    // MARK: - Search

    func searchProject(
        query: String,
        at directoryURL: URL,
        caseSensitive: Bool = false,
        useRegex: Bool = false,
        fileExtension: String? = nil
    ) async -> [SearchResult] {
        return await Self.searchFiles(
            query: query,
            in: directoryURL,
            caseSensitive: caseSensitive,
            useRegex: useRegex,
            fileExtension: fileExtension
        )
    }

    // MARK: - Scanning

    private static func scanDirectory(_ url: URL) async -> [IndexEntry] {
        let fm = FileManager.default
        var results: [IndexEntry] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            results.append(contentsOf: parseSwiftSymbols(in: content, filePath: relativePath))
        }

        return results
    }

    // MARK: - Symbol Parsing

    private static func parseSwiftSymbols(in content: String, filePath: String) -> [IndexEntry] {
        var entries: [IndexEntry] = []
        let lines = content.components(separatedBy: "\n")

        let patterns: [(String, IndexEntry.SymbolKind)] = [
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:static\s+)?func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .function),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?struct\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .structType),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .classType),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?enum\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .enumType),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:static\s+)?var\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .variable),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:static\s+)?let\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .constant),
            (#"^\s*import\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .importDecl),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?protocol\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .protocolType),
            (#"^\s*extension\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, .extensionType),
        ]

        let regexes: [(NSRegularExpression, IndexEntry.SymbolKind)] = patterns.compactMap { pattern, kind in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, kind)
        }

        for (lineIndex, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            for (regex, kind) in regexes {
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges > 1 {
                    let nameRange = match.range(at: 1)
                    if nameRange.location != NSNotFound {
                        let name = nsLine.substring(with: nameRange)
                        entries.append(IndexEntry(
                            name: name,
                            kind: kind,
                            filePath: filePath,
                            lineNumber: lineIndex + 1,
                            snippet: line.trimmingCharacters(in: .whitespaces)
                        ))
                    }
                }
            }
        }

        return entries
    }

    // MARK: - Full Text Search

    private static func searchFiles(
        query: String,
        in directoryURL: URL,
        caseSensitive: Bool = false,
        useRegex: Bool = false,
        fileExtension: String? = nil
    ) async -> [SearchResult] {
        let fm = FileManager.default
        var results: [SearchResult] = []

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Comprehensive list of searchable text file extensions
        let allTextExtensions = Set([
            "swift", "json", "plist", "yml", "yaml", "md", "txt", "xml",
            "html", "css", "js", "ts", "tsx", "jsx", "py", "rb", "go",
            "rs", "kt", "java", "c", "cpp", "h", "hpp", "m", "mm",
            "sh", "bash", "zsh", "fish", "toml", "ini", "cfg", "conf",
            "gradle", "podspec", "xcconfig", "gitignore", "dockerfile",
            "graphql", "sql", "r", "pl", "php", "cs", "fs", "lua",
            "dart", "scala", "clj", "ex", "exs", "erl", "hs", "elm"
        ])

        // Build a regex or plain search closure
        let matchLine: (String) -> Bool
        if useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : .caseInsensitive
            if let regex = try? NSRegularExpression(pattern: query, options: options) {
                matchLine = { line in
                    let range = NSRange(line.startIndex..., in: line)
                    return regex.firstMatch(in: line, range: range) != nil
                }
            } else {
                // Invalid regex — fall back to plain search
                matchLine = Self.plainMatcher(query: query, caseSensitive: caseSensitive)
            }
        } else {
            matchLine = Self.plainMatcher(query: query, caseSensitive: caseSensitive)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            // Apply file extension filter if set
            if let filterExt = fileExtension {
                guard ext == filterExt else { continue }
            } else {
                guard allTextExtensions.contains(ext) else { continue }
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
            let fileName = fileURL.lastPathComponent
            let lines = content.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                if matchLine(line) {
                    results.append(SearchResult(
                        fileName: fileName,
                        filePath: relativePath,
                        lineNumber: lineIndex + 1,
                        snippet: line.trimmingCharacters(in: .whitespaces),
                        matchRange: nil
                    ))
                }
            }

            // Also match file name itself (only when using plain search)
            if !useRegex {
                let lname = caseSensitive ? fileName : fileName.lowercased()
                let lq = caseSensitive ? query : query.lowercased()
                if lname.contains(lq) && !results.contains(where: { $0.filePath == relativePath }) {
                    results.append(SearchResult(
                        fileName: fileName,
                        filePath: relativePath,
                        lineNumber: 1,
                        snippet: fileName,
                        matchRange: nil
                    ))
                }
            }
        }

        return results
    }

    /// Returns a closure that checks whether a line contains `query` using plain-text matching.
    private static func plainMatcher(query: String, caseSensitive: Bool) -> (String) -> Bool {
        let lq = caseSensitive ? query : query.lowercased()
        return { line in (caseSensitive ? line : line.lowercased()).contains(lq) }
    }
}
