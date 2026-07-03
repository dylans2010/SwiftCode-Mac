import Foundation

public actor ThemeStore {
    public static let shared = ThemeStore()

    private var themesDirectory: URL {
        try! PathTool.appSupportDirectory().appendingPathComponent("Themes", isDirectory: true)
    }

    public func loadThemes() throws -> [EditorTheme] {
        if !FileManager.default.fileExists(atPath: themesDirectory.path) {
            try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        }

        let files = try FileManager.default.contentsOfDirectory(at: themesDirectory, includingPropertiesForKeys: nil)
        var themes: [EditorTheme] = []
        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            if let theme = try? JSONDecoder().decode(EditorTheme.self, from: data) {
                themes.append(theme)
            }
        }
        return themes
    }

    public func saveTheme(_ theme: EditorTheme) throws {
        let fileURL = themesDirectory.appendingPathComponent("\(theme.id).json")
        let data = try JSONEncoder().encode(theme)
        try data.write(to: fileURL)
    }
}
