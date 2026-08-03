import SwiftUI
import Combine

@Observable
@MainActor
public class TemplateManager {
    public static let shared = TemplateManager()

    public var templates: [FileTemplate] = []
    public var isLoading: Bool = false
    public var favorites: Set<String> = []
    public var recentlyUsed: [String] = []

    private let favoritesKey = "com.swiftcode.templates.favorites"
    private let recentsKey = "com.swiftcode.templates.recents"

    private init() {
        loadFavoritesAndRecents()
    }

    public func loadFavoritesAndRecents() {
        if let favArray = UserDefaults.standard.stringArray(forKey: favoritesKey) {
            favorites = Set(favArray)
        }
        if let recArray = UserDefaults.standard.stringArray(forKey: recentsKey) {
            recentlyUsed = recArray
        }
    }

    public func toggleFavorite(template: FileTemplate) {
        if favorites.contains(template.id) {
            favorites.remove(template.id)
        } else {
            favorites.insert(template.id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    public func recordUsage(template: FileTemplate) {
        recentlyUsed.removeAll { $0 == template.id }
        recentlyUsed.insert(template.id, at: 0)
        recentlyUsed = Array(recentlyUsed.prefix(8))
        UserDefaults.standard.set(recentlyUsed, forKey: recentsKey)
    }

    public func scanTemplates(projectURL: URL?) {
        guard templates.isEmpty else { return } // Prevent duplicate scans
        isLoading = true

        var discoveredURLs: [URL] = []

        // 1. Try scanning bundle resources subfolder
        if let bundleURLs = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: "File Templates") {
            discoveredURLs.extend(bundleURLs)
        }

        // 2. Fallback scan local workspace directory directly
        if let projectURL {
            let templatesFolder = projectURL.appendingPathComponent("SwiftCode/Resources/File Templates")
            if let fileURLs = try? FileManager.default.contentsOfDirectory(at: templatesFolder, includingPropertiesForKeys: nil) {
                for url in fileURLs {
                    if url.pathExtension == "txt" {
                        if !discoveredURLs.contains(where: { $0.lastPathComponent == url.lastPathComponent }) {
                            discoveredURLs.append(url)
                        }
                    }
                }
            }
        }

        var parsedTemplates: [FileTemplate] = []
        for url in discoveredURLs {
            if let template = parseTemplate(from: url) {
                parsedTemplates.append(template)
            }
        }

        // Sort templates alphabetically
        self.templates = parsedTemplates.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        self.isLoading = false
    }

    private func parseTemplate(from url: URL) -> FileTemplate? {
        guard let rawText = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var name = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        // Clean up category prefixes in filenames (e.g., "Swift_SwiftFile" -> "SwiftFile")
        if let underscoreIndex = name.firstIndex(of: "_") {
            name = String(name[name.index(after: underscoreIndex)...])
        }

        // Break camelCase or pascalCase into separate words for display name
        name = name.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        var category = "General"
        var description = "No description available."
        var suggestedExtension = url.deletingPathExtension().pathExtension
        if suggestedExtension == "txt" || suggestedExtension.isEmpty {
            suggestedExtension = "swift" // fallback default
        }
        var content = rawText

        let lines = rawText.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var headerLines: [String] = []
            var contentLines: [String] = []
            var isHeader = true
            for i in 1..<lines.count {
                let line = lines[i]
                if isHeader {
                    if line.trimmingCharacters(in: .whitespaces) == "---" {
                        isHeader = false
                    } else {
                        headerLines.append(line)
                    }
                } else {
                    contentLines.append(line)
                }
            }

            for hLine in headerLines {
                let parts = hLine.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    switch key.lowercased() {
                    case "name": name = value
                    case "category": category = value
                    case "description": description = value
                    case "extension": suggestedExtension = value
                    default: break
                    }
                }
            }
            content = contentLines.joined(separator: "\n")
        }

        let estLines = content.components(separatedBy: .newlines).count

        return FileTemplate(
            name: name,
            category: category,
            description: description,
            suggestedExtension: suggestedExtension,
            content: content,
            originalFileName: url.lastPathComponent,
            estimatedLineCount: estLines,
            isFolder: false
        )
    }
}

extension Array {
    mutating func extend(_ other: Array) {
        self.append(contentsOf: other)
    }
}
