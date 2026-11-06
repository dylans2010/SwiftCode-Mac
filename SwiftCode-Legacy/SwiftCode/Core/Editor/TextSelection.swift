import Foundation

public struct TextSelection: Sendable, Codable, Equatable {
    public var range: NSRange
    public var cursorPosition: Int {
        return range.location
    }

    public init(range: NSRange) {
        self.range = range
    }

    public static var zero: TextSelection {
        return TextSelection(range: NSRange(location: 0, length: 0))
    }
}
