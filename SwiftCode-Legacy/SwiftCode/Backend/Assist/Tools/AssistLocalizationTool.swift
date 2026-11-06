import Foundation

public struct AssistLocalizationTool: AssistTool {
    public let id = "localization_manager"
    public let name = "Localization Manager"
    public let description = "Inspects, extracts, adds translations, and validates .strings, .stringsdict, and .xcstrings localization files."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manage localizations across Apple platform projects.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'list_languages', 'read_key', 'add_translation', 'validate'."),
                "filePath": JSONSchema(type: "string", description: "Workspace-relative path to .strings or .xcstrings file."),
                "key": JSONSchema(type: "string", description: "Localization key (e.g. 'welcome_message')."),
                "translation": JSONSchema(type: "string", description: "Translated string value to insert.")
            ],
            required: ["action", "filePath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String,
              let filePath = input["filePath"] as? String else {
            return .failure("Missing required parameters: action and filePath")
        }

        let fileURL = context.workspaceRoot.appendingPathComponent(filePath)
        let fileManager = FileManager.default
        let ext = fileURL.pathExtension.lowercased()
        let lowered = action.lowercased()

        guard ["list_languages", "read_key", "add_translation", "validate"].contains(lowered) else {
            return .failure("Unsupported action '\(action)'. Valid: list_languages, read_key, add_translation, validate")
        }
        guard ["strings", "xcstrings", "stringsdict"].contains(ext) else {
            return .failure("Unsupported localization file type '\(ext)'. Expected .strings, .stringsdict, or .xcstrings.")
        }

        // list_languages works against the file plus its sibling locale files.
        if lowered == "list_languages" {
            return listLanguages(fileURL: fileURL, ext: ext, workspaceRoot: context.workspaceRoot)
        }

        if lowered == "validate" {
            return validate(fileURL: fileURL, ext: ext)
        }

        // read_key / add_translation
        switch ext {
        case "xcstrings":
            return handleXCStrings(fileURL: fileURL, action: lowered, key: input["key"] as? String, value: input["translation"] as? String, locale: localeForXCStrings(fileURL: fileURL))
        case "stringsdict":
            return handleStringsDict(fileURL: fileURL, action: lowered, key: input["key"] as? String, value: input["translation"] as? String)
        default: // strings
            if lowered == "add_translation" {
                guard let key = input["key"] as? String, !key.isEmpty,
                      let translation = input["translation"] as? String else {
                    return .failure("key and translation parameters are required for add_translation")
                }
                return addStringsTranslation(fileURL: fileURL, key: key, translation: translation)
            } else {
                guard let key = input["key"] as? String, !key.isEmpty else {
                    return .failure("key parameter is required for read_key")
                }
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    return .failure("Localization file does not exist at: \(filePath)")
                }
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    return .failure("Failed to read localization file: \(filePath)")
                }
                for line in content.components(separatedBy: .newlines) {
                    if let parsed = parseStringsLine(line), parsed.key == key {
                        return .success("Found localization: \"\(parsed.key)\" = \"\(parsed.value)\";")
                    }
                }
                return .failure("Key '\(key)' not found in \(filePath)")
            }
        }
    }

    // MARK: - list_languages

    private func listLanguages(fileURL: URL, ext: String, workspaceRoot: URL) -> AssistToolResult {
        var languages = Set<String>()
        let fileManager = FileManager.default

        if ext == "xcstrings", let data = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let strings = json["strings"] as? [String: Any] {
            for entry in strings.values {
                if let locs = (entry as? [String: Any])?["localizations"] as? [String: Any] {
                    languages.formUnion(locs.keys)
                }
            }
            if let source = json["sourceLanguage"] as? String { languages.insert(source) }
        } else if let own = localeFromLproj(fileURL: fileURL) {
            languages.insert(own)
        }

        // Sibling locale files (en.lproj, es.lproj, …) in the workspace.
        if let enumerator = fileManager.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let last = url.lastPathComponent
                if (last == "Localizable.strings" || last == "Localizable.xcstrings" || last == "InfoPlist.strings"),
                   let lang = localeFromLproj(fileURL: url) {
                    languages.insert(lang)
                }
            }
        }

        if languages.isEmpty {
            return .failure("No languages found. The file '\(fileURL.lastPathComponent)' has no detectable locales.")
        }
        let sorted = languages.sorted()
        return .success("Languages (\(sorted.count)): \(sorted.joined(separator: ", "))", data: [
            "languages": sorted.joined(separator: ","),
            "count": "\(sorted.count)"
        ])
    }

    private func localeFromLproj(fileURL: URL) -> String? {
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        if parent.hasSuffix(".lproj") {
            return String(parent.dropLast(".lproj".count))
        }
        return nil
    }

    // MARK: - validate (per file type)

    private func validate(fileURL: URL, ext: String) -> AssistToolResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File does not exist at: \(fileURL.lastPathComponent)")
        }
        switch ext {
        case "xcstrings":
            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure("Validation failed: \(fileURL.lastPathComponent) is not valid JSON.")
            }
            guard json["strings"] is [String: Any] else {
                return .failure("Validation failed: \(fileURL.lastPathComponent) is JSON but has no 'strings' dictionary.")
            }
            let count = (json["strings"] as? [String: Any])?.count ?? 0
            return .success("Validation passed for \(fileURL.lastPathComponent). Valid String Catalog with \(count) key(s).")
        case "stringsdict":
            guard let data = try? Data(contentsOf: fileURL),
                  let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
                return .failure("Validation failed: \(fileURL.lastPathComponent) is not a valid property list.")
            }
            return .success("Validation passed for \(fileURL.lastPathComponent). Valid property list.")
        default: // strings
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return .failure("Cannot read \(fileURL.lastPathComponent)")
            }
            let lines = content.components(separatedBy: .newlines)
            var keyCount = 0
            var syntaxErrors: [String] = []
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("/*") || trimmed.hasPrefix("//") || trimmed.hasPrefix("*") {
                    continue
                }
                if trimmed.hasPrefix("\"") {
                    if !trimmed.hasSuffix(";") {
                        syntaxErrors.append("Line \(idx + 1): missing terminating semicolon ';'")
                    } else if parseStringsLine(line) == nil {
                        syntaxErrors.append("Line \(idx + 1): malformed key = value entry")
                    } else {
                        keyCount += 1
                    }
                }
            }
            if syntaxErrors.isEmpty {
                return .success("Validation passed for \(fileURL.lastPathComponent). Contains \(keyCount) localized entries with no syntax errors.")
            } else {
                return .failure("Validation errors in \(fileURL.lastPathComponent):\n" + syntaxErrors.joined(separator: "\n"))
            }
        }
    }

    // MARK: - .strings write path

    private func addStringsTranslation(fileURL: URL, key: String, translation: String) -> AssistToolResult {
        let fileManager = FileManager.default
        var lines: [String] = []
        if fileManager.fileExists(atPath: fileURL.path) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return .failure("Failed to read localization file: \(fileURL.lastPathComponent)")
            }
            lines = content.components(separatedBy: "\n")
        }
        let newLine = "\"\(escape(key))\" = \"\(escape(translation))\";"
        var replaced = false
        for (index, line) in lines.enumerated() {
            if let parsed = parseStringsLine(line), parsed.key == key {
                lines[index] = newLine
                replaced = true
                break
            }
        }
        if !replaced {
            lines.append(newLine)
        }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write translation: \(error.localizedDescription)")
        }
        guard let verify = try? String(contentsOf: fileURL, encoding: .utf8),
              verify.contains(newLine) else {
            return .failure("Verification failed: key not present after write.")
        }
        return .success("Successfully \(replaced ? "updated" : "added") translation for '\(key)' in \(fileURL.lastPathComponent).")
    }

    // MARK: - .stringsdict (read + validate; writes refused honestly)

    private func handleStringsDict(fileURL: URL, action: String, key: String?, value: String?) -> AssistToolResult {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return .failure("Failed to read \(fileURL.lastPathComponent) as a property list.")
        }
        if action == "read_key" {
            guard let key = key, !key.isEmpty else {
                return .failure("key parameter is required for read_key")
            }
            guard let entry = plist[key] else {
                return .failure("Key '\(key)' not found in \(fileURL.lastPathComponent)")
            }
            return .success("Found localization entry for '\(key)': \(entry)")
        }
        // add_translation on a .stringsdict requires a plural/format-rule dictionary, not a
        // plain string; silently writing a plain string would corrupt the format rules.
        return .failure("add_translation is not supported for .stringsdict files: entries are plural/format-rule dictionaries, not plain strings. Use the .xcstrings String Catalog (or a .strings file) for plain string translations.")
    }

    // MARK: - .xcstrings read/write

    private func localeForXCStrings(fileURL: URL) -> String {
        localeFromLproj(fileURL: fileURL) ?? "en"
    }

    private func handleXCStrings(fileURL: URL, action: String, key: String?, value: String?, locale: String) -> AssistToolResult {
        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure("Failed to read \(fileURL.lastPathComponent) as JSON.")
            }
            json = parsed
        }
        var strings = (json["strings"] as? [String: Any]) ?? [:]

        if action == "read_key" {
            guard let key = key, !key.isEmpty else {
                return .failure("key parameter is required for read_key")
            }
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let loc = localizations[locale] as? [String: Any],
                  let unit = loc["stringUnit"] as? [String: Any],
                  let found = unit["value"] as? String else {
                return .failure("Key '\(key)' not found for locale '\(locale)' in \(fileURL.lastPathComponent).")
            }
            return .success("Key '\(key)' (\(locale)) = \"\(found)\" in \(fileURL.lastPathComponent).", data: ["key": key, "value": found, "locale": locale, "file": fileURL.lastPathComponent])
        }

        // add_translation
        guard let key = key, !key.isEmpty, let value = value else {
            return .failure("key and translation parameters are required for add_translation")
        }
        var entry = (strings[key] as? [String: Any]) ?? [:]
        var localizations = (entry["localizations"] as? [String: Any]) ?? [:]
        localizations[locale] = ["stringUnit": ["state": "translated", "value": value]]
        entry["localizations"] = localizations
        strings[key] = entry
        json["strings"] = strings
        if json["sourceLanguage"] == nil { json["sourceLanguage"] = "en" }
        if json["version"] == nil { json["version"] = "1.0" }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: fileURL, options: [.atomic])
        } catch {
            return .failure("Failed to write \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        return .success("Successfully added translation for '\(key)' (\(locale)) in \(fileURL.lastPathComponent).")
    }

    // MARK: - .strings line parsing

    private func parseStringsLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { return nil }
        guard let eqRange = trimmed.range(of: "=") else { return nil }
        let keyPart = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let valuePart = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let key = unquote(keyPart), let rawValue = unquote(valuePart) else { return nil }
        return (key: key, value: rawValue)
    }

    private func unquote(_ text: String) -> String? {
        var value = String(text)
        if value.hasSuffix(";") {
            value = String(value.dropLast())
        }
        value = value.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
        let inner = String(value.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
    }
}
