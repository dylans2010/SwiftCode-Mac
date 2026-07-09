import Foundation

public enum SourceLanguage: String, Codable, Sendable {
    case swift
    case markdown
    case json
    case plainText
    case html
    case css
    case javascript
    case python
    // ... add more as needed, or transition to a full dynamic ID system

    public var fileExtensions: [String] {
        if let provider = LanguageManager.shared.provider(forId: self.rawValue) {
            return provider.fileExtensions
        }
        return []
    }

    public static func from(url: URL) -> SourceLanguage {
        if let provider = LanguageManager.shared.provider(for: url) {
            return SourceLanguage(rawValue: provider.id) ?? .plainText
        }
        return .plainText
    }
}
