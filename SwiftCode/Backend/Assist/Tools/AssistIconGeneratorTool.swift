//
//  AssistIconGeneratorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistIconGeneratorTool: AssistTool {
    public let id = "icon_generator_tool"
    public let name = "App Icon Generator & Validator"
    public let description = "Validates, configures, or scaffolds complete AppIcon.appiconset specifications in asset catalogs."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits or scaffolds an AppIcon.appiconset with compliant Apple platform slots (macOS, iOS, iPad).",
            properties: [
                "catalogPath": JSONSchema(type: "string", description: "Relative path to the .xcassets directory."),
                "action": JSONSchema(type: "string", description: "Action: 'validate' or 'scaffold'.")
            ],
            required: ["catalogPath", "action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let catalogPath = input["catalogPath"] as? String else {
            return .failure("Missing required parameter: catalogPath")
        }
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action ('validate' or 'scaffold')")
        }

        let catURL = catalogPath.hasPrefix("/") ? URL(fileURLWithPath: catalogPath) : context.workspaceRoot.appendingPathComponent(catalogPath)
        let iconSetURL = catURL.appendingPathComponent("AppIcon.appiconset")

        if action.lowercased() == "scaffold" {
            try? FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)
            let contentsJSON = iconSetURL.appendingPathComponent("Contents.json")

            let template = """
            {
              "images" : [
                {
                  "idiom" : "universal",
                  "platform" : "ios",
                  "size" : "1024x1024"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "16x16"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "16x16"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "32x32"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "32x32"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "128x128"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "128x128"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "256x256"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "256x256"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "512x512"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "512x512"
                }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }
            """
            do {
                try template.write(to: contentsJSON, atomically: true, encoding: .utf8)
                return .success("Successfully created universal AppIcon.appiconset at: \(iconSetURL.path)")
            } catch {
                return .failure("Failed to write AppIcon Contents.json: \(error.localizedDescription)")
            }
        }

        // Action: validate
        let contentsJSON = iconSetURL.appendingPathComponent("Contents.json")
        guard FileManager.default.fileExists(atPath: contentsJSON.path),
              let data = try? Data(contentsOf: contentsJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]] else {
            return .failure("Contents.json not found or invalid in \(iconSetURL.path)")
        }

        var filledSlots = 0
        var emptySlots = 0
        for img in images {
            if let fn = img["filename"] as? String, !fn.isEmpty {
                let imgURL = iconSetURL.appendingPathComponent(fn)
                if FileManager.default.fileExists(atPath: imgURL.path) {
                    filledSlots += 1
                } else {
                    emptySlots += 1
                }
            } else {
                emptySlots += 1
            }
        }

        return .success("AppIcon.appiconset audit for `\(catalogPath)`:\n- Total slots configured: \(images.count)\n- Rendered assets present: \(filledSlots)\n- Empty/unassigned slots: \(emptySlots)")
    }
}
