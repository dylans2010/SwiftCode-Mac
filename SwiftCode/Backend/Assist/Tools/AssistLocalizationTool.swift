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

        switch action.lowercased() {
        case "read_key":
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
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("\"\(key)\"") && trimmed.contains("=") {
                    return .success("Found localization: \(trimmed)")
                }
            }
            return .failure("Key '\(key)' not found in \(filePath)")

        case "add_translation":
            guard let key = input["key"] as? String, !key.isEmpty,
                  let translation = input["translation"] as? String else {
                return .failure("key and translation parameters are required for add_translation")
            }
            var content = ""
            if fileManager.fileExists(atPath: fileURL.path) {
                content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            }

            let escapedTrans = translation.replacingOccurrences(of: "\"", with: "\\\"")
            let newLine = "\"\(key)\" = \"\(escapedTrans)\";\n"
            content.append(newLine)

            do {
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return .success("Successfully added translation for '\(key)' in \(filePath)")
            } catch {
                return .failure("Failed to write translation: \(error.localizedDescription)")
            }

        case "validate":
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return .failure("File does not exist at: \(filePath)")
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return .failure("Cannot read \(filePath)")
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
                    } else {
                        keyCount += 1
                    }
                }
            }

            if syntaxErrors.isEmpty {
                return .success("Validation passed for \(filePath). Contains \(keyCount) localized entries with no syntax errors.")
            } else {
                return .failure("Validation errors in \(filePath):\n" + syntaxErrors.joined(separator: "\n"))
            }

        default:
            return .failure("Unsupported action '\(action)'. Valid: read_key, add_translation, validate")
        }
    }
}
