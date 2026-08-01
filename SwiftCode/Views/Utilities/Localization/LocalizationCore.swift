import Foundation
import os
import Observation

private let logger = Logger(subsystem: "com.swiftcode.app", category: "LocalizationCore")

public struct LocalizedKey: Identifiable, Codable, Hashable, Sendable {
    public var id: String { key }
    public var key: String
    public var translations: [String: String] // LanguageCode -> Translated String
    public var comment: String?
    public var isFavorite: Bool
}

public struct LocalizationFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let type: String // "xcstrings", "strings", "stringsdict", "infoplist"
}

public struct LocalizationValidationIssue: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let key: String
    public let message: String
    public let severity: String // "ERROR" or "WARNING"
}

// Codable models for Xcode 15+ String Catalogs (.xcstrings)
struct XCStringsFile: Codable {
    var sourceLanguage: String
    var strings: [String: XCStringsEntry]
}

struct XCStringsEntry: Codable {
    var localizations: [String: XCStringsLocalization]?
    var comment: String?
}

struct XCStringsLocalization: Codable {
    var stringUnit: XCStringsUnit
}

struct XCStringsUnit: Codable {
    var state: String
    var value: String
}

@Observable
@MainActor
public final class LocalizationCore {
    public static let shared = LocalizationCore()

    public var availableFiles: [LocalizationFile] = []
    public var isScanning: Bool = false

    // Changing selectedFile dynamically loads the actual keys and translations from disk!
    public var selectedFile: LocalizationFile? = nil {
        didSet {
            if let file = selectedFile {
                Task {
                    await loadFileContentsAsync(file)
                }
            }
        }
    }

    public var languages: [String] = ["en", "es", "fr", "de", "zh-Hans"]
    public var defaultLanguage: String = "en"
    public var activeLanguages: Set<String> = ["en", "es", "fr"]

    public var keys: [LocalizedKey] = []
    public var searchEditorQuery: String = ""
    public var filterMissingOnly: Bool = false
    public var selectedKey: LocalizedKey? = nil

    private init() {
        loadSettings()
        // Do not scan synchronously in init() to prevent any MainActor freeze!
    }

    /// Run the directory scanning processes asynchronously on detached background contexts
    /// (Task.detached(priority: .userInitiated)) and publish updates to the @MainActor thread.
    public func scanProjectFiles() {
        guard !isScanning else { return }
        isScanning = true

        let rootPath = FileManager.default.currentDirectoryPath
        let rootURL = URL(fileURLWithPath: rootPath)

        Task.detached(priority: .userInitiated) {
            logger.log("Beginning asynchronous off-thread file system scanning for localizations...")
            let startTime = Date()

            var found: [LocalizationFile] = []
            let fileManager = FileManager()
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            if let enumerator = enumerator {
                while let fileURL = enumerator.nextObject() as? URL {
                    // Fast path: skip scanning within heavy non-source directories
                    let pathString = fileURL.path
                    if pathString.contains("/build/") ||
                       pathString.contains("/.git/") ||
                       pathString.contains("/.github/") ||
                       pathString.contains("/node_modules/") {
                        enumerator.skipDescendants()
                        continue
                    }

                    let ext = fileURL.pathExtension.lowercased()
                    if ["strings", "stringsdict", "xcstrings"].contains(ext) {
                        let type: String
                        if fileURL.lastPathComponent == "InfoPlist.strings" {
                            type = "infoplist"
                        } else {
                            type = ext
                        }
                        let relPath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                        found.append(LocalizationFile(name: fileURL.lastPathComponent, path: relPath, type: type))
                    }
                }
            }

            // Seed default file structures on disk if none are found
            if found.isEmpty {
                let xcstringsPath = "Localizable.xcstrings"
                let xcstringsURL = rootURL.appendingPathComponent(xcstringsPath)
                if !fileManager.fileExists(atPath: xcstringsURL.path) {
                    let initialCatalog = XCStringsFile(
                        sourceLanguage: "en",
                        strings: [
                            "welcome_message": XCStringsEntry(
                                localizations: [
                                    "en": XCStringsLocalization(stringUnit: XCStringsUnit(state: "translated", value: "Welcome to SwiftCode!")),
                                    "es": XCStringsLocalization(stringUnit: XCStringsUnit(state: "translated", value: "¡Bienvenido a SwiftCode!")),
                                    "fr": XCStringsLocalization(stringUnit: XCStringsUnit(state: "translated", value: "Bienvenue sur SwiftCode!"))
                                ],
                                comment: "Welcome onboarding message"
                            )
                        ]
                    )
                    if let data = try? JSONEncoder().encode(initialCatalog) {
                        try? data.write(to: xcstringsURL)
                    }
                }
                found = [LocalizationFile(name: "Localizable.xcstrings", path: xcstringsPath, type: "xcstrings")]
            }

            let duration = Date().timeIntervalSince(startTime)
            logger.log("Asynchronous scanning completed in \(duration)s. Found \(found.count) files.")

            // Safe MainActor publishing update
            let finalFound = found
            await MainActor.run {
                self.availableFiles = finalFound
                if self.selectedFile == nil {
                    self.selectedFile = finalFound.first
                }
                self.isScanning = false
            }
        }
    }

    // MARK: - Disk Read / Write Engine

    private func loadFileContentsAsync(_ file: LocalizationFile) async {
        let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(file.path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        logger.log("Reading real localization asset from disk asynchronously: \(file.path)")

        let defaultLang = self.defaultLanguage

        if file.type == "xcstrings" {
            // Parse Xcode String Catalog JSON in a background context
            let loadedKeys = await Task.detached(priority: .userInitiated) { () -> [LocalizedKey]? in
                guard let data = try? Data(contentsOf: fileURL),
                      let catalog = try? JSONDecoder().decode(XCStringsFile.self, from: data) else {
                    return nil
                }
                var loaded: [LocalizedKey] = []
                for (keyName, entry) in catalog.strings {
                    var trans: [String: String] = [:]
                    if let localizations = entry.localizations {
                        for (langCode, loc) in localizations {
                            trans[langCode] = loc.stringUnit.value
                        }
                    }
                    loaded.append(LocalizedKey(
                        key: keyName,
                        translations: trans,
                        comment: entry.comment,
                        isFavorite: false
                    ))
                }
                return loaded
            }.value

            if let loadedKeys = loadedKeys {
                await MainActor.run {
                    self.keys = loadedKeys
                }
                logger.log("Loaded \(loadedKeys.count) keys from String Catalog.")
            }
        } else {
            // Parse standard .strings format: "key" = "value"; in a background context
            let loadedKeys = await Task.detached(priority: .userInitiated) { () -> [LocalizedKey]? in
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    return nil
                }
                var loaded: [LocalizedKey] = []
                let lines = content.components(separatedBy: .newlines)

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }

                    // Match "key" = "value";
                    let pattern = #"^\s*\"([^\"]+)\"\s*=\s*\"([^\"]*)\"\s*;\s*$"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {
                        if let keyRange = Range(match.range(at: 1), in: trimmed),
                           let valRange = Range(match.range(at: 2), in: trimmed) {
                            let key = String(trimmed[keyRange])
                            let val = String(trimmed[valRange])

                            loaded.append(LocalizedKey(
                                key: key,
                                translations: [defaultLang: val],
                                comment: nil,
                                isFavorite: false
                            ))
                        }
                    }
                }
                return loaded
            }.value

            if let loadedKeys = loadedKeys {
                await MainActor.run {
                    self.keys = loadedKeys
                }
                logger.log("Loaded \(loadedKeys.count) keys from .strings asset.")
            }
        }
    }

    public func saveFileContents() {
        guard let file = selectedFile else { return }
        let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(file.path)

        logger.log("Serializing and writing updated localizations back to disk asynchronously at: \(file.path)")

        let keysToSave = self.keys
        let fileType = file.type
        let defaultLang = self.defaultLanguage

        Task.detached(priority: .background) {
            if fileType == "xcstrings" {
                // Format back to Xcode String Catalog schema
                var stringsMap: [String: XCStringsEntry] = [:]
                for record in keysToSave {
                    var locs: [String: XCStringsLocalization] = [:]
                    for (lang, val) in record.translations {
                        locs[lang] = XCStringsLocalization(stringUnit: XCStringsUnit(state: "translated", value: val))
                    }
                    stringsMap[record.key] = XCStringsEntry(localizations: locs, comment: record.comment)
                }

                let catalog = XCStringsFile(sourceLanguage: defaultLang, strings: stringsMap)
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(catalog) {
                    try? data.write(to: fileURL, options: .atomic)
                    logger.log("String Catalog saved successfully asynchronously.")
                }
            } else {
                // Format to standard .strings structure
                var output = ""
                for record in keysToSave {
                    if let comment = record.comment, !comment.isEmpty {
                        output += "/* \(comment) */\n"
                    }
                    let val = record.translations[defaultLang] ?? ""
                    output += "\"\(record.key)\" = \"\(val)\";\n\n"
                }
                try? output.write(to: fileURL, atomically: true, encoding: .utf8)
                logger.log(".strings asset saved successfully asynchronously.")
            }
        }
    }

    // MARK: - Language Management

    public func addLanguage(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        if !languages.contains(trimmed) {
            languages.append(trimmed)
            activeLanguages.insert(trimmed)
            saveSettings()
            saveFileContents()
        }
    }

    public func removeLanguage(_ code: String) {
        guard code != defaultLanguage else { return }
        languages.removeAll { $0 == code }
        activeLanguages.remove(code)
        saveSettings()
        saveFileContents()
    }

    public func toggleLanguageActive(_ code: String) {
        if activeLanguages.contains(code) {
            guard code != defaultLanguage else { return }
            activeLanguages.remove(code)
        } else {
            activeLanguages.insert(code)
        }
        saveSettings()
        saveFileContents()
    }

    // MARK: - Key Management

    public func addKey(_ newKey: String, comment: String? = nil) {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !keys.contains(where: { $0.key == trimmed }) {
            let record = LocalizedKey(
                key: trimmed,
                translations: [defaultLanguage: trimmed],
                comment: comment,
                isFavorite: false
            )
            keys.append(record)
            saveSettings()
            saveFileContents()
        }
    }

    public func updateTranslation(key: String, lang: String, value: String) {
        if let idx = keys.firstIndex(where: { $0.key == key }) {
            let oldValue = keys[idx].translations[lang] ?? ""
            if oldValue != value {
                keys[idx].translations[lang] = value
                saveSettings()
                saveFileContents()
            }
        }
    }

    public func deleteKey(_ key: String) {
        keys.removeAll { $0.key == key }
        saveSettings()
        saveFileContents()
    }

    // MARK: - Validations

    public func validateTranslations() -> [LocalizationValidationIssue] {
        var issues: [LocalizationValidationIssue] = []
        let formatSpecifiers = ["%@", "%d", "%f", "%ld", "%lf"]

        for record in keys {
            // Missing Translations
            for lang in activeLanguages {
                let trans = record.translations[lang] ?? ""
                if trans.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(LocalizationValidationIssue(
                        key: record.key,
                        message: "Missing translation for language '\(lang)'.",
                        severity: "WARNING"
                    ))
                } else {
                    // Placeholder checks
                    let defaultTrans = record.translations[defaultLanguage] ?? ""
                    for spec in formatSpecifiers {
                        let countInDefault = defaultTrans.components(separatedBy: spec).count - 1
                        let countInTrans = trans.components(separatedBy: spec).count - 1
                        if countInDefault != countInTrans {
                            issues.append(LocalizationValidationIssue(
                                key: record.key,
                                message: "Inconsistent placeholders for '\(lang)'. Default has \(countInDefault) '\(spec)', Translation has \(countInTrans).",
                                severity: "ERROR"
                            ))
                        }
                    }
                }
            }
        }
        return issues
    }

    // MARK: - Import / Export

    public func exportCSV(to url: URL) throws {
        var csvString = "Key,Comment," + languages.joined(separator: ",") + "\n"
        for record in keys {
            var row = "\"\(record.key)\",\"\(record.comment ?? "")\""
            for lang in languages {
                let trans = record.translations[lang] ?? ""
                row += ",\"\(trans.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            csvString += row + "\n"
        }
        try csvString.write(to: url, atomically: true, encoding: .utf8)
        logger.log("Successfully exported translation file as CSV.")
    }

    public func importCSV(from url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = content.components(separatedBy: .newlines)
        guard rows.count > 1 else { return }

        // Parse header
        let headers = parseCSVRow(rows[0])
        guard headers.count > 2 else { return }

        var importedKeys: [LocalizedKey] = []
        for i in 1..<rows.count {
            let rowText = rows[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if rowText.isEmpty { continue }
            let columns = parseCSVRow(rowText)
            guard columns.count >= 2 else { continue }

            let key = columns[0]
            let comment = columns[1].isEmpty ? nil : columns[1]

            var translations: [String: String] = [:]
            for j in 2..<columns.count {
                if j < headers.count {
                    let langCode = headers[j]
                    translations[langCode] = columns[j]
                }
            }

            importedKeys.append(LocalizedKey(key: key, translations: translations, comment: comment, isFavorite: false))
        }

        if !importedKeys.isEmpty {
            self.keys = importedKeys
            saveSettings()
            saveFileContents()
        }
    }

    private func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        let chars = Array(row)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    current += "\""
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if c == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current += String(c)
            }
            i += 1
        }
        result.append(current)
        return result
    }

    // MARK: - Persistence Settings

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let langs = defaults.stringArray(forKey: "com.swiftcode.localization.languages") {
            self.languages = langs
        }
        if let defaultL = defaults.string(forKey: "com.swiftcode.localization.default") {
            self.defaultLanguage = defaultL
        }
        if let active = defaults.stringArray(forKey: "com.swiftcode.localization.active") {
            self.activeLanguages = Set(active)
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(languages, forKey: "com.swiftcode.localization.languages")
        defaults.set(defaultLanguage, forKey: "com.swiftcode.localization.default")
        defaults.set(Array(activeLanguages), forKey: "com.swiftcode.localization.active")
    }
}
