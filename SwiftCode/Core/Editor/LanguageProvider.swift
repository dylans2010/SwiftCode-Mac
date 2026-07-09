import Foundation

public enum LanguageCapability: String, Codable, Sendable {
    case build
    case run
    case livePreview
    case format
    case lint
    case autocomplete
    case diagnostics
}

public struct CommentSyntax: Sendable, Codable {
    public let linePrefix: String?
    public let blockStart: String?
    public let blockEnd: String?

    public init(linePrefix: String? = nil, blockStart: String? = nil, blockEnd: String? = nil) {
        self.linePrefix = linePrefix
        self.blockStart = blockStart
        self.blockEnd = blockEnd
    }
}

public protocol LanguageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var fileExtensions: [String] { get }
    var iconName: String { get }
    var iconColorName: String { get }
    var capabilities: Set<LanguageCapability> { get }
    var commentSyntax: CommentSyntax { get }
    var bracketPairs: [(open: String, close: String)] { get }

    func tokenize(line: String) -> [TokenizedLine.Token]
    func generateDefaultContent(fileName: String) -> String
}

extension LanguageProvider {
    public func generateDefaultContent(fileName: String) -> String {
        return ""
    }

    public var bracketPairs: [(open: String, close: String)] {
        [("{", "}"), ("(", ")"), ("[", "]")]
    }
}
