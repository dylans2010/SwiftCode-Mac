import Foundation

public struct AssistTestDataFactoryTool: AssistTool {
    public let id = "test_data_factory"
    public let name = "Test Data Factory"
    public let description = "Writes a test fixture file: a JSON object with sample values per field type, or a Swift struct with a static sample."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a fixture file from a field list such as id:Int,name:String.",
            properties: [
                "name": JSONSchema(type: "string", description: "Required. Valid Swift identifier used for the fixture type and file name."),
                "kind": JSONSchema(type: "string", description: "json or swift. Default: json."),
                "fields": JSONSchema(type: "string", description: "Optional comma list, e.g. id:Int,name:String,isActive:Bool. Defaults to id:Int,name:String."),
                "path": JSONSchema(type: "string", description: "Optional workspace-relative directory or file path. Default: TestData/."),
                "overwrite": JSONSchema(type: "string", description: "Must be 'true' to replace an existing file. Default: 'false'.")
            ],
            required: ["name"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let name = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .failure("Missing required parameter: name")
        }
        guard isValidIdentifier(name) else {
            return .failure("name '\(name)' is not a valid Swift identifier. Use letters, digits, and underscores, starting with a letter or underscore.")
        }
        let kind = ((input["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "json"
        guard kind == "json" || kind == "swift" else {
            return .failure("kind must be 'json' or 'swift'.")
        }
        let fieldsRaw = ((input["fields"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "id:Int,name:String"
        let fields: [(name: String, type: String)]
        do {
            fields = try parseFields(fieldsRaw)
        } catch {
            return .failure(error.localizedDescription)
        }
        let pathRaw = ((input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "TestData/"
        let overwrite = (input["overwrite"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            || (input["overwrite"] as? Bool) == true
        guard let fileURL = resolveFileURL(pathRaw: pathRaw, name: name, kind: kind, workspaceRoot: context.workspaceRoot) else {
            return .failure("path must be inside the workspace and must not contain '..'.")
        }
        if FileManager.default.fileExists(atPath: fileURL.path) && !overwrite {
            return .failure("File already exists at '\(relativePath(of: fileURL, workspaceRoot: context.workspaceRoot))'. Pass overwrite='true' to replace it.")
        }
        let content = kind == "json" ? buildJSON(fields: fields) : buildSwift(name: name, fields: fields)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write fixture file: \(error.localizedDescription)")
        }
        return .success("Created test fixture at \(relativePath(of: fileURL, workspaceRoot: context.workspaceRoot))", data: [
            "path": relativePath(of: fileURL, workspaceRoot: context.workspaceRoot),
            "kind": kind,
            "name": name
        ])
    }

    private func parseFields(_ raw: String) throws -> [(name: String, type: String)] {
        var fields: [(name: String, type: String)] = []
        for part in raw.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let pieces = trimmed.components(separatedBy: ":")
            let fieldName = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let fieldType = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : "String"
            guard isValidIdentifier(fieldName) else {
                throw NSError(domain: "AssistTestDataFactoryTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Field name '\(fieldName)' is not a valid Swift identifier."])
            }
            guard !fieldType.isEmpty else {
                throw NSError(domain: "AssistTestDataFactoryTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Field '\(fieldName)' has an empty type."])
            }
            fields.append((name: fieldName, type: fieldType))
        }
        guard !fields.isEmpty else {
            throw NSError(domain: "AssistTestDataFactoryTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "fields produced no usable fields."])
        }
        return fields
    }

    private func sampleJSONValue(for type: String, fieldName: String) -> String {
        switch type.lowercased() {
        case "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64":
            return "1"
        case "double", "float", "cgfloat":
            return "3.14"
        case "bool", "boolean":
            return "true"
        case "date":
            return "\"2026-01-01T00:00:00Z\""
        case "url":
            return "\"https://example.com/\(fieldName)\""
        case "uuid":
            return "\"00000000-0000-4000-8000-000000000001\""
        case "[string]", "array<string>":
            return "[\"Sample \(fieldName)\"]"
        case "[int]":
            return "[1]"
        default:
            return "\"Sample \(fieldName)\""
        }
    }

    private func sampleSwiftValue(for type: String, fieldName: String) -> String {
        switch type.lowercased() {
        case "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64":
            return "1"
        case "double", "float", "cgfloat":
            return "3.14"
        case "bool", "boolean":
            return "true"
        case "date":
            return "Date(timeIntervalSince1970: 1767225600)"
        case "url":
            return "URL(string: \"https://example.com/\(fieldName)\")!"
        case "uuid":
            return "UUID(uuidString: \"00000000-0000-4000-8000-000000000001\")!"
        default:
            return "\"Sample \(fieldName)\""
        }
    }

    private func buildJSON(fields: [(name: String, type: String)]) -> String {
        var lines: [String] = []
        lines.append("{")
        for (index, field) in fields.enumerated() {
            let comma = index < fields.count - 1 ? "," : ""
            lines.append("  \"\(field.name)\": \(sampleJSONValue(for: field.type, fieldName: field.name))\(comma)")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private func buildSwift(name: String, fields: [(name: String, type: String)]) -> String {
        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("")
        lines.append("struct \(name) {")
        for field in fields {
            lines.append("    let \(field.name): \(field.type)")
        }
        lines.append("")
        lines.append("    static let sample = \(name)(")
        for (index, field) in fields.enumerated() {
            let comma = index < fields.count - 1 ? "," : ""
            lines.append("        \(field.name): \(sampleSwiftValue(for: field.type, fieldName: field.name))\(comma)")
        }
        lines.append("    )")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private func resolveFileURL(pathRaw: String, name: String, kind: String, workspaceRoot: URL) -> URL? {
        if pathRaw.components(separatedBy: "/").contains("..") { return nil }
        let root = workspaceRoot.standardized
        let ext = kind == "json" ? "json" : "swift"
        let candidate: URL
        if pathRaw.hasSuffix("/") {
            candidate = root.appendingPathComponent(pathRaw).appendingPathComponent("\(name).\(ext)").standardized
        } else if pathRaw.hasSuffix(".json") || pathRaw.hasSuffix(".swift") {
            candidate = pathRaw.hasPrefix("/") ? URL(fileURLWithPath: pathRaw).standardized : root.appendingPathComponent(pathRaw).standardized
        } else {
            candidate = root.appendingPathComponent(pathRaw).appendingPathComponent("\(name).\(ext)").standardized
        }
        let rootPath = root.path
        if candidate.path == rootPath { return nil }
        if candidate.path.hasPrefix(rootPath + "/") { return candidate }
        return nil
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        guard CharacterSet.letters.contains(first) || first == "_" else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}
