import Foundation

public actor ThemeStore {
    public static let shared = ThemeStore()

    private func themesDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    public func loadThemes() throws -> [EditorTheme] {
        let dir = try themesDirectory()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        var themes: [EditorTheme] = []
        for file in files where file.pathExtension == "swiftcodetheme" {
            if let theme = try? EditorTheme.read(file) {
                themes.append(theme)
            }
        }
        return themes
    }

    public func saveTheme(_ theme: EditorTheme) throws {
        let dir = try themesDirectory()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try theme.write(to: dir.appendingPathComponent(theme.fileName))
    }
}
