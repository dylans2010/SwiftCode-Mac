import Foundation
import SwiftUI

public protocol MarkdownBlockRenderer: Sendable {
    var supportedLanguages: Set<String> { get }

    @MainActor
    func renderBlock(language: String, code: String) -> AnyView
}
