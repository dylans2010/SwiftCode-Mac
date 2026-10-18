import Foundation

public struct AssistStringsLocalizationTool: AssistTool {
    public let id = "strings_localization"
    public let name = "Localization Strings"
    public let description = "Gets, sets, or deletes a localization string in Localizable.strings or Localizable.xcstrings."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manages one localization string entry.",
            properties: [
                "action": JSONSchema(type: "string", description: "get, set, or delete. Default: get."),
                "key": JSONSchema(type: "string", description: "Localization key (required)."),
                "value": JSONSchema(type: "string", description: "Value for set action."),
                "locale": JSONSchema(type: "string", description: "Locale code such as en or fr. Default: en."),
                "path": JSONSchema(type: "string", description: "Optional workspace-relative path to a specific .strings or .xcstrings file.")
            ],
            required: ["key"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let key = input["key"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: key")
        }
        let action = ((input["action"] as? String) ?? "get").lowercased()
        guard action == "get" || action == "set" || action == "delete" else {
            return .failure("Invalid action '\(action)': must be get, set, or delete.")
        }
        if action == "set" {
            guard let value = input["value"] as? String, !value.isEmpty else {
                return .failure("Missing required parameter: value for set action.")
            }
        }
        let locale = ((input["locale"] as? String) ?? "en").trimmingCharacters(in: .whitespacesAndNewlines)
        if locale.isEmpty || locale.contains("/") || locale.contains("..") {
            return .failure("Invalid locale.")
        }
        let root = context.workspaceRoot.standardizedFileURL
        let fileURL: URL
        if let rawPath = input["path"] as? String, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = resolvePath(rawPath, workspaceRoot: context.workspaceRoot) else {
                return .failure("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                return .failure("Localization file not found at '\(rawPath)'.")
            }
            fileURL = resolved
        } else if let found = findLocalizationFile(locale: locale, root: root) {
            fileURL = found
        } else {
            return .failure("No Localizable.strings or Localizable.xcstrings found for locale '\(locale)'. Pass path to a specific file.")
        }
        if fileURL.pathExtension == "xcstrings" {
            return handleXCStrings(fileURL: fileURL, action: action, key: key, value: input["value"] as? String, locale: locale)
        }
        if fileURL.pathExtension == "strings" {
            return handleStrings(fileURL: fileURL, action: action, key: key, value: input["value"] as? String)
        }
        return .failure("Unsupported localization file type: \(fileURL.lastPathComponent). Expected .strings or .xcstrings.")
    }

    private func handleStrings(fileURL: URL, action: String, key: String, value: String?) -> AssistToolResult {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .failure("Failed to read \(fileURL.lastPathComponent).")
        }
        var lines = content.components(separatedBy: "\n")
        let escapedKey = escape(key)
        var foundIndex: Int?
        var foundValue: String?
        for (index, line) in lines.enumerated() {
            if let parsed = parseStringsLine(line), parsed.key == key {
                foundIndex = index
                foundValue = parsed.value
                break
            }
        }
        _ = escapedKey
        if action == "get" {
            if let foundValue = foundValue {
                return .success("Key '\(key)' = \"\(foundValue)\" in \(fileURL.lastPathComponent).", data: ["key": key, "value": foundValue, "file": fileURL.lastPathComponent])
            }
            return .failure("Key '\(key)' not found in \(fileURL.lastPathComponent).")
        }
        if action == "set" {
            let newLine = "\"\(escape(key))\" = \"\(escape(value ?? ""))\";"
            if let foundIndex = foundIndex {
                lines[foundIndex] = newLine
            } else {
                lines.append(newLine)
            }
            let updated = lines.joined(separator: "\n")
            do {
                try updated.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                return .failure("Failed to write \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
            guard let verify = try? String(contentsOf: fileURL, encoding: .utf8),
                  verify.contains("\"\(escape(key))\" = \"\(escape(value ?? ""))\";") else {
                return .failure("Verification failed: key not present after write.")
            }
            return .success("Set key '\(key)' in \(fileURL.lastPathComponent).", data: ["key": key, "value": value ?? "", "file": fileURL.lastPathComponent])
        }
        // delete
        guard let foundIndex = foundIndex else {
            return .failure("Key '\(key)' not found in \(fileURL.lastPathComponent).")
        }
        lines.remove(at: foundIndex)
        let updated = lines.joined(separator: "\n")
        do {
            try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        return .success("Deleted key '\(key)' from \(fileURL.lastPathComponent).", data: ["key": key, "file": fileURL.lastPathComponent])
    }

    private func handleXCStrings(fileURL: URL, action: String, key: String, value: String?, locale: String) -> AssistToolResult {
        guard let data = try? Data(contentsOf: fileURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Failed to read \(fileURL.lastPathComponent) as JSON.")
        }
        var strings = (json["strings"] as? [String: Any]) ?? [:]
        if action == "get" {
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let loc = localizations[locale] as? [String: Any],
                  let unit = loc["stringUnit"] as? [String: Any],
                  let found = unit["value"] as? String else {
                return .failure("Key '\(key)' not found for locale '\(locale)' in \(fileURL.lastPathComponent).")
            }
            return .success("Key '\(key)' (\(locale)) = \"\(found)\" in \(fileURL.lastPathComponent).", data: ["key": key, "value": found, "locale": locale, "file": fileURL.lastPathComponent])
        }
        if action == "set" {
            var entry = (strings[key] as? [String: Any]) ?? [:]
            var localizations = (entry["localizations"] as? [String: Any]) ?? [:]
            localizations[locale] = ["stringUnit": ["state": "translated", "value": value ?? ""]]
            entry["localizations"] = localizations
            strings[key] = entry
            json["strings"] = strings
            do {
                let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
                try out.write(to: fileURL, options: [.atomic])
            } catch {
                return .failure("Failed to write \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
            return .success("Set key '\(key)' (\(locale)) in \(fileURL.lastPathComponent).", data: ["key": key, "value": value ?? "", "locale": locale, "file": fileURL.lastPathComponent])
        }
        // delete
        guard var entry = strings[key] as? [String: Any],
              var localizations = entry["localizations"] as? [String: Any],
              localizations[locale] != nil else {
            return .failure("Key '\(key)' not found for locale '\(locale)' in \(fileURL.lastPathComponent).")
        }
        localizations.removeValue(forKey: locale)
        if localizations.isEmpty {
            strings.removeValue(forKey: key)
        } else {
            entry["localizations"] = localizations
            strings[key] = entry
        }
        json["strings"] = strings
        do {
            let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: fileURL, options: [.atomic])
        } catch {
            return .failure("Failed to write \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        return .success("Deleted key '\(key)' (\(locale)) from \(fileURL.lastPathComponent).", data: ["key": key, "locale": locale, "file": fileURL.lastPathComponent])
    }

    private func findLocalizationFile(locale: String, root: URL) -> URL? {
        let candidates = [
            "\(locale).lproj/Localizable.strings",
            "Localizable.xcstrings",
            "en.lproj/Localizable.strings",
            "Localizable.strings"
        ]
        for candidate in candidates {
            let url = root.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "Localizable.strings" || url.lastPathComponent == "Localizable.xcstrings" {
                return url
            }
        }
        return nil
    }

    private func parseStringsLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { return nil }
        guard let eqRange = trimmed.range(of: "=") else { return nil }
        let keyPart = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let valuePart = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let key = unquote(keyPart), let rawValue = unquote(valuePart) else { return nil }
        return (key: key, value: rawValue)
    }

    private func unquote(_ text: Substring) -> String? {
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

    private func resolvePath(_ rawPath: String, workspaceRoot: URL) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("..") { return nil }
        let root = workspaceRoot.standardizedFileURL
        if trimmed.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
            return candidate
        }
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }
}
