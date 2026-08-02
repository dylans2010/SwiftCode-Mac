import Foundation

public struct LicenseTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let summary: String
    public let body: String
}

@MainActor
public enum LicenseCatalog {
    /// Dynamically discovered and parsed license templates from the bundle resources.
    public static let cachedTemplates: [LicenseTemplate] = loadTemplates()
    public static var all: [LicenseTemplate] { cachedTemplates }

    public static func licenseBody(for id: String) -> String? {
        all.first(where: { $0.id == id })?.body
    }

    private static func loadTemplates() -> [LicenseTemplate] {
        var templates: [LicenseTemplate] = []

        // Find all TXT files bundled as offline resources in the application
        if let urls = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) {
            for url in urls {
                let filename = url.lastPathComponent.lowercased()
                // Skip any non-license text files (such as sf_symbols lists)
                if filename.hasPrefix("sfsymbol") {
                    continue
                }

                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let id = url.deletingPathExtension().lastPathComponent

                    // The first non-empty line of the SPDX file represents the official license name
                    let lines = content.components(separatedBy: .newlines)
                    var name = id
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            name = trimmed
                            break
                        }
                    }

                    let category = filename.contains("exception") ? "Exception" : "SPDX"
                    let summary = "Official SPDX license text for \(name)."

                    templates.append(LicenseTemplate(
                        id: id,
                        name: name,
                        category: category,
                        summary: summary,
                        body: content
                    ))
                } catch {
                    // Log and gracefully fallback
                    continue
                }
            }
        }

        // Return sorted alphabetically by name
        return templates.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })
    }
}
