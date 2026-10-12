import Foundation

// MARK: - SDKCodeLanguage
//
// Languages the Studio code editor can open and highlight. Raw values are
// stable identifiers (not display strings) so they can be persisted in
// document metadata without depending on UI copy.
//
// Language inference is deliberately conservative: an unknown or missing
// extension falls back to `.plaintext` rather than guessing, so the
// editor never claims a language it cannot highlight.

public enum SDKCodeLanguage: String, Sendable, Codable, CaseIterable, Hashable {
    case swift
    case typescript
    case javascript
    case json
    case markdown
    case plaintext

    /// User-facing display name, e.g. "TypeScript".
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

    /// Canonical file extensions for this language, lowercase, without the
    /// leading dot. Used by `infer(fromFileExtension:)`; the first entry is
    /// the preferred extension when the editor must invent a filename.
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

    /// Infers a language from a file extension (case-insensitive, leading
    /// dot optional). Returns `.plaintext` for unknown or empty extensions
    /// rather than failing: every file must be openable.
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

    /// Infers a language from a file URL's path extension. Files without an
    /// extension (e.g. `LICENSE`, `Makefile`) open as `.plaintext`.
    public static func infer(fromFileURL url: URL) -> SDKCodeLanguage {
        infer(fromFileExtension: url.pathExtension)
    }
}
