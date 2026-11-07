import Foundation
import SwiftUI

public struct MarkdownRenderOptions: Sendable, Hashable {
    public var isSyntaxHighlightingEnabled: Bool
    public var isTableOfContentsEnabled: Bool
    public var customThemeName: String?
    public var fontSize: CGFloat

    public init(
        isSyntaxHighlightingEnabled: Bool = true,
        isTableOfContentsEnabled: Bool = true,
        customThemeName: String? = nil,
        fontSize: CGFloat = 13.0
    ) {
        self.isSyntaxHighlightingEnabled = isSyntaxHighlightingEnabled
        self.isTableOfContentsEnabled = isTableOfContentsEnabled
        self.customThemeName = customThemeName
        self.fontSize = fontSize
    }
}
