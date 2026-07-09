import Foundation
import SwiftUI

public final class LanguageManager: Sendable {
    public static let shared = LanguageManager()

    private let providers: [String: LanguageProvider]
    private let extensionMap: [String: String]

    private init() {
        var providers: [String: LanguageProvider] = [:]
        var extensionMap: [String: String] = [:]

        let core: [LanguageProvider] = [
            SwiftLanguageProvider(),
            HTMLLanguageProvider(),
            MarkdownLanguageProvider(),
            JavaScriptLanguageProvider(),
            PythonLanguageProvider()
        ]

        for provider in core {
            providers[provider.id] = provider
            for ext in provider.fileExtensions {
                extensionMap[ext.lowercased()] = provider.id
            }
        }

        self.providers = providers
        self.extensionMap = extensionMap
    }

    // We'll use a temporary initializer that we'll update in Phase 3
    internal init(providers: [LanguageProvider]) {
        var pMap: [String: LanguageProvider] = [:]
        var eMap: [String: String] = [:]

        for provider in providers {
            pMap[provider.id] = provider
            for ext in provider.fileExtensions {
                eMap[ext.lowercased()] = provider.id
            }
        }

        self.providers = pMap
        self.extensionMap = eMap
    }

    public func provider(for url: URL) -> LanguageProvider? {
        let ext = url.pathExtension.lowercased()
        guard let id = extensionMap[ext] else { return nil }
        return providers[id]
    }

    public func provider(forId id: String) -> LanguageProvider? {
        return providers[id]
    }

    public var allProviders: [LanguageProvider] {
        Array(providers.values)
    }

    @MainActor
    public func color(for colorName: String) -> Color {
        switch colorName {
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        case "yellow": return .yellow
        case "green": return .green
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .secondary
        }
    }
}
