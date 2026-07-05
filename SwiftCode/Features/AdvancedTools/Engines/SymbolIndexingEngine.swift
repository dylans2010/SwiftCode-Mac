import Foundation

struct IndexedSymbol: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let file: String
    let line: Int
}

@MainActor
final class SymbolIndexingEngine: ObservableObject {
    static let shared = SymbolIndexingEngine()
    @Published var symbols: [IndexedSymbol] = []

    func index(project: Project?) {
        guard let project else { symbols = []; return }
        var output: [IndexedSymbol] = []
        for file in project.files {
            collectSymbols(in: file, project: project, results: &output)
        }
        symbols = output.sorted { lhs, rhs in
            if lhs.file == rhs.file { return lhs.line < rhs.line }
            return lhs.file < rhs.file
        }
    }

    private func collectSymbols(in node: FileNode, project: Project, results: inout [IndexedSymbol]) {
        if node.isDirectory {
            node.children.forEach { collectSymbols(in: $0, project: project, results: &results) }
            return
        }
        guard node.name.hasSuffix(".swift") else { return }

        let fileURL = project.directoryURL.appendingPathComponent(node.path)
        guard let content = try? String(contentsOf: fileURL) else { return }

        for (idx, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let symbol = parseSymbol(from: trimmed) {
                results.append(.init(name: symbol.name, kind: symbol.kind, file: node.path, line: idx + 1))
            }
        }
    }

    private func parseSymbol(from line: String) -> (name: String, kind: String)? {
        let prefixes: [(String, String)] = [("struct ", "struct"), ("class ", "class"), ("enum ", "enum"), ("protocol ", "protocol"), ("func ", "func"), ("var ", "var"), ("let ", "let")]
        for (prefix, kind) in prefixes where line.hasPrefix(prefix) {
            let tail = line.dropFirst(prefix.count)
            let name = tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { return (String(name), kind) }
        }
        return nil
    }
}
