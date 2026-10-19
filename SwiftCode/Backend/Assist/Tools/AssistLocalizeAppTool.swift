import Foundation

public struct AssistLocalizeAppTool: AssistTool {
    public let id = "localize_app"
    public let name = "App Localizer"
    public let description = "Fully localizes an app into up to 3 languages per session: discovers localizable strings in Swift sources, creates/merges a Localizable.xcstrings String Catalog with translations, and sets Info.plist CFBundleLocalizations + CFBundleDevelopmentRegion. Follows the LocalizingApps.md System Asset."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Localizes the app (default), reports localization status, or sets the development region.",
            properties: [
                "action": JSONSchema(type: "string", description: "localize (default), status, or set_development_region."),
                "languages": JSONSchema(type: "array", description: "Language codes to localize into, 1-3 per Assist session (e.g. [\"es\",\"fr\",\"de\"]). Required for action=localize.", items: JSONSchema(type: "string")),
                "translations": JSONSchema(type: "object", description: "Optional map of string-key -> language-code -> translated text. Keys or languages without a supplied translation are written with state \"new\" as untranslated placeholders for the model to translate later."),
                "development_region": JSONSchema(type: "string", description: "Development-region language code (default \"en\"). Sets the String Catalog source language on localize; the value to set for action=set_development_region.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = (input["action"] as? String ?? "localize").lowercased()
        guard action == "localize" || action == "status" || action == "set_development_region" else {
            return .failure("Invalid action '\(action)'. Expected localize, status, or set_development_region.", code: .invalidInput)
        }
        let workspaceRoot = context.workspaceRoot
        guard FileManager.default.fileExists(atPath: workspaceRoot.path) else {
            return .failure("Workspace root is not accessible.", code: .executionFailed)
        }
        switch action {
        case "status":
            return localizationStatus(workspaceRoot: workspaceRoot)
        case "set_development_region":
            let region = (input["development_region"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !region.isEmpty else {
                return .failure("Missing required parameter: development_region for action=set_development_region.", code: .missingArgument)
            }
            guard isValidLanguageCode(region) else {
                return .failure("Invalid language code '\(region)'. Expected 2-3 letters with an optional -Region suffix (e.g. en, es, pt-BR, zh-Hans).", code: .invalidInput)
            }
            return setDevelopmentRegion(region, workspaceRoot: workspaceRoot)
        default:
            let validation = validatedLanguages(input["languages"])
            guard let languages = validation.languages else {
                return .failure(validation.error ?? "Invalid languages parameter.", code: .invalidInput)
            }
            var region = (input["development_region"] as? String ?? "en").trimmingCharacters(in: .whitespacesAndNewlines)
            if region.isEmpty { region = "en" }
            guard isValidLanguageCode(region) else {
                return .failure("Invalid development_region '\(region)'. Expected a language code such as en.", code: .invalidInput)
            }
            let translations = normalizedTranslations(input["translations"])
            return localize(workspaceRoot: workspaceRoot, languages: languages, translations: translations, developmentRegion: region)
        }
    }

    // MARK: - localize

    private func localize(workspaceRoot: URL, languages: [String], translations: [String: [String: String]], developmentRegion: String) -> AssistToolResult {
        let plistURL = findInfoPlist(in: workspaceRoot)
        let targetDir = plistURL?.deletingLastPathComponent() ?? workspaceRoot

        let discovered = discoverLocalizableKeys(in: targetDir)
        guard !discovered.keys.isEmpty else {
            return .failure("No localizable strings found in Swift sources under '\(relativePath(of: targetDir, workspaceRoot: workspaceRoot))'. Wrap user-facing text in NSLocalizedString(_:comment:) or String(localized:) first.", code: .notFound)
        }

        let catalogURL = findCatalog(named: "Localizable.xcstrings", in: targetDir) ?? targetDir.appendingPathComponent("Localizable.xcstrings")
        let merge = mergeCatalog(at: catalogURL, sourceLanguage: developmentRegion, keys: discovered.keys, languages: languages, translations: translations)
        guard let merge else {
            return .failure("Failed to write String Catalog at '\(catalogURL.lastPathComponent)'.", code: .executionFailed)
        }
        guard verifyCatalog(at: catalogURL, keys: discovered.keys, languages: languages) else {
            return .failure("Verification failed: the String Catalog was not written correctly.", code: .executionFailed)
        }

        var filesChanged = [relativePath(of: catalogURL, workspaceRoot: workspaceRoot)]
        var plistNote = "No Info.plist found; CFBundleLocalizations was not updated."
        if let plistURL {
            if updatePlistLocalization(plistURL: plistURL, languages: languages, developmentRegion: developmentRegion) {
                filesChanged.append(relativePath(of: plistURL, workspaceRoot: workspaceRoot))
                plistNote = "Info.plist updated: CFBundleLocalizations=[\(languages.joined(separator: ", "))], CFBundleDevelopmentRegion=\(developmentRegion)."
            } else {
                return .failure("Wrote the String Catalog but failed to update Info.plist at '\(plistURL.lastPathComponent)'.", code: .executionFailed)
            }
        }

        let rtlLanguages = languages.filter(isRightToLeft)
        let direction = rtlLanguages.isEmpty ? "ltr" : "rtl"
        var summary = "Localized app into \(languages.count) language(s): \(languages.joined(separator: ", ")).\n"
        summary += "- Discovered \(discovered.keys.count) localizable key(s) in \(discovered.filesScanned) Swift file(s)."
        if discovered.skippedTableKeys > 0 {
            summary += " (\(discovered.skippedTableKeys) key(s) use a non-Localizable table and were skipped.)"
        }
        summary += "\n- String Catalog: \(relativePath(of: catalogURL, workspaceRoot: workspaceRoot)) — \(merge.totalKeys) key(s), \(merge.added) new localization(s) added, \(merge.updated) updated with supplied translations."
        summary += "\n- \(plistNote)"
        summary += "\n- Layout direction: \(direction)\(rtlLanguages.isEmpty ? "" : " (RTL languages: \(rtlLanguages.joined(separator: ", ")))")."
        if let plistURL, let note = infoPlistLocalizationNote(plistURL: plistURL) {
            summary += "\n- Note: \(note)"
        }
        summary += "\nNext: call localization_audit to find keys still missing per locale."

        return .success(
            summary,
            data: [
                AssistToolDataKey.count: "\(discovered.keys.count)",
                AssistToolDataKey.path: relativePath(of: catalogURL, workspaceRoot: workspaceRoot),
                "languages": languages.joined(separator: ","),
                "layoutDirection": direction,
                "sourceLanguage": developmentRegion,
                "keysAdded": "\(merge.added)"
            ],
            filesChanged: filesChanged,
            suggestedNextActions: ["localization_audit"]
        )
    }

    // MARK: - status

    private func localizationStatus(workspaceRoot: URL) -> AssistToolResult {
        let targetDir = findInfoPlist(in: workspaceRoot)?.deletingLastPathComponent() ?? workspaceRoot
        let discovered = discoverLocalizableKeys(in: targetDir)
        let catalogURL = findCatalog(named: "Localizable.xcstrings", in: targetDir)
        var catalogInfo = "absent"
        var catalogLanguages: [String] = []
        if let catalogURL,
           let root = readCatalog(at: catalogURL),
           let strings = root["strings"] as? [String: Any] {
            catalogInfo = "present"
            var langSet = Set<String>()
            for entry in strings.values {
                if let locs = (entry as? [String: Any])?["localizations"] as? [String: Any] {
                    langSet.formUnion(locs.keys)
                }
            }
            catalogLanguages = langSet.sorted()
            catalogInfo += " (\(strings.count) keys, languages: \(catalogLanguages.joined(separator: ", ")))"
        }
        var plistInfo = "No Info.plist found."
        if let plistURL = findInfoPlist(in: workspaceRoot), let dict = readPlist(at: plistURL) {
            let localizations = (dict["CFBundleLocalizations"] as? [String])?.joined(separator: ", ") ?? "not set"
            let region = dict["CFBundleDevelopmentRegion"] as? String ?? "not set"
            plistInfo = "\(plistURL.lastPathComponent): CFBundleLocalizations=[\(localizations)], CFBundleDevelopmentRegion=\(region)."
        }
        let summary = "Localization status:\n- Discovered keys in Swift: \(discovered.keys.count)\n- String Catalog: \(catalogInfo)\n- \(plistInfo)"
        return .success(
            summary,
            data: [
                AssistToolDataKey.count: "\(discovered.keys.count)",
                "languages": catalogLanguages.joined(separator: ","),
                "layoutDirection": catalogLanguages.contains(where: isRightToLeft) ? "rtl" : "ltr",
                "sourceLanguage": (catalogURL.flatMap { readCatalog(at: $0) }?["sourceLanguage"] as? String) ?? "unknown"
            ]
        )
    }

    // MARK: - set_development_region

    private func setDevelopmentRegion(_ region: String, workspaceRoot: URL) -> AssistToolResult {
        guard let plistURL = findInfoPlist(in: workspaceRoot) else {
            return .failure("No Info.plist found in the workspace; cannot set the development region.", code: .notFound)
        }
        guard var dict = readPlist(at: plistURL) else {
            return .failure("Info.plist at '\(plistURL.lastPathComponent)' is not a valid property list dictionary.", code: .executionFailed)
        }
        let before = dict["CFBundleDevelopmentRegion"] as? String ?? "not set"
        dict["CFBundleDevelopmentRegion"] = region
        guard writePlist(dict, to: plistURL),
              let verify = readPlist(at: plistURL),
              (verify["CFBundleDevelopmentRegion"] as? String) == region else {
            return .failure("Failed to set CFBundleDevelopmentRegion in Info.plist.", code: .executionFailed)
        }
        var note = ""
        let targetDir = plistURL.deletingLastPathComponent()
        if let catalogURL = findCatalog(named: "Localizable.xcstrings", in: targetDir),
           var root = readCatalog(at: catalogURL) {
            root["sourceLanguage"] = region
            if writeCatalog(root, to: catalogURL) {
                note = " Also set the String Catalog source language to \(region)."
            }
        }
        return .success(
            "Set CFBundleDevelopmentRegion to '\(region)' (was: \(before)).\(note)",
            data: [
                AssistToolDataKey.path: relativePath(of: plistURL, workspaceRoot: workspaceRoot),
                "sourceLanguage": region
            ],
            filesChanged: [relativePath(of: plistURL, workspaceRoot: workspaceRoot)]
        )
    }

    // MARK: - Validation helpers

    private func validatedLanguages(_ value: Any?) -> (languages: [String]?, error: String?) {
        guard let raw = value as? [Any], !raw.isEmpty else {
            return (nil, "Missing required parameter: languages (1-3 language codes, e.g. [\"es\",\"fr\",\"de\"]).")
        }
        var seen = Set<String>()
        var languages: [String] = []
        for item in raw {
            let code = (item as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, isValidLanguageCode(code) else {
                return (nil, "Invalid language code '\(code)'. Expected 2-3 letters with an optional -Region suffix (e.g. en, es, pt-BR, zh-Hans).")
            }
            if seen.insert(code).inserted { languages.append(code) }
        }
        guard !languages.isEmpty else {
            return (nil, "Missing required parameter: languages (1-3 language codes).")
        }
        guard languages.count <= 3 else {
            return (nil, "Too many languages (\(languages.count)). Maximum 3 languages per Assist session; run again for more.")
        }
        return (languages, nil)
    }

    private func isValidLanguageCode(_ code: String) -> Bool {
        code.range(of: "^[A-Za-z]{2,3}(-[A-Za-z]{2,4})?$", options: .regularExpression) != nil
    }

    private func isRightToLeft(_ code: String) -> Bool {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return ["ar", "he", "fa", "ur"].contains(base.lowercased())
    }

    private func normalizedTranslations(_ value: Any?) -> [String: [String: String]] {
        guard let dict = value as? [String: Any] else { return [:] }
        var result: [String: [String: String]] = [:]
        for (key, inner) in dict {
            guard !key.isEmpty else { continue }
            if let innerDict = inner as? [String: String] {
                result[key] = innerDict
            } else if let innerAny = inner as? [String: Any] {
                var converted: [String: String] = [:]
                for (lang, text) in innerAny {
                    if let text = text as? String { converted[lang] = text }
                }
                if !converted.isEmpty { result[key] = converted }
            }
        }
        return result
    }

    // MARK: - Discovery

    private func discoverLocalizableKeys(in targetDir: URL) -> (keys: Set<String>, skippedTableKeys: Int, filesScanned: Int) {
        let fm = FileManager.default
        var keys = Set<String>()
        var skippedTableKeys = 0
        var filesScanned = 0
        guard let enumerator = fm.enumerator(at: targetDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return (keys, skippedTableKeys, filesScanned)
        }
        let nsRegex = try? NSRegularExpression(pattern: #"NSLocalizedString\s*\(\s*"((?:[^"\\]|\\.)*)"\s*(?:,\s*tableName:\s*(?:"((?:[^"\\]|\\.)*)"|nil))?"#)
        let localizedRegex = try? NSRegularExpression(pattern: #"String\s*\(\s*localized:\s*"((?:[^"\\]|\\.)*)""#)
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            if path.contains("/build/") || path.contains("/DerivedData/") || path.contains("/.build/")
                || path.contains("/Pods/") || path.contains("/.swiftpm/") { continue }
            guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber,
                  size.intValue < 2_000_000,
                  let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            filesScanned += 1
            let range = NSRange(text.startIndex..., in: text)
            if let nsRegex {
                for match in nsRegex.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    let key = unescapeStringLiteral(String(text[keyRange]))
                    guard !key.isEmpty else { continue }
                    if match.range(at: 2).location != NSNotFound,
                       let tableRange = Range(match.range(at: 2), in: text) {
                        let table = String(text[tableRange])
                        if !table.isEmpty, table != "Localizable" {
                            skippedTableKeys += 1
                            continue
                        }
                    }
                    keys.insert(key)
                }
            }
            if let localizedRegex {
                for match in localizedRegex.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    let key = unescapeStringLiteral(String(text[keyRange]))
                    if !key.isEmpty { keys.insert(key) }
                }
            }
        }
        return (keys, skippedTableKeys, filesScanned)
    }

    private func unescapeStringLiteral(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    // MARK: - String Catalog (.xcstrings)

    private func findCatalog(named name: String, in targetDir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: targetDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == name else { continue }
            if url.path.contains("/build/") || url.path.contains("/DerivedData/") { continue }
            candidates.append(url)
        }
        return candidates.sorted { $0.path < $1.path }.first
    }

    private func readCatalog(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private func writeCatalog(_ root: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func mergeCatalog(at url: URL, sourceLanguage: String, keys: Set<String>, languages: [String], translations: [String: [String: String]]) -> (added: Int, updated: Int, totalKeys: Int)? {
        var root = readCatalog(at: url) ?? [:]
        root["sourceLanguage"] = sourceLanguage
        root["version"] = "1.0"
        var strings = root["strings"] as? [String: Any] ?? [:]
        var added = 0
        var updated = 0
        for key in keys.sorted() {
            var entry = strings[key] as? [String: Any] ?? [:]
            var localizations = entry["localizations"] as? [String: Any] ?? [:]
            // Source language always carries the key itself as the source text.
            if localizations[sourceLanguage] == nil {
                localizations[sourceLanguage] = ["stringUnit": ["state": "translated", "value": key]]
                added += 1
            }
            for language in languages {
                if language == sourceLanguage { continue }
                if let translation = translations[key]?[language], !translation.isEmpty {
                    let newUnit: [String: Any] = ["stringUnit": ["state": "translated", "value": translation]]
                    if let existing = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any],
                       (existing["value"] as? String) == translation,
                       (existing["state"] as? String) == "translated" {
                        continue
                    }
                    if localizations[language] != nil { updated += 1 } else { added += 1 }
                    localizations[language] = newUnit
                } else if localizations[language] == nil {
                    localizations[language] = ["stringUnit": ["state": "new", "value": ""]]
                    added += 1
                }
            }
            entry["localizations"] = localizations
            strings[key] = entry
        }
        root["strings"] = strings
        guard writeCatalog(root, to: url) else { return nil }
        return (added, updated, strings.count)
    }

    private func verifyCatalog(at url: URL, keys: Set<String>, languages: [String]) -> Bool {
        guard let root = readCatalog(at: url),
              let strings = root["strings"] as? [String: Any] else { return false }
        for key in keys {
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { return false }
            for language in languages where localizations[language] == nil {
                return false
            }
        }
        return true
    }

    // MARK: - Info.plist

    private func updatePlistLocalization(plistURL: URL, languages: [String], developmentRegion: String) -> Bool {
        guard var dict = readPlist(at: plistURL) else { return false }
        dict["CFBundleLocalizations"] = languages
        dict["CFBundleDevelopmentRegion"] = developmentRegion
        guard writePlist(dict, to: plistURL),
              let verify = readPlist(at: plistURL),
              (verify["CFBundleLocalizations"] as? [String]) == languages,
              (verify["CFBundleDevelopmentRegion"] as? String) == developmentRegion else { return false }
        return true
    }

    private func infoPlistLocalizationNote(plistURL: URL) -> String? {
        guard let dict = readPlist(at: plistURL) else { return nil }
        let candidates = ["CFBundleName", "CFBundleDisplayName"].filter { dict[$0] != nil }
        guard !candidates.isEmpty else { return nil }
        return "Info.plist keys \(candidates.joined(separator: ", ")) are best localized with InfoPlist.strings tables (see LocalizingApps.md), not the Localizable catalog."
    }

    private func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) else { return nil }
        return plist as? [String: Any]
    }

    private func writePlist(_ dict: [String: Any], to url: URL) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func findInfoPlist(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "Info.plist" else { continue }
            let path = url.path
            if path.contains("/build/") || path.contains("/DerivedData/") || path.contains("/.build/") { continue }
            candidates.append(url)
        }
        return candidates.sorted { $0.path < $1.path }.first
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path.hasPrefix(root + "/") { return String(url.path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}
