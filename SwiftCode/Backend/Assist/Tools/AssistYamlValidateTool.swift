import Foundation

public struct AssistYamlValidateTool: AssistTool {
    public let id = "yaml_validate"
    public let name = "Validate YAML"
    public let description = "Heuristic YAML validation (no full YAML parser): rejects tab indentation, unbalanced brackets/quotes, duplicate top-level keys, and mapping lines without a colon. Format normalizes indentation to 2 spaces per level and only writes back when write is true and validation passes."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Heuristic YAML validation and optional formatting.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the YAML file."),
                "action": JSONSchema(type: "string", description: "Action: validate or format. Default: validate."),
                "write": JSONSchema(type: "string", description: "Pass \"true\" to write the formatted YAML back to the file on format, only when validation passes. Default: false.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = (input["path"] as? String), !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = resolveWorkspacePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(rawPath)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .failure("YAML validation requires an existing file: \(rawPath)")
        }

        let action = ((input["action"] as? String) ?? "validate").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "validate" || action == "format" else {
            return .failure("Invalid action '\(action)'. Allowed: validate, format.")
        }
        let shouldWrite = boolValue(input["write"])
        let relative = relativePath(url, workspaceRoot: context.workspaceRoot)

        let text: String
        do {
            let data = try Data(contentsOf: url)
            guard let decoded = String(data: data, encoding: .utf8) else {
                return .failure("File \(relative) is not valid UTF-8 text.")
            }
            text = decoded
        } catch {
            return .failure("Failed to read \(relative): \(error.localizedDescription)")
        }

        let errors = validateYAML(text)
        if !errors.isEmpty {
            return .failure("YAML validation failed (heuristic — no full YAML parser) in \(relative):\n\(errors.joined(separator: "\n"))")
        }

        if action == "validate" {
            return .success("YAML validation passed (heuristic — no full YAML parser) in \(relative).", data: ["path": relative, "valid": "true", "heuristic": "true", "written": "false"])
        }

        let formatted = formatYAML(text)
        if shouldWrite {
            guard let formattedData = formatted.data(using: .utf8) else {
                return .failure("Could not encode formatted YAML for \(relative) as UTF-8.")
            }
            do {
                try formattedData.write(to: url, options: [.atomic])
            } catch {
                return .failure("Failed to write formatted YAML to \(relative): \(error.localizedDescription)")
            }
            return .success("YAML validation passed (heuristic — no full YAML parser) in \(relative). Formatted YAML written back to the file.", data: ["path": relative, "valid": "true", "heuristic": "true", "written": "true", "formatted": formatted])
        }
        return .success("YAML validation passed (heuristic — no full YAML parser) in \(relative). Formatted preview returned without writing.", data: ["path": relative, "valid": "true", "heuristic": "true", "written": "false", "formatted": formatted])
    }

    private func validateYAML(_ text: String) -> [String] {
        var errors: [String] = []
        let rawLines = text.components(separatedBy: "\n")
        let lines = rawLines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var inSingle = false
        var inDouble = false
        var singleStartLine = 0
        var doubleStartLine = 0
        var bracketStack: [(char: Character, line: Int)] = []
        var blockScalarIndent: Int? = nil
        var seenTopKeys = Set<String>()

        for (index, line) in lines.enumerated() {
            let lineNo = index + 1
            let indent = line.prefix(while: { $0 == " " }).count
            let leadingRun = line.prefix(while: { $0 == " " || $0 == "\t" })
            let hasTabIndent = leadingRun.contains("\t")

            if let blockIndent = blockScalarIndent {
                let strippedForBlock = line.trimmingCharacters(in: .whitespaces)
                if strippedForBlock.isEmpty {
                    continue
                }
                if indent > blockIndent {
                    continue
                }
                blockScalarIndent = nil
            }

            if hasTabIndent {
                errors.append("Line \(lineNo): tab used for indentation (YAML requires spaces).")
            }

            let quoteOpenAtStart = inSingle || inDouble
            var cursor = line.startIndex
            var inComment = false
            while cursor < line.endIndex, !inComment {
                let ch = line[cursor]
                if inSingle {
                    if ch == "'" {
                        let next = line.index(after: cursor)
                        if next < line.endIndex, line[next] == "'" {
                            cursor = line.index(after: next)
                            continue
                        } else {
                            inSingle = false
                        }
                    }
                    cursor = line.index(after: cursor)
                    continue
                }
                if inDouble {
                    if ch == "\\" {
                        let next = line.index(after: cursor)
                        cursor = next < line.endIndex ? line.index(after: next) : line.endIndex
                        continue
                    }
                    if ch == "\"" { inDouble = false }
                    cursor = line.index(after: cursor)
                    continue
                }
                if ch == "#" {
                    let atStart = cursor == line.startIndex
                    let precededBySpace = !atStart && (line[line.index(before: cursor)] == " " || line[line.index(before: cursor)] == "\t")
                    if atStart || precededBySpace {
                        inComment = true
                        break
                    }
                    cursor = line.index(after: cursor)
                    continue
                }
                if ch == "'" {
                    inSingle = true
                    singleStartLine = lineNo
                } else if ch == "\"" {
                    inDouble = true
                    doubleStartLine = lineNo
                } else if ch == "[" || ch == "{" {
                    bracketStack.append((ch, lineNo))
                } else if ch == "]" || ch == "}" {
                    let expected: Character = (ch == "]") ? "[" : "{"
                    if let last = bracketStack.last, last.char == expected {
                        bracketStack.removeLast()
                    } else {
                        errors.append("Line \(lineNo): unbalanced closing bracket '\(ch)'.")
                    }
                }
                cursor = line.index(after: cursor)
            }

            if quoteOpenAtStart {
                continue
            }

            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            if stripped.hasPrefix("#") { continue }
            if stripped == "---" || stripped == "..." || stripped.hasPrefix("--- ") {
                if stripped == "---" {
                    seenTopKeys.removeAll()
                }
                continue
            }
            if stripped.hasPrefix("- ") || stripped == "-" {
                if isBlockScalarHeader(stripped, isListItem: true) {
                    blockScalarIndent = indent
                }
                continue
            }

            guard let colonIndex = stripped.firstIndex(of: ":") else {
                errors.append("Line \(lineNo): expected 'key: value' mapping (no colon found) — heuristic.")
                continue
            }
            if indent == 0 {
                let rawKey = String(stripped[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let key = rawKey.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !key.isEmpty, !key.hasPrefix("{") && !key.hasPrefix("[") && !key.hasPrefix("?") {
                    if seenTopKeys.contains(key) {
                        errors.append("Line \(lineNo): duplicate top-level key '\(key)'.")
                    } else {
                        seenTopKeys.insert(key)
                    }
                }
            }
            if isBlockScalarHeader(stripped, isListItem: false) {
                blockScalarIndent = indent
            }
        }

        if inSingle {
            errors.append("Unbalanced single quote opened at line \(singleStartLine).")
        }
        if inDouble {
            errors.append("Unbalanced double quote opened at line \(doubleStartLine).")
        }
        for unclosed in bracketStack {
            errors.append("Unbalanced opening bracket '\(unclosed.char)' opened at line \(unclosed.line).")
        }
        return errors
    }

    private func isBlockScalarHeader(_ stripped: String, isListItem: Bool) -> Bool {
        let content: String
        if isListItem {
            guard stripped.hasPrefix("- ") else { return false }
            content = String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("|") || content.hasPrefix(">") { return true }
            return false
        }
        guard let colonIndex = stripped.firstIndex(of: ":") else { return false }
        let value = String(stripped[stripped.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        guard let first = value.first, first == "|" || first == ">" else { return false }
        return true
    }

    private func formatYAML(_ text: String) -> String {
        let rawLines = text.components(separatedBy: "\n")
        let lines = rawLines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var step = 2
        var minPositive = Int.max
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            let leading = line.prefix(while: { $0 == " " }).count
            if leading > 0, leading < minPositive {
                minPositive = leading
            }
        }
        if minPositive != Int.max, minPositive >= 2 {
            step = minPositive
        }

        var output: [String] = []
        var blockScalarIndent: Int? = nil
        for line in lines {
            let strippedFull = line.trimmingCharacters(in: .whitespaces)
            if strippedFull.isEmpty {
                output.append("")
                continue
            }
            let indent = line.prefix(while: { $0 == " " }).count
            if let blockIndent = blockScalarIndent {
                if indent > blockIndent {
                    output.append(line)
                    continue
                }
                blockScalarIndent = nil
            }
            let stripped = line.trimmingCharacters(in: .whitespaces)
            let level = step > 0 ? indent / step : 0
            let newIndent = String(repeating: " ", count: level * 2)
            output.append(newIndent + stripped)
            if stripped.hasPrefix("- ") || stripped == "-" {
                if isBlockScalarHeader(stripped, isListItem: true) {
                    blockScalarIndent = indent
                }
            } else if isBlockScalarHeader(stripped, isListItem: false) {
                blockScalarIndent = indent
            }
        }
        return output.joined(separator: "\n")
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "true" || lowered == "1" || lowered == "yes"
        }
        return false
    }

    private func resolveWorkspacePath(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        let rootPath = workspaceRoot.standardized.path
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardized
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
        }
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func relativePath(_ url: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }
}
