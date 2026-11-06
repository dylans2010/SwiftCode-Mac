import Foundation

/// One license template, discovered from a bundled `.txt` file.
public struct LicenseTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let summary: String
    public let body: String

    public init(id: String, name: String, category: String, summary: String, body: String) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.body = body
    }
}

/// Dynamically discovered license templates (ported from Legacy's
/// `LicenseCatalog`).
///
/// Legacy scanned `Bundle.main` for `*.txt` resources, skipping `sfsymbol*`
/// files, taking the first non-empty line as the name and classifying
/// `*exception*` files as "Exception" (everything else "SPDX"). This keeps
/// that behaviour, with one seam: `loadTemplates(directory:)` takes an
/// explicit directory so tests can point it at a fixture instead of the
/// bundle.
///
/// Resource-wiring caveat: Wave 18's SPDX corpus lives at repo level in
/// `packaging/licenses/spdx/` and is NOT copied into any target's bundle
/// resources, so `cachedTemplates` is empty until the corpus is wired into
/// a target (a `Package.swift` resources decision for the parent). The
/// catalogue never invents license text — an empty bundle means an empty
/// catalogue, never a hardcoded list.
public enum LicenseCatalog {
    /// Dynamically discovered and parsed license templates from the bundle resources.
    public static let cachedTemplates: [LicenseTemplate] = loadTemplates()
    public static var all: [LicenseTemplate] { cachedTemplates }

    public static func prewarm() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = cachedTemplates
        }
    }

    public static func licenseBody(for id: String) -> String? {
        all.first(where: { $0.id == id })?.body
    }

    /// Templates in `directory`, or in the main bundle when `directory` is nil.
    public static func loadTemplates(directory: URL? = nil) -> [LicenseTemplate] {
        let urls: [URL]
        if let directory {
            urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                .map { $0.filter { $0.pathExtension.lowercased() == "txt" } } ?? []
        } else if let bundleURLs = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) {
            urls = bundleURLs
        } else {
            urls = []
        }

        var templates: [LicenseTemplate] = []
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
                // Unreadable file: skip it rather than failing the whole catalogue.
                continue
            }
        }

        // Return sorted alphabetically by name
        return templates.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })
    }
}
