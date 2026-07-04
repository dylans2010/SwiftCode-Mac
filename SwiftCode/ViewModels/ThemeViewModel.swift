import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public class ThemeViewModel {
    public var themes: [EditorTheme] = []
    public var currentTheme: EditorTheme
    public var fontSize: CGFloat = 13.0
    public var fontFamily: String = "SF Mono"

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
            selectionColor: "#264F78",
            lineHighlightColor: "#2F3333",
            cursorColor: "#AEAFAD",
            isBuiltIn: true
        )

        let midnight = EditorTheme(
            id: "midnight",
            name: "Midnight",
            background: "#000000",
            foreground: "#FFFFFF",
            keywordColor: "#FF79C6",
            stringColor: "#F1FA8C",
            commentColor: "#6272A4",
            numberColor: "#BD93F9",
            typeColor: "#8BE9FD",
            accentColor: "#BD93F9",
            selectionColor: "#44475A",
            lineHighlightColor: "#44475A",
            cursorColor: "#F8F8F2",
            isBuiltIn: true
        )

        let solarizedDark = EditorTheme(
            id: "solarized-dark",
            name: "Solarized Dark",
            background: "#002B36",
            foreground: "#839496",
            keywordColor: "#859900",
            stringColor: "#2AA198",
            commentColor: "#586E75",
            numberColor: "#D33682",
            typeColor: "#B58900",
            accentColor: "#268BD2",
            selectionColor: "#073642",
            lineHighlightColor: "#073642",
            cursorColor: "#93A1A1",
            isBuiltIn: true
        )

        let monokai = EditorTheme(
            id: "monokai",
            name: "Monokai",
            background: "#272822",
            foreground: "#F8F8F2",
            keywordColor: "#F92672",
            stringColor: "#E6DB74",
            commentColor: "#75715E",
            numberColor: "#AE81FF",
            typeColor: "#66D9EF",
            accentColor: "#F92672",
            selectionColor: "#49483E",
            lineHighlightColor: "#3E3D32",
            cursorColor: "#F8F8F2",
            isBuiltIn: true
        )

        self.currentTheme = defaultTheme
        self.themes = [defaultTheme, midnight, solarizedDark, monokai]
    }

    public func loadThemes() async {
        do {
            let loaded = try await ThemeStore.shared.loadThemes()
            for theme in loaded {
                if !themes.contains(where: { $0.id == theme.id }) {
                    themes.append(theme)
                }
            }
        } catch {
            LoggingTool.error("Failed to load themes: \(error)")
        }
    }
}
