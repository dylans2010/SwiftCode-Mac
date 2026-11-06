// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Shared/Markdown/MarkdownBlockRenderer.swift
//
// Verbatim apart from this header.

import Foundation
import SwiftUI

public protocol MarkdownBlockRenderer: Sendable {
    var supportedLanguages: Set<String> { get }

    @MainActor
    func renderBlock(language: String, code: String) -> AnyView
}
