import Foundation
import Observation

public struct IndexedSymbol: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let kind: String
    public let file: String
    public let line: Int

    public init(name: String, kind: String, file: String, line: Int) {
        self.name = name
        self.kind = kind
        self.file = file
        self.line = line
    }
}

@Observable
@MainActor
public final class CodeIntelligenceEngine {
    public static let shared = CodeIntelligenceEngine()

    public var completions: [String] = []
    public var symbols: [String] = []

    private var symbolDocs: [String: String] = [:]

    public init() {}

    public func index(content: String) {
        let tokens = content.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
        completions = Array(Set(tokens.map(String.init))).sorted().prefix(40).map { $0 }
        let declarationLines = content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("func ") || $0.hasPrefix("struct ") || $0.hasPrefix("class ") || $0.hasPrefix("enum ") || $0.hasPrefix("protocol ") }
        symbols = declarationLines
        symbolDocs = Dictionary(uniqueKeysWithValues: declarationLines.map { line in
            (line, describe(declaration: line))
        })
    }

    public func quickDoc(for symbol: String) -> String {
        symbolDocs[symbol] ?? "No indexed documentation available."
    }

    private func describe(declaration: String) -> String {
        if declaration.hasPrefix("func ") { return "Function declaration. Review parameters and return type for usage." }
        if declaration.hasPrefix("struct ") { return "Struct type declaration. Value type used for models and UI state." }
        if declaration.hasPrefix("class ") { return "Class type declaration. Reference type, useful for shared mutable state." }
        if declaration.hasPrefix("enum ") { return "Enum declaration. Constrained set of states or options." }
        if declaration.hasPrefix("protocol ") { return "Protocol declaration. Defines required interface for conforming types." }
        return "Declaration indexed from active source file."
    }
}

@Observable
@MainActor
public final class SymbolIndexingEngine {
    public static let shared = SymbolIndexingEngine()

    public var symbols: [IndexedSymbol] = []

    public init() {}

    public func index(rootURL: URL?) {
        guard let rootURL else { symbols = []; return }
        var output: [IndexedSymbol] = []
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var swiftFiles: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL)
            }
        }
        for fileURL in swiftFiles.sorted(by: { $0.path < $1.path }) {
            guard let content = try? String(contentsOf: fileURL) else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let symbol = parseSymbol(from: trimmed) {
                    output.append(IndexedSymbol(name: symbol.name, kind: symbol.kind, file: relativePath, line: index + 1))
                }
            }
        }
        symbols = output.sorted {
            if $0.file == $1.file { return $0.line < $1.line }
            return $0.file < $1.file
        }
    }

    private func parseSymbol(from line: String) -> (name: String, kind: String)? {
        let prefixes: [(String, String)] = [
            ("struct ", "struct"), ("class ", "class"), ("enum ", "enum"),
            ("protocol ", "protocol"), ("func ", "func"), ("var ", "var"), ("let ", "let"),
        ]
        for (prefix, kind) in prefixes where line.hasPrefix(prefix) {
            let tail = line.dropFirst(prefix.count)
            let name = tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { return (String(name), kind) }
        }
        return nil
    }
}
