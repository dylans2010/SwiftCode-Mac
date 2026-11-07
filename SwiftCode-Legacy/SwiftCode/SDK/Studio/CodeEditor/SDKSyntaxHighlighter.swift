import Foundation

public enum SDKTokenKind: String, Sendable, Codable, CaseIterable, Hashable {
    case keyword
    case string
    case comment
    case number
    case typeName
    case plain
}

public struct SDKToken: Sendable, Hashable {
    public let range: Range<Int>
    public let kind: SDKTokenKind

    public init(range: Range<Int>, kind: SDKTokenKind) {
        self.range = range
        self.kind = kind
    }

    public var length: Int { range.upperBound - range.lowerBound }
}

public protocol SDKSyntaxHighlighter: Sendable {
    func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken]
}
