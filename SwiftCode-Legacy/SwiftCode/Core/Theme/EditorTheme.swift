import Foundation
import SwiftUI

public struct EditorTheme: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var background: String // Hex string
    public var foreground: String
    public var keywordColor: String
    public var stringColor: String
    public var commentColor: String
    public var numberColor: String
    public var typeColor: String
    public var accentColor: String
    public var selectionColor: String
    public var lineHighlightColor: String
    public var cursorColor: String
    public let isBuiltIn: Bool

    public init(id: String, name: String, background: String, foreground: String, keywordColor: String, stringColor: String, commentColor: String, numberColor: String, typeColor: String, accentColor: String, selectionColor: String = "#3E4451", lineHighlightColor: String = "#2C313C", cursorColor: String = "#528BFF", isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.background = background
        self.foreground = foreground
        self.keywordColor = keywordColor
        self.stringColor = stringColor
        self.commentColor = commentColor
        self.numberColor = numberColor
        self.typeColor = typeColor
        self.accentColor = accentColor
        self.selectionColor = selectionColor
        self.lineHighlightColor = lineHighlightColor
        self.cursorColor = cursorColor
        self.isBuiltIn = isBuiltIn
    }
}
