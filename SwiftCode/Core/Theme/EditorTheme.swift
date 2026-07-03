import Foundation
import SwiftUI

public struct EditorTheme: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let background: String // Hex string
    public let foreground: String
    public let keywordColor: String
    public let stringColor: String
    public let commentColor: String
    public let numberColor: String
    public let typeColor: String
    public let accentColor: String
    public let isBuiltIn: Bool

    public init(id: String, name: String, background: String, foreground: String, keywordColor: String, stringColor: String, commentColor: String, numberColor: String, typeColor: String, accentColor: String, isBuiltIn: Bool) {
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
        self.isBuiltIn = isBuiltIn
    }
}
