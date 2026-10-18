import Foundation

public struct AssistLocalizationAuditTool: AssistTool {
    public let id = "localization_audit"
    public let name = "Localization Audit"
    public let description = "Compares localization keys across locales and reports missing keys and keys never referenced in Swift code."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits localization coverage. Takes no parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot.standardizedFileURL
        var keysByLocale: [String: Set<String>] = [:]
        var sourceFiles: [String] = []

        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return .failure("Failed to enumerate workspace.")
        }
        var swiftFiles: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == "Localizable.strings" {
                let locale = localeFor(url: url) ?? "unknown"
                let keys = parseStringsKeys(at: url)
                keysByLocale[locale, default: []].formUnion(keys)
                sourceFiles.append(relativePath(url, root: root))
            } else if name == "Localizable.xcstrings" {
                let perLocale = parseXCStringsKeys(at: url)
                for (locale, keys) in perLocale {
                    keysByLocale[locale, default: []].formUnion(keys)
                }
                sourceFiles.append(relativePath(url, root: root))
            } else if url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }
        if keysByLocale.isEmpty {
            return .success("No Localizable.strings or Localizable.xcstrings files found.", data: ["localeCount": "0", "totalKeys": "0"])
        }
        let allKeys = keysByLocale.values.reduce(Set<String>()) { $0.union($1) }
        var lines: [String] = []
        lines.append("Locales: \(keysByLocale.keys.sorted().joined(separator: ", "))")
        lines.append("Total distinct keys: \(allKeys.count)")
        lines.append("Localization files: \(sourceFiles.joined(separator: ", "))")
        var missingLines: [String] = []
        for locale in keysByLocale.keys.sorted() {
            let missing = allKeys.subtracting(keysByLocale[locale] ?? [])
            if missing.isEmpty {
                lines.append("\(locale): complete (\(keysByLocale[locale]?.count ?? 0) keys)")
            } else {
                lines.append("\(locale): missing \(missing.count) key(s)")
                for key in missing.sorted().prefix(50) {
                    missingLines.append("\(locale) missing: \(key)")
                }
            }
        }
        if !missingLines.isEmpty {
            lines.append("Missing keys:")
            lines.append(contentsOf: missingLines)
        }
        let unused = findUnusedKeys(allKeys: allKeys, swiftFiles: swiftFiles)
        if unused.isEmpty {
            lines.append("Unused keys: none found (all keys referenced in Swift files).")
        } else {
            lines.append("Unused keys (\(unused.count)): keys not referenced via NSLocalizedString / String(localized:) / quoted literal in Swift files:")
            for key in unused.sorted().prefix(100) {
                lines.append("- \(key)")
            }
        }
        return .success(lines.joined(separator: "\n"), data: [
            "localeCount": "\(keysByLocale.keys.count)",
            "totalKeys": "\(allKeys.count)",
            "unusedCount": "\(unused.count)",
            "unused": unused.sorted().joined(separator: ",")
        ])
    }

    private func localeFor(url: URL) -> String? {
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.hasSuffix(".lproj") {
            return String(parent.dropLast(".lproj".count))
        }
        return nil
    }

    private func parseStringsKeys(at url: URL) -> Set<String> {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var keys: Set<String> = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let keyPart = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
            var keyText = String(keyPart)
            if keyText.hasSuffix(";") { keyText = String(keyText.dropLast()) }
            keyText = keyText.trimmingCharacters(in: .whitespaces)
            if keyText.hasPrefix("\"") && keyText.hasSuffix("\"") && keyText.count >= 2 {
                let inner = String(keyText.dropFirst().dropLast())
                keys.insert(inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
            }
        }
        return keys
    }

    private func parseXCStringsKeys(at url: URL) -> [String: Set<String>] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else { return [:] }
        var result: [String: Set<String>] = [:]
        for (key, value) in strings {
            if let entry = value as? [String: Any],
               let localizations = entry["localizations"] as? [String: Any] {
                for locale in localizations.keys {
                    result[locale, default: []].insert(key)
                }
            }
        }
        return result
    }

    private func findUnusedKeys(allKeys: Set<String>, swiftFiles: [URL]) -> [String] {
        var swiftText = ""
        var scanned = 0
        for file in swiftFiles.prefix(2000) {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if content.count > 300_000 { continue }
            swiftText += "\n" + content
            scanned += 1
            if swiftText.count > 5_000_000 { break }
        }
        _ = scanned
        var unused: [String] = []
        for key in allKeys {
            let quoted = "\"\(key)\""
            if !swiftText.contains(quoted) {
                unused.append(key)
            }
        }
        return unused
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
