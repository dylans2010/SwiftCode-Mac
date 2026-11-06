import Foundation

/// The localization-only agent used by LocalizingAppNewView's
/// "Localize App" button.
///
/// Hard rule, enforced in code (not just in a prompt): every file
/// write in a localization run goes through one of these four
/// registered Assist tools, via the same registry validation the
/// SDK runner uses. The model is only ever asked for translation
/// *text* (LLMService); it never touches a file, and no other tool
/// is reachable from this service — `runTool` throws for any id
/// outside the allowlist.
@MainActor
public enum LocalizingAppService {
    /// The complete, closed toolset for app localization.
    public static let allowedToolIDs: Set<String> = [
        "localize_app",          // scaffold: discover keys, merge catalog, update Info.plist
        "localization_manager",  // read/add/validate localization files
        "strings_localization",  // get/set/delete one string (writes "translated" state)
        "localization_audit",    // read-only coverage report
    ]

    public struct LocalizeProgress {
        public var stage: String
        public var translated: Int
        public var total: Int
    }

    public typealias ProgressHandler = (LocalizeProgress) -> Void

    // MARK: - Guarded tool execution

    /// Executes one localization tool through registry validation.
    /// Throws for any tool id outside `allowedToolIDs`, for failed
    /// validation, and for unsuccessful tool results — never silently.
    public static func runTool(
        id: String,
        arguments: [String: Any],
        workspaceRoot: URL
    ) async throws -> AssistToolResult {
        guard allowedToolIDs.contains(id) else {
            throw NSError(
                domain: "LocalizingAppService", code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Tool '\(id)' is not a localization tool and is blocked in localization runs."]
            )
        }
        let registry = AssistToolRegistry.shared
        let validation = registry.validate(toolId: id, arguments: arguments)
        guard validation.isValid else {
            throw NSError(
                domain: "LocalizingAppService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Tool '\(id)' failed validation: \(validation.issue ?? "invalid arguments"). Nothing was executed."]
            )
        }
        guard let tool = registry.getTool(registry.resolve(toolId: id)?.id ?? id) else {
            throw NSError(
                domain: "LocalizingAppService", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Tool '\(id)' is not registered. Nothing was executed."]
            )
        }
        let context = AssistContext(
            sessionId: UUID(),
            project: ProjectSessionStore.shared.activeProject,
            workspaceRoot: workspaceRoot,
            memory: AssistMemoryGraph(),
            logger: AssistLogger(),
            fileSystem: AssistFileSystem(workspaceRoot: workspaceRoot),
            git: AssistGitManager(project: ProjectSessionStore.shared.activeProject, workspaceRoot: workspaceRoot),
            permissions: AssistPermissionsManager(),
            safetyLevel: .balanced,
            isAutonomous: true
        )
        let result = try await tool.execute(input: validation.correctedInput ?? arguments, context: context)
        guard result.success else {
            throw NSError(
                domain: "LocalizingAppService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Tool '\(id)' failed: \(result.error ?? result.output)"]
            )
        }
        return result
    }

    // MARK: - One-click localization

    /// Fully localizes the app into `languages`:
    /// 1. `localize_app` discovers source strings, creates/merges the
    ///    String Catalog, and updates Info.plist localizations.
    /// 2. The model translates every source string (batched, JSON in /
    ///    JSON out) — translation text only, no file access.
    /// 3. Each translation is written back with `strings_localization`
    ///    (action `set`, state `translated`) — the only writer.
    /// Returns a human-readable summary. Throws on scaffold failure;
    /// a translation failure for a batch leaves that batch's strings
    /// as "new" placeholders and is reported in the summary, never
    /// faked with source-language text.
    public static func localizeApp(
        catalogURL: URL,
        workspaceRoot: URL,
        languages: [String],
        sourceLanguage: String,
        onProgress: ProgressHandler? = nil
    ) async throws -> String {
        let scaffold = try await runTool(
            id: "localize_app",
            arguments: [
                "action": "localize",
                "languages": languages,
                "development_region": sourceLanguage,
            ],
            workspaceRoot: workspaceRoot
        )
        // Re-read the catalog the tool just wrote: source strings are
        // the keys' source-language values.
        let catalog = try readCatalog(at: catalogURL)
        let sourceStrings = sourceStrings(from: catalog, sourceLanguage: sourceLanguage)
        guard !sourceStrings.isEmpty else {
            return scaffold.output + "\nNo source strings found to translate."
        }
        let relativePath = workspaceRelativePath(of: catalogURL, workspaceRoot: workspaceRoot)
        var translatedCount = 0
        var failedBatches: [String] = []
        let batches = sourceStrings.chunkedForLocalization(into: 25)
        for (index, batch) in batches.enumerated() {
            onProgress?(LocalizeProgress(
                stage: "Translating batch \(index + 1) of \(batches.count)…",
                translated: translatedCount,
                total: sourceStrings.count
            ))
            do {
                let translations = try await translate(batch: batch, languages: languages)
                for (key, perLanguage) in translations {
                    for language in languages where language != sourceLanguage {
                        guard let text = perLanguage[language], !text.isEmpty else { continue }
                        _ = try await runTool(
                            id: "strings_localization",
                            arguments: [
                                "action": "set",
                                "key": key,
                                "value": text,
                                "locale": language,
                                "path": relativePath,
                            ],
                            workspaceRoot: workspaceRoot
                        )
                        translatedCount += 1
                    }
                }
            } catch {
                failedBatches.append("batch \(index + 1): \(error.localizedDescription)")
            }
            onProgress?(LocalizeProgress(stage: "Translated \(translatedCount) of \(sourceStrings.count) strings.", translated: translatedCount, total: sourceStrings.count))
        }
        var summary = scaffold.output
        summary += "\nTranslated \(translatedCount) string(s) into \(languages.joined(separator: ", "))."
        if !failedBatches.isEmpty {
            summary += "\nNot translated (left as \"new\"): \(failedBatches.joined(separator: "; "))."
        }
        return summary
    }

    // MARK: - Catalog reading (for the editor + the AI flow)

    public struct CatalogEntry {
        public var key: String
        public var comment: String?
        /// language -> (state, value). Entries with variations and no
        /// stringUnit are represented with state "variations".
        public var localizations: [String: (state: String, value: String)]
    }

    public struct Catalog {
        public var sourceLanguage: String
        public var version: String
        public var entries: [CatalogEntry]
    }

    public static func readCatalog(at url: URL) throws -> Catalog {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LocalizingAppService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Localizable.xcstrings is not a JSON object."])
        }
        let sourceLanguage = json["sourceLanguage"] as? String ?? "en"
        let version = json["version"] as? String ?? "1.0"
        let strings = json["strings"] as? [String: Any] ?? [:]
        var entries: [CatalogEntry] = []
        for key in strings.keys.sorted() {
            let entry = strings[key] as? [String: Any] ?? [:]
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            var parsed: [String: (state: String, value: String)] = [:]
            for (language, loc) in localizations {
                let locDict = loc as? [String: Any] ?? [:]
                if let unit = locDict["stringUnit"] as? [String: Any] {
                    parsed[language] = (unit["state"] as? String ?? "new", unit["value"] as? String ?? "")
                } else {
                    parsed[language] = ("variations", "")
                }
            }
            entries.append(CatalogEntry(key: key, comment: entry["comment"] as? String, localizations: parsed))
        }
        return Catalog(sourceLanguage: sourceLanguage, version: version, entries: entries)
    }

    private static func sourceStrings(from catalog: Catalog, sourceLanguage: String) -> [(key: String, value: String)] {
        catalog.entries.compactMap { entry in
            guard let unit = entry.localizations[sourceLanguage], !unit.value.isEmpty else { return nil }
            return (entry.key, unit.value)
        }
    }

    private static func workspaceRelativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }

    // MARK: - Model translation (text only)

    private static func translate(
        batch: [(key: String, value: String)],
        languages: [String]
    ) async throws -> [String: [String: String]] {
        let input = Dictionary(uniqueKeysWithValues: batch.map { ($0.key, $0.value) })
        let inputJSON = String(data: try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]), encoding: .utf8) ?? "{}"
        let prompt = """
        Translate each app string below from English into \(languages.joined(separator: ", ")).
        Keep placeholders like %@, %d, and {name} exactly as-is. Keep the tone natural for app UI.
        Reply with ONLY a JSON object: { "stringKey": { "\(languages.first ?? "es")": "translation", ... }, ... }.
        Do not add explanations, markdown, or keys that were not given.
        Strings: \(inputJSON)
        """
        let raw = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
        let jsonText = stripCodeFences(raw)
        guard let data = jsonText.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            throw NSError(domain: "LocalizingAppService", code: 422, userInfo: [NSLocalizedDescriptionKey: "The model did not return usable JSON translations."])
        }
        return parsed
    }

    private static func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            result = result.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if let newline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array {
    func chunkedForLocalization(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var out: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            out.append(Array(self[index..<end]))
            index = end
        }
        return out
    }
}
