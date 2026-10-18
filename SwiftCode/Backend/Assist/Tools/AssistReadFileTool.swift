import Foundation

public struct AssistReadFileTool: AssistTool {
    public let id = "file_read"
    public let name = "Read File"
    public let description = "Reads the content of a file at the specified path. Pass lines {start,end} for a 1-based inclusive line range; omit lines to read the whole file."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads the content of a file at the specified path. Pass lines {start,end} for a 1-based inclusive line range; omit lines to read the whole file.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path to the file from the workspace root."),
                "lines": JSONSchema(
                    type: "object",
                    description: "Optional 1-based inclusive line range. start defaults to 1, end defaults to the last line. Both must be integers >= 1; start must be <= end. Out-of-range end is clamped to the last line; out-of-range start (start > totalLines) is an error, never invented content.",
                    properties: [
                        "start": JSONSchema(type: "integer", description: "1-based first line to return. Default: 1."),
                        "end": JSONSchema(type: "integer", description: "1-based last line to return, inclusive. Default: last line.")
                    ]
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard var path = (input["path"] ?? input["filePath"] ?? input["file_path"] ?? input["targetFile"] ?? input["file"]) as? String else {
            return .failure("Missing required parameter: path", code: .missingArgument)
        }

        if !path.hasPrefix("/tmp/swiftcode/scripts") {
            let workspacePrefix = context.workspaceRoot.path
            if !workspacePrefix.isEmpty && path.hasPrefix(workspacePrefix) {
                path = String(path.dropFirst(workspacePrefix.count))
            }
            while path.hasPrefix("/") {
                path = String(path.dropFirst())
            }
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            // Split preserving empty lines; a trailing newline does not create a phantom line.
            var lines = content.components(separatedBy: .newlines)
            if lines.last == "" { lines.removeLast() }
            let totalLines = lines.count
            let resolvedPath = (try? context.fileSystem.resolve(path).path) ?? path

            // Parse optional lines {start,end}; accept Int / integral Double / numeric String.
            // Also accept a JSON-stringified range ("{\"start\":240,\"end\":280}") since
            // some dispatch paths stringify nested arguments.
            var start = 1
            var end = totalLines
            var linesArg = input["lines"] as? [String: Any]
            if linesArg == nil, let linesString = input["lines"] as? String,
               let linesData = linesString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: linesData) as? [String: Any] {
                linesArg = parsed
            }
            if let range = linesArg {
                if let rawStart = range["start"] {
                    guard let parsed = Self.parseLineNumber(rawStart) else {
                        return .failure("Invalid lines.start: must be an integer >= 1 (got '\(rawStart)').", code: .invalidInput)
                    }
                    start = parsed
                }
                if let rawEnd = range["end"] {
                    guard let parsed = Self.parseLineNumber(rawEnd) else {
                        return .failure("Invalid lines.end: must be an integer >= 1 (got '\(rawEnd)').", code: .invalidInput)
                    }
                    end = parsed
                }
            }
            if start > end {
                return .failure("Invalid line range: start (\(start)) > end (\(end)). Lines are 1-based inclusive.)", code: .invalidInput)
            }
            if totalLines == 0 {
                return .success("File is empty: \(path)", data: [
                    "content": "", "path": resolvedPath,
                    "start": "1", "end": "0", "totalLines": "0", "fullyAvailable": "true"
                ])
            }
            if start > totalLines {
                return .failure("Line range start (\(start)) exceeds total lines (\(totalLines)) in \(path). No content invented.", code: .invalidInput)
            }
            let clampedEnd = min(end, totalLines)
            let slice = lines[(start - 1)...(clampedEnd - 1)]
            // Number every returned line so the model can cite exact lines.
            let numbered = slice.enumerated()
                .map { "\(start + $0.offset): \($0.element)" }
                .joined(separator: "\n")
            let fullyAvailable = (start == 1 && clampedEnd == totalLines)
            return .success("Successfully read file: \(path) (lines \(start)-\(clampedEnd) of \(totalLines))", data: [
                "content": numbered,
                "path": resolvedPath,
                "start": "\(start)", "end": "\(clampedEnd)",
                "totalLines": "\(totalLines)",
                "fullyAvailable": fullyAvailable ? "true" : "false"
            ])
        } catch {
            return .failure("Failed to read file at \(path): \(error.localizedDescription)", code: .executionFailed)
        }
    }

    private static func parseLineNumber(_ value: Any) -> Int? {
        if let i = value as? Int, i >= 1 { return i }
        if let d = value as? Double, d >= 1, d == d.rounded(), d <= Double(Int.max) { return Int(d) }
        if let s = value as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)), i >= 1 { return i }
        return nil
    }
}
