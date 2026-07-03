import Foundation
import SwiftUI

public struct MarkdownRenderer: Sendable {
    public static let shared = MarkdownRenderer()

    public func render(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown)
        } catch {
            return AttributedString(markdown)
        }
    }
}
