//
//  AssistStringCatalogMigratorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistStringCatalogMigratorTool: AssistTool {
    public let id = "string_catalog_migrator"
    public let name = "String Catalog Migrator"
    public let description = "Converts legacy .strings files into modern Xcode 15+ String Catalogs (.xcstrings)."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Transforms a legacy .strings file into a unified .xcstrings String Catalog.",
            properties: [
                "sourceStringsPath": JSONSchema(type: "string", description: "Relative path to the legacy .strings file."),
                "targetXcstringsPath": JSONSchema(type: "string", description: "Relative destination path for the .xcstrings file.")
            ],
            required: ["sourceStringsPath", "targetXcstringsPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let srcPath = input["sourceStringsPath"] as? String else {
            return .failure("Missing required parameter: sourceStringsPath")
        }
        guard let dstPath = input["targetXcstringsPath"] as? String else {
            return .failure("Missing required parameter: targetXcstringsPath")
        }

        let root = context.workspaceRoot
        let srcURL = srcPath.hasPrefix("/") ? URL(fileURLWithPath: srcPath) : root.appendingPathComponent(srcPath)
        let dstURL = dstPath.hasPrefix("/") ? URL(fileURLWithPath: dstPath) : root.appendingPathComponent(dstPath)

        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            return .failure("Source .strings file not found: \(srcPath)")
        }

        guard let content = try? String(contentsOf: srcURL, encoding: .utf8) else {
            return .failure("Unable to read .strings content at \(srcPath)")
        }

        // Parse "key" = "value";
        var stringsDict: [String: [String: Any]] = [:]
        let regex = try? NSRegularExpression(pattern: #""([^"\\]*(?:\\.[^"\\]*)*)"\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)";"#, options: [])
        let nsContent = content as NSString

        if let matches = regex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
            for match in matches {
                let key = nsContent.substring(with: match.range(at: 1))
                let val = nsContent.substring(with: match.range(at: 2))

                stringsDict[key] = [
                    "extractionState": "manual",
                    "localizations": [
                        "en": [
                            "stringUnit": [
                                "state": "translated",
                                "value": val
                            ]
                        ]
                    ]
                ]
            }
        }

        let xcstringsStructure: [String: Any] = [
            "sourceLanguage": "en",
            "strings": stringsDict,
            "version": "1.0"
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: xcstringsStructure, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dstURL)
            return .success("Successfully migrated \(stringsDict.count) localization keys from `\(srcPath)` to String Catalog `\(dstPath)`.")
        } catch {
            return .failure("Failed to write .xcstrings file: \(error.localizedDescription)")
        }
    }
}
