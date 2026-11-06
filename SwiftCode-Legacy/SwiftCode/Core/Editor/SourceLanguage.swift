import Foundation

public enum SourceLanguage: String, Codable, Sendable, CaseIterable {
    case swift
    case markdown
    case json
    case plainText

    public var fileExtensions: [String] {
        switch self {
        case .swift: return ["swift"]
        case .markdown: return ["md", "markdown"]
        case .json: return ["json"]
        case .plainText: return ["txt"]
        }
    }

    public static func from(url: URL) -> SourceLanguage {
        let ext = url.pathExtension.lowercased()
        for language in allCases {
            if language.fileExtensions.contains(ext) {
                return language
            }
        }
        return .plainText
    }
}
