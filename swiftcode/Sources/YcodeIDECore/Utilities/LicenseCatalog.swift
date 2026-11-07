import Foundation

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

public enum LicenseCatalog {
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

    public static func loadTemplates(directory: URL? = nil) -> [LicenseTemplate] {
        let urls: [URL]
        if let directory {
            urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                .map { $0.filter { $0.pathExtension.lowercased() == "txt" } } ?? []
        } else {
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
            if filename.hasPrefix("sfsymbol") {
                continue
            }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let id = url.deletingPathExtension().lastPathComponent

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
                continue
            }
        }

        if directory == nil {
            var seenIDs = Set<String>()
            templates = templates.filter { seenIDs.insert($0.id).inserted }
            templates.append(contentsOf: aliasedTemplates(from: templates))
        }

        return templates.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })
    }
}
