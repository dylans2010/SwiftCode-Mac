import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public class ThemeViewModel {
    public var themes: [EditorTheme] = []
    public var currentTheme: EditorTheme

    public init() {
        let defaultTheme = EditorTheme(
            id: "default-dark",
            name: "SwiftCode Dark",
            background: "#1E1E1E",
            foreground: "#D4D4D4",
            keywordColor: "#569CD6",
            stringColor: "#CE9178",
            commentColor: "#6A9955",
            numberColor: "#B5CEA8",
            typeColor: "#4EC9B0",
            accentColor: "#007AFF",
            isBuiltIn: true
        )
        self.currentTheme = defaultTheme
        self.themes = [defaultTheme]
    }

    public func loadThemes() async {
        do {
            let loaded = try await ThemeStore.shared.loadThemes()
            if !loaded.isEmpty {
                themes.append(contentsOf: loaded)
            }
        } catch {
            LoggingTool.error("Failed to load themes: \(error)")
        }
    }
}
