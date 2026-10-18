//
//  AssistColorSetBuilderTool.swift
//  SwiftCode
//

import Foundation

public struct AssistColorSetBuilderTool: AssistTool {
    public let id = "colorset_builder"
    public let name = "Color Set Builder"
    public let description = "Creates or updates adaptive Light/Dark mode colorsets in Xcode asset catalogs."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates or modifies a named .colorset in an asset catalog with adaptive light and dark hex colors.",
            properties: [
                "catalogPath": JSONSchema(type: "string", description: "Relative path to the .xcassets directory."),
                "colorName": JSONSchema(type: "string", description: "Name of the color set (e.g. BrandPrimary, SurfaceElevated)."),
                "lightHex": JSONSchema(type: "string", description: "Hex color for Any/Light mode (e.g. #007AFF, #FFFFFF)."),
                "darkHex": JSONSchema(type: "string", description: "Hex color for Dark mode (e.g. #0A84FF, #1C1C1E).")
            ],
            required: ["catalogPath", "colorName", "lightHex"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let catalogPath = input["catalogPath"] as? String else {
            return .failure("Missing required parameter: catalogPath")
        }
        guard let colorName = input["colorName"] as? String else {
            return .failure("Missing required parameter: colorName")
        }
        guard let lightHex = input["lightHex"] as? String else {
            return .failure("Missing required parameter: lightHex")
        }
        let darkHex = (input["darkHex"] as? String) ?? lightHex

        let catURL = catalogPath.hasPrefix("/") ? URL(fileURLWithPath: catalogPath) : context.workspaceRoot.appendingPathComponent(catalogPath)
        let colorSetURL = catURL.appendingPathComponent("\(colorName).colorset")

        try? FileManager.default.createDirectory(at: colorSetURL, withIntermediateDirectories: true)
        let contentsURL = colorSetURL.appendingPathComponent("Contents.json")

        func hexToRGBComponents(_ hex: String) -> (r: String, g: String, b: String, a: String) {
            var cString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if cString.hasPrefix("#") { cString.removeFirst() }
            if cString.count == 6 {
                var rgbValue: UInt64 = 0
                Scanner(string: cString).scanHexInt64(&rgbValue)
                let r = String(format: "%.3f", Double((rgbValue & 0xFF0000) >> 16) / 255.0)
                let g = String(format: "%.3f", Double((rgbValue & 0x00FF00) >> 8) / 255.0)
                let b = String(format: "%.3f", Double(rgbValue & 0x0000FF) / 255.0)
                return (r, g, b, "1.000")
            }
            return ("0.000", "0.478", "1.000", "1.000")
        }

        let (lr, lg, lb, la) = hexToRGBComponents(lightHex)
        let (dr, dg, db, da) = hexToRGBComponents(darkHex)

        let contents = """
        {
          "colors" : [
            {
              "color" : {
                "color-space" : "srgb",
                "components" : {
                  "alpha" : "\(la)",
                  "blue" : "\(lb)",
                  "green" : "\(lg)",
                  "red" : "\(lr)"
                }
              },
              "idiom" : "universal"
            },
            {
              "appearances" : [
                {
                  "appearance" : "luminosity",
                  "value" : "dark"
                }
              ],
              "color" : {
                "color-space" : "srgb",
                "components" : {
                  "alpha" : "\(da)",
                  "blue" : "\(db)",
                  "green" : "\(dg)",
                  "red" : "\(dr)"
                }
              },
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """

        do {
            try contents.write(to: contentsURL, atomically: true, encoding: .utf8)
            return .success("Successfully built adaptive ColorSet `\(colorName)` at: \(colorSetURL.path)\n- Light: \(lightHex)\n- Dark: \(darkHex)")
        } catch {
            return .failure("Failed to write colorset Contents.json: \(error.localizedDescription)")
        }
    }
}
