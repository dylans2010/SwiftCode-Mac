//
//  AssistBinaryPlistConverterTool.swift
//  SwiftCode
//

import Foundation

public struct AssistBinaryPlistConverterTool: AssistTool {
    public let id = "binary_plist_converter"
    public let name = "Binary Plist Converter"
    public let description = "Converts property list files between XML and Binary formats using plutil."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Converts .plist files to human-readable XML or compact binary format via plutil.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to the .plist file."),
                "format": JSONSchema(type: "string", description: "Target format: 'xml1' (human-readable) or 'binary1'. Defaults to 'xml1'.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        let format = (input["format"] as? String)?.lowercased() ?? "xml1"

        let resolvedURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return .failure("File not found at: \(resolvedURL.path)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        proc.arguments = ["-convert", format, resolvedURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                return .success("Successfully converted `\(path)` to \(format) format.")
            } else {
                return .failure("plutil conversion failed: \(err)")
            }
        } catch {
            return .failure("Failed to execute plutil: \(error.localizedDescription)")
        }
    }
}
