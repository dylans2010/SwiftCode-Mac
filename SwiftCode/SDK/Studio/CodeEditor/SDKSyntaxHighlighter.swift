import Foundation

// MARK: - SDKTokenKind
//
// Semantic kind of a highlighted token. The highlighter emits these; the
// view layer maps each kind to a color. `plain` marks runs that carry no
// special meaning and render in the default text color.

public enum SDKTokenKind: String, Sendable, Codable, CaseIterable, Hashable {
    case keyword
    case string
    case comment
    case number
    case typeName
    case plain
}

// MARK: - SDKToken
//
// One highlighted run of text. `range` is a half-open range of UTF-16
// code-unit offsets into the input string (matching `NSString`/`NSRange`
// conventions without importing AppKit), so tokens can be applied to an
// `NSAttributedString` without re-indexing. Tokens in one result must be
// non-overlapping; gaps implicitly carry `.plain`.

public struct SDKToken: Sendable, Hashable {
    /// Half-open UTF-16 code-unit range into the highlighted string.
    public let range: Range<Int>
    public let kind: SDKTokenKind

    public init(range: Range<Int>, kind: SDKTokenKind) {
        self.range = range
        self.kind = kind
    }

    /// Length in UTF-16 code units.
    public var length: Int { range.upperBound - range.lowerBound }
}

// MARK: - SDKSyntaxHighlighter
//
// PURE syntax-highlighting contract: a stateless function from text to
// tokens. Implementations must not touch UI, the filesystem, or shared
// mutable state — highlighting is safe to run on any thread, which is why
// the protocol requires `Sendable`.
//
// The editor debounces calls and may invoke `highlight` off the main
// actor; results are applied back on the main actor by the view layer.

public protocol SDKSyntaxHighlighter: Sendable {
    /// Returns the highlighted tokens for `text` in `language`.
    /// Must be total: any string in any listed language returns a valid
    /// (possibly empty) token array, never throws, and never returns
    /// overlapping ranges.
    func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken]
}
