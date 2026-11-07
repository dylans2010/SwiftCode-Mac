import Foundation

public enum SDKCodeLanguage: String, Sendable, Codable, CaseIterable, Hashable {
    case swift
    case typescript
    case javascript
    case json
    case markdown
    case plaintext

    public var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .plaintext: return "Plain Text"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .swift: return ["swift"]
        case .typescript: return ["ts", "tsx", "mts", "cts"]
        case .javascript: return ["js", "jsx", "mjs", "cjs"]
        case .json: return ["json"]
        case .markdown: return ["md", "markdown"]
        case .plaintext: return ["txt"]
        }
    }

    public static func infer(fromFileExtension ext: String) -> SDKCodeLanguage {
        var normalized = ext.lowercased()
        if normalized.hasPrefix(".") { normalized.removeFirst() }
        guard !normalized.isEmpty else { return .plaintext }
        for language in SDKCodeLanguage.allCases
            where language.fileExtensions.contains(normalized) {
            return language
        }
        return .plaintext
    }

    public static func infer(fromFileURL url: URL) -> SDKCodeLanguage {
        infer(fromFileExtension: url.pathExtension)
    }
}
