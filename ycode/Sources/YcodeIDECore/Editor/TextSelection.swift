// Adapted from SwiftCode-Legacy SwiftCode/Core/Editor/TextSelection.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
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
