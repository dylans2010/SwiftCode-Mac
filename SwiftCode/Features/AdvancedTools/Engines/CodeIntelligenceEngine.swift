import Foundation

@MainActor
final class CodeIntelligenceEngine: ObservableObject {
    static let shared = CodeIntelligenceEngine()

    @Published var completions: [String] = []
    @Published var symbols: [String] = []

    private var symbolDocs: [String: String] = [:]

    func index(content: String) {
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

    func quickDoc(for symbol: String) -> String {
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
