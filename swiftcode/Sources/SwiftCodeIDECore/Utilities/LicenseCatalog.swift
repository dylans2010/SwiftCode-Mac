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
/// Wiring (Wave 19 slice E): the corpus is copied into this target at
/// `Resources/Licenses/` (`Package.swift`: `resources:
/// [.copy("Resources/Licenses")]` on `SwiftCodeIDECore`) and discovered
/// through `Bundle.module` as well as `Bundle.main`. The canonical store
/// stays `packaging/licenses/spdx/` (Wave 18). The catalogue never invents
/// license text — an empty bundle means an empty catalogue, never a
/// hardcoded list.
///
/// Dedup aliases: 40 Legacy IDs were byte-identical to a kept file (Wave 18
/// dedup, alphabetically-first keeper; sha256-verified in
/// `wave18/deduped.tsv`). Each is re-issued under its own ID with its
/// keeper's body, so `licenseBody(for:)` serves all 819 Legacy IDs.
/// Aliases apply to the bundle path only, never to an explicit directory
/// (the test seam stays a pure directory read).
///
/// Status: `LicencesAddView` is still missing and nothing calls this
/// catalogue yet — wiring makes it populate; the view is follow-up work.
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

    /// Dedup aliases (Wave 18, `wave18/deduped.tsv`): Legacy ID stem ->
    /// keeper ID stem. Each deduped file was byte-identical to its keeper
    /// (sha256-verified, 40/40), so the keeper's body serves the deduped
    /// ID too. No text is invented; the map only restores IDs the corpus
    /// lost when duplicate files were not written.
    static let dedupAliases: [String: String] = [
        "AGPL-1.0-or-later": "AGPL-1.0-only",
        "AGPL-3.0-or-later": "AGPL-3.0-only",
        "CAL-1.0": "CAL-1.0-Combined-Work-Exception",
        "GFDL-1.1-invariants-or-later": "GFDL-1.1-invariants-only",
        "GFDL-1.1-no-invariants-only": "GFDL-1.1-invariants-only",
        "GFDL-1.1-no-invariants-or-later": "GFDL-1.1-invariants-only",
        "GFDL-1.1-only": "GFDL-1.1-invariants-only",
        "GFDL-1.1-or-later": "GFDL-1.1-invariants-only",
        "GFDL-1.2-invariants-or-later": "GFDL-1.2-invariants-only",
        "GFDL-1.2-no-invariants-only": "GFDL-1.2-invariants-only",
        "GFDL-1.2-no-invariants-or-later": "GFDL-1.2-invariants-only",
        "GFDL-1.2-only": "GFDL-1.2-invariants-only",
        "GFDL-1.2-or-later": "GFDL-1.2-invariants-only",
        "GFDL-1.3-invariants-or-later": "GFDL-1.3-invariants-only",
        "GFDL-1.3-no-invariants-only": "GFDL-1.3-invariants-only",
        "GFDL-1.3-no-invariants-or-later": "GFDL-1.3-invariants-only",
        "GFDL-1.3-only": "GFDL-1.3-invariants-only",
        "GFDL-1.3-or-later": "GFDL-1.3-invariants-only",
        "GPL-1.0-or-later": "GPL-1.0-only",
        "GPL-2.0-or-later": "GPL-2.0-only",
        "GPL-3.0-or-later": "GPL-3.0-only",
        "LGPL-2.0-or-later": "LGPL-2.0-only",
        "LGPL-2.1-or-later": "LGPL-2.1-only",
        "LGPL-3.0-or-later": "LGPL-3.0-only",
        "MPL-2.0": "MPL-2.0-no-copyleft-exception",
        "OFL-1.0": "OFL-1.0-RFN",
        "OFL-1.0-no-RFN": "OFL-1.0-RFN",
        "OFL-1.1": "OFL-1.1-RFN",
        "OFL-1.1-no-RFN": "OFL-1.1-RFN",
        "deprecated_AGPL-1.0": "AGPL-1.0-only",
        "deprecated_AGPL-3.0": "AGPL-3.0-only",
        "deprecated_GFDL-1.1": "GFDL-1.1-invariants-only",
        "deprecated_GFDL-1.2": "GFDL-1.2-invariants-only",
        "deprecated_GFDL-1.3": "GFDL-1.3-invariants-only",
        "deprecated_GPL-1.0": "GPL-1.0-only",
        "deprecated_GPL-2.0": "GPL-2.0-only",
        "deprecated_GPL-3.0": "GPL-3.0-only",
        "deprecated_LGPL-2.0": "LGPL-2.0-only",
        "deprecated_LGPL-2.1": "LGPL-2.1-only",
        "deprecated_LGPL-3.0": "LGPL-3.0-only",
    ]

    /// Templates for the deduped IDs, copied from their keepers' parsed
    /// templates. Skips any ID whose keeper was not discovered (an empty
    /// bundle stays empty) and any ID already present.
    static func aliasedTemplates(from templates: [LicenseTemplate]) -> [LicenseTemplate] {
        var byID: [String: LicenseTemplate] = [:]
        for t in templates { if byID[t.id] == nil { byID[t.id] = t } }
        var out: [LicenseTemplate] = []
        for (dedupID, keeperID) in dedupAliases {
            guard byID[dedupID] == nil, let keeper = byID[keeperID] else { continue }
            out.append(LicenseTemplate(id: dedupID, name: keeper.name, category: keeper.category, summary: keeper.summary, body: keeper.body))
        }
        return out
    }

    /// Templates in `directory`, or in the main bundle when `directory` is nil.
    public static func loadTemplates(directory: URL? = nil) -> [LicenseTemplate] {
        let urls: [URL]
        if let directory {
            urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                .map { $0.filter { $0.pathExtension.lowercased() == "txt" } } ?? []
        } else {
            // Bundle path: the main bundle (Legacy behaviour) plus this
            // target's module bundle, where SwiftPM puts
            // `Resources/Licenses/` (see the wiring note above).
            var found: [URL] = []
            if let mainURLs = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) {
                found.append(contentsOf: mainURLs)
            }
            if let moduleURLs = Bundle.module.urls(forResourcesWithExtension: "txt", subdirectory: "Licenses") {
                found.append(contentsOf: moduleURLs)
            }
            var seenURLs = Set<URL>()
            urls = found.filter { seenURLs.insert($0).inserted }
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

        // Bundle path only: drop duplicate IDs (first wins — Bundle.main
        // before Bundle.module), then re-issue the 40 deduped Legacy IDs
        // under their own IDs (same body as their keeper).
        if directory == nil {
            var seenIDs = Set<String>()
            templates = templates.filter { seenIDs.insert($0.id).inserted }
            templates.append(contentsOf: aliasedTemplates(from: templates))
        }

        // Return sorted alphabetically by name
        return templates.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })
    }
}
