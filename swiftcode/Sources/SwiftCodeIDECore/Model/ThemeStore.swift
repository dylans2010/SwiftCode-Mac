// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Persistence/ThemeStore.swift
// Adapted for SwiftCode: Onto SwiftCode's own EditorTheme (Preferences.swift), not Legacy's Core/Theme/EditorTheme — different struct, different shape (SwiftCode themes are .swiftcodetheme files with #RRGGBB hex colours, read via EditorTheme.read / written via theme.write(to:)). Legacy theme files (.json, Legacy shape) do NOT decode here. PathTool replaced by FileManager's Application Support directory.

import Foundation

/// User themes on disk: scans a Themes directory for `*.swiftcodetheme` files
/// and decodes them with SwiftCode's own `EditorTheme` (see `Preferences.swift`).
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
