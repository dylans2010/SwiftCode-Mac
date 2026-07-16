import SwiftUI

// MARK: - Code Coloring Theme

struct CodeColoringTheme: Identifiable, Equatable {
    let id: String
    var name: String
    var backgroundColor: Color
    var plainColor: Color
    var keywordColor: Color
    var stringColor: Color
    var commentColor: Color
    var numberColor: Color
    var typeColor: Color
    var functionColor: Color
    var lineHighlightColor: Color
    var selectionColor: Color
    var cursorColor: Color

    // MARK: - Built-in Themes

    static let dark = CodeColoringTheme(
        id: "dark",
        name: "Dark (Default)",
        backgroundColor: Color(red: 0.11, green: 0.11, blue: 0.15),
        plainColor: Color(red: 0.85, green: 0.85, blue: 0.85),
        keywordColor: Color(red: 0.98, green: 0.45, blue: 0.50),
        stringColor: Color(red: 0.90, green: 0.72, blue: 0.45),
        commentColor: Color(red: 0.45, green: 0.60, blue: 0.45),
        numberColor: Color(red: 0.68, green: 0.85, blue: 0.60),
        typeColor: Color(red: 0.60, green: 0.85, blue: 0.98),
        functionColor: Color(red: 0.68, green: 0.78, blue: 0.98),
        lineHighlightColor: Color.white.opacity(0.04),
        selectionColor: Color.blue.opacity(0.3),
        cursorColor: .orange
    )

    static let monokai = CodeColoringTheme(
        id: "monokai",
        name: "Monokai",
        backgroundColor: Color(red: 0.16, green: 0.16, blue: 0.15),
        plainColor: Color(red: 0.97, green: 0.97, blue: 0.97),
        keywordColor: Color(red: 0.99, green: 0.35, blue: 0.55),
        stringColor: Color(red: 0.90, green: 0.85, blue: 0.26),
        commentColor: Color(red: 0.47, green: 0.47, blue: 0.47),
        numberColor: Color(red: 0.68, green: 0.51, blue: 1.0),
        typeColor: Color(red: 0.40, green: 0.86, blue: 0.84),
        functionColor: Color(red: 0.65, green: 0.90, blue: 0.32),
        lineHighlightColor: Color.white.opacity(0.05),
        selectionColor: Color(red: 0.28, green: 0.28, blue: 0.36).opacity(0.7),
        cursorColor: Color(red: 0.99, green: 0.35, blue: 0.55)
    )

    static let solarizedDark = CodeColoringTheme(
        id: "solarized_dark",
        name: "Solarized Dark",
        backgroundColor: Color(red: 0.00, green: 0.17, blue: 0.21),
        plainColor: Color(red: 0.51, green: 0.58, blue: 0.59),
        keywordColor: Color(red: 0.52, green: 0.60, blue: 0.00),
        stringColor: Color(red: 0.17, green: 0.63, blue: 0.59),
        commentColor: Color(red: 0.40, green: 0.48, blue: 0.51),
        numberColor: Color(red: 0.80, green: 0.29, blue: 0.09),
        typeColor: Color(red: 0.27, green: 0.51, blue: 0.71),
        functionColor: Color(red: 0.42, green: 0.44, blue: 0.77),
        lineHighlightColor: Color.white.opacity(0.03),
        selectionColor: Color.blue.opacity(0.25),
        cursorColor: .cyan
    )

    static let github = CodeColoringTheme(
        id: "github",
        name: "GitHub Light",
        backgroundColor: Color(red: 0.98, green: 0.98, blue: 0.98),
        plainColor: Color(red: 0.10, green: 0.10, blue: 0.10),
        keywordColor: Color(red: 0.70, green: 0.10, blue: 0.55),
        stringColor: Color(red: 0.03, green: 0.44, blue: 0.68),
        commentColor: Color(red: 0.40, green: 0.40, blue: 0.40),
        numberColor: Color(red: 0.03, green: 0.52, blue: 0.06),
        typeColor: Color(red: 0.10, green: 0.20, blue: 0.70),
        functionColor: Color(red: 0.48, green: 0.25, blue: 0.03),
        lineHighlightColor: Color.black.opacity(0.03),
        selectionColor: Color.blue.opacity(0.15),
        cursorColor: .black
    )

    static let dracula = CodeColoringTheme(
        id: "dracula",
        name: "Dracula",
        backgroundColor: Color(hex: "#282A36"),
        plainColor: Color(hex: "#F8F8F2"),
        keywordColor: Color(hex: "#FF79C6"),
        stringColor: Color(hex: "#F1FA8C"),
        commentColor: Color(hex: "#6272A4"),
        numberColor: Color(hex: "#BD93F9"),
        typeColor: Color(hex: "#8BE9FD"),
        functionColor: Color(hex: "#50FA7B"),
        lineHighlightColor: Color.white.opacity(0.05),
        selectionColor: Color.blue.opacity(0.2),
        cursorColor: Color(hex: "#BD93F9")
    )

    static let oneDark = CodeColoringTheme(
        id: "one_dark",
        name: "One Dark",
        backgroundColor: Color(hex: "#282C34"),
        plainColor: Color(hex: "#ABB2BF"),
        keywordColor: Color(hex: "#C678DD"),
        stringColor: Color(hex: "#98C379"),
        commentColor: Color(hex: "#5C6370"),
        numberColor: Color(hex: "#D19A66"),
        typeColor: Color(hex: "#61AFEF"),
        functionColor: Color(hex: "#E5C07B"),
        lineHighlightColor: Color.white.opacity(0.04),
        selectionColor: Color.blue.opacity(0.2),
        cursorColor: Color(hex: "#C678DD")
    )

    static let allThemes: [CodeColoringTheme] = [.dark, .monokai, .solarizedDark, .github, .dracula, .oneDark]

    @MainActor
    static func theme(for id: String) -> CodeColoringTheme {
        // First try to resolve custom Theme colors dynamically in real-time
        if let appTheme = ThemeManager.shared.theme(for: id) {
            return CodeColoringTheme(
                id: appTheme.id,
                name: appTheme.name,
                backgroundColor: Color(hex: appTheme.colors.background),
                plainColor: Color(hex: appTheme.colors.editorText),
                keywordColor: Color(hex: appTheme.colors.syntaxKeyword),
                stringColor: Color(hex: appTheme.colors.syntaxString),
                commentColor: Color(hex: appTheme.colors.syntaxComment),
                numberColor: Color(hex: appTheme.colors.syntaxKeyword),
                typeColor: Color(hex: appTheme.colors.syntaxType),
                functionColor: Color(hex: appTheme.colors.accent),
                lineHighlightColor: Color(hex: appTheme.colors.panelBackground).opacity(0.3),
                selectionColor: Color(hex: appTheme.colors.accent).opacity(0.25),
                cursorColor: Color(hex: appTheme.colors.accent)
            )
        }

        // Fallback to presets
        switch id {
        case "light":
            return .github
        case "dracula":
            return .dracula
        case "one_dark":
            return .oneDark
        case "solarized":
            return .solarizedDark
        case "monokai":
            return .monokai
        default:
            return allThemes.first { $0.id == id } ?? .dark
        }
    }
}
