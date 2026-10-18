//
//  AssistCoreDataModelInspectorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistCoreDataModelInspectorTool: AssistTool {
    public let id = "core_data_model_inspector"
    public let name = "Core Data Model Inspector"
    public let description = "Locates, inspects, and parses Core Data .xcdatamodeld schemas, entities, attributes, and relationships."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Inspects Core Data data models (.xcdatamodeld) in the workspace.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional path to the .xcdatamodeld bundle. If omitted, the workspace is scanned.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let customPath = input["path"] as? String
        let root = context.workspaceRoot

        var modelDirURL: URL?
        if let p = customPath, !p.isEmpty {
            modelDirURL = p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
        } else {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = enumerator?.nextObject() as? URL {
                if u.pathExtension == "xcdatamodeld" {
                    modelDirURL = u
                    break
                }
            }
        }

        guard let modelURL = modelDirURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            return .success("No .xcdatamodeld Core Data models found in the workspace.")
        }

        // Find contents file inside the current version
        var contentsURL: URL?
        if let subitems = try? FileManager.default.contentsOfDirectory(at: modelURL, includingPropertiesForKeys: nil) {
            for sub in subitems {
                if sub.pathExtension == "xcdatamodel" {
                    let c = sub.appendingPathComponent("contents")
                    if FileManager.default.fileExists(atPath: c.path) {
                        contentsURL = c
                        break
                    }
                }
            }
        }

        guard let contents = contentsURL, let xmlString = try? String(contentsOf: contents, encoding: .utf8) else {
            return .success("Found model at \(modelURL.lastPathComponent), but contents XML was unreadable.")
        }

        // Simple XML attribute and entity parsing
        var entities: [String: [String]] = [:]
        let entityRegex = try? NSRegularExpression(pattern: #"<entity name="([^"]+)""#, options: [])
        let attributeRegex = try? NSRegularExpression(pattern: #"<attribute name="([^"]+)"[^>]*attributeType="([^"]+)""#, options: [])

        let nsXml = xmlString as NSString
        var currentEntity = "Entity"

        for line in xmlString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let eMatch = entityRegex?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                currentEntity = (trimmed as NSString).substring(with: eMatch.range(at: 1))
                entities[currentEntity] = []
            } else if let aMatch = attributeRegex?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                let attrName = (trimmed as NSString).substring(with: aMatch.range(at: 1))
                let attrType = (trimmed as NSString).substring(with: aMatch.range(at: 2))
                entities[currentEntity, default: []].append("\(attrName): \(attrType)")
            }
        }

        var report = "### Core Data Model: `\(modelURL.lastPathComponent)` (\(entities.count) entities):\n\n"
        for (name, attrs) in entities {
            report += "#### Entity `\(name)`:\n"
            if attrs.isEmpty {
                report += "  _(No attributes defined or managed via relationships)_\n"
            } else {
                for a in attrs {
                    report += "  - `\(a)`\n"
                }
            }
            report += "\n"
        }

        return .success(report)
    }
}
