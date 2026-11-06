// ThemeManager.swift
//
// Moved from `swiftcode-ide/GeneralSettingsView.swift` (ThemeColors,
// AppTheme and ThemeManager were declared there at lines 162-290).
// SwiftCodeUI must own them: `SwiftCodeUI/App/NativeSettingsViews.swift`
// and `SwiftCodeUI/Editor/CodeColoringTheme.swift` use `ThemeManager.shared`,
// and `swiftcode-ide` (GeneralSettingsView) still uses all three types via
// its `SwiftCodeUI` dependency. Declarations are `public` (with explicit
// public memberwise inits) so the swiftcode-ide call sites keep resolving;
// every other line is verbatim from the origin file.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import Foundation

public struct ThemeColors: Codable, Equatable {
    public var background: String
    public var editorText: String
    public var syntaxKeyword: String
    public var syntaxString: String
    public var syntaxComment: String
    public var syntaxType: String
    public var accent: String
    public var toolbar: String
    public var panelBackground: String

    public init(
        background: String,
        editorText: String,
        syntaxKeyword: String,
        syntaxString: String,
        syntaxComment: String,
        syntaxType: String,
        accent: String,
        toolbar: String,
        panelBackground: String
    ) {
        self.background = background
        self.editorText = editorText
        self.syntaxKeyword = syntaxKeyword
        self.syntaxString = syntaxString
        self.syntaxComment = syntaxComment
        self.syntaxType = syntaxType
        self.accent = accent
        self.toolbar = toolbar
        self.panelBackground = panelBackground
    }
}

public struct AppTheme: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    public var colors: ThemeColors

    public init(id: String, name: String, isBuiltIn: Bool, colors: ThemeColors) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.colors = colors
    }

    public static let light = AppTheme(
        id: "light", name: "Light", isBuiltIn: true,
        colors: ThemeColors(
            background: "#FFFFFF", editorText: "#000000",
            syntaxKeyword: "#AD3DA4", syntaxString: "#C41A16",
            syntaxComment: "#007400", syntaxType: "#3900A0",
            accent: "#007AFF", toolbar: "#F2F2F7", panelBackground: "#F5F5F5"
        )
    )
    public static let dark = AppTheme(
        id: "dark", name: "Dark", isBuiltIn: true,
        colors: ThemeColors(
            background: "#1A1A2E", editorText: "#DCDCDC",
            syntaxKeyword: "#FC5FA3", syntaxString: "#FC6A5D",
            syntaxComment: "#6C7986", syntaxType: "#5DD8FF",
            accent: "#FF9500", toolbar: "#1C1C1E", panelBackground: "#242430"
        )
    )
    public static let monokai = AppTheme(
        id: "monokai", name: "Monokai", isBuiltIn: true,
        colors: ThemeColors(
            background: "#272822", editorText: "#F8F8F2",
            syntaxKeyword: "#F92672", syntaxString: "#E6DB74",
            syntaxComment: "#75715E", syntaxType: "#66D9EF",
            accent: "#A6E22E", toolbar: "#1E1F1C", panelBackground: "#3E3D32"
        )
    )
    public static let dracula = AppTheme(
        id: "dracula", name: "Dracula", isBuiltIn: true,
        colors: ThemeColors(
            background: "#282A36", editorText: "#F8F8F2",
            syntaxKeyword: "#FF79C6", syntaxString: "#F1FA8C",
            syntaxComment: "#6272A4", syntaxType: "#8BE9FD",
            accent: "#BD93F9", toolbar: "#21222C", panelBackground: "#343746"
        )
    )
    public static let oneDark = AppTheme(
        id: "one_dark", name: "One Dark", isBuiltIn: true,
        colors: ThemeColors(
            background: "#282C34", editorText: "#ABB2BF",
            syntaxKeyword: "#C678DD", syntaxString: "#98C379",
            syntaxComment: "#5C6370", syntaxType: "#61AFEF",
            accent: "#E06C75", toolbar: "#21252B", panelBackground: "#2C313A"
        )
    )
    public static let solarized = AppTheme(
        id: "solarized", name: "Solarized Dark", isBuiltIn: true,
        colors: ThemeColors(
            background: "#002B36", editorText: "#839496",
            syntaxKeyword: "#859900", syntaxString: "#2AA198",
            syntaxComment: "#586E75", syntaxType: "#268BD2",
            accent: "#B58900", toolbar: "#073642", panelBackground: "#073642"
        )
    )

    public static let builtIns: [AppTheme] = [.light, .dark, .monokai, .dracula, .oneDark, .solarized]
}


// MARK: - Theme Manager

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public var customThemes: [AppTheme] = [] {
        didSet { save() }
    }

    private let defaultsKey = "customThemes"

    private init() { load() }

    public var allThemes: [AppTheme] { AppTheme.builtIns + customThemes }
    public var themes: [AppTheme] { allThemes }

    public func theme(for id: String) -> AppTheme? {
        allThemes.first { $0.id == id }
    }

    public func add(_ theme: AppTheme) {
        var mutable = theme
        mutable.isBuiltIn = false
        customThemes.append(mutable)
    }

    public func update(_ theme: AppTheme) {
        if let idx = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[idx] = theme
        }
    }

    public func delete(_ theme: AppTheme) {
        customThemes.removeAll { $0.id == theme.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([AppTheme].self, from: data) else { return }
        customThemes = decoded
    }

    public func reset() { customThemes = [] }
}
