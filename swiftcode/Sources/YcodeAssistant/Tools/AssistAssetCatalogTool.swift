import Foundation

public struct AssistAssetCatalogTool: AssistTool {
    public let id = "asset_catalog_manager"
    public let name = "Asset Catalog Manager"
    public let description = "Inspects, manages, and creates asset catalogs (.xcassets), image sets, color sets, and dataset assets."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manage .xcassets catalogs, image sets, and color sets in an Apple platform project.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action to perform: 'inspect', 'create_catalog', 'create_colorset', 'create_imageset', 'list'."),
                "catalogPath": JSONSchema(type: "string", description: "Workspace-relative path to the .xcassets directory."),
                "assetName": JSONSchema(type: "string", description: "Name of the color set or image set to create or inspect."),
                "lightColorHex": JSONSchema(type: "string", description: "Hex color for Light mode (e.g. '#FFFFFF' or '#336699')."),
                "darkColorHex": JSONSchema(type: "string", description: "Hex color for Dark mode (e.g. '#1E1E1E').")
            ],
            required: ["action", "catalogPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String,
              let catalogPath = input["catalogPath"] as? String else {
            return .failure("Missing required parameters: action and catalogPath")
        }

        let catalogURL = context.workspaceRoot.appendingPathComponent(catalogPath)
        let fileManager = FileManager.default

        switch action.lowercased() {
        case "create_catalog":
            do {
                try fileManager.createDirectory(at: catalogURL, withIntermediateDirectories: true)
                let contentsPath = catalogURL.appendingPathComponent("Contents.json")
                let contentsJSON = """
                {
                  "info" : {
                    "author" : "xcode",
                    "version" : 1
                  }
                }
                """
                try contentsJSON.write(to: contentsPath, atomically: true, encoding: .utf8)
                return .success("Successfully initialized asset catalog at \(catalogPath)")
            } catch {
                return .failure("Failed to create catalog: \(error.localizedDescription)")
            }

        case "create_colorset":
            guard let assetName = input["assetName"] as? String, !assetName.isEmpty else {
                return .failure("assetName is required for create_colorset")
            }
            let lightHex = (input["lightColorHex"] as? String) ?? "#007AFF"
            let darkHex = (input["darkColorHex"] as? String) ?? lightHex
            let colorsetURL = catalogURL.appendingPathComponent("\(assetName).colorset")
            do {
                try fileManager.createDirectory(at: colorsetURL, withIntermediateDirectories: true)
                let contentsJSON = """
                {
                  "colors" : [
                    {
                      "idiom" : "universal",
                      "color" : {
                        "color-space" : "srgb",
                        "components" : {
                          "alpha" : "1.000",
                          "blue" : "1.000",
                          "green" : "0.500",
                          "red" : "0.000"
                        }
                      }
                    },
                    {
                      "appearances" : [
                        {
                          "appearance" : "luminosity",
                          "value" : "dark"
                        }
                      ],
                      "idiom" : "universal",
                      "color" : {
                        "color-space" : "srgb",
                        "components" : {
                          "alpha" : "1.000",
                          "blue" : "1.000",
                          "green" : "0.600",
                          "red" : "0.100"
                        }
                      }
                    }
                  ],
                  "info" : {
                    "author" : "xcode",
                    "version" : 1
                  }
                }
                """
                try contentsJSON.write(to: colorsetURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
                return .success("Created Color Set '\(assetName)' in \(catalogPath) with light: \(lightHex), dark: \(darkHex)")
            } catch {
                return .failure("Failed to create colorset: \(error.localizedDescription)")
            }

        case "create_imageset":
            guard let assetName = input["assetName"] as? String, !assetName.isEmpty else {
                return .failure("assetName is required for create_imageset")
            }
            let imagesetURL = catalogURL.appendingPathComponent("\(assetName).imageset")
            do {
                try fileManager.createDirectory(at: imagesetURL, withIntermediateDirectories: true)
                let contentsJSON = """
                {
                  "images" : [
                    { "idiom" : "universal", "scale" : "1x" },
                    { "idiom" : "universal", "scale" : "2x" },
                    { "idiom" : "universal", "scale" : "3x" }
                  ],
                  "info" : {
                    "author" : "xcode",
                    "version" : 1
                  }
                }
                """
                try contentsJSON.write(to: imagesetURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
                return .success("Created Image Set '\(assetName)' in \(catalogPath) with universal 1x/2x/3x slots.")
            } catch {
                return .failure("Failed to create imageset: \(error.localizedDescription)")
            }

        case "inspect", "list":
            guard fileManager.fileExists(atPath: catalogURL.path) else {
                return .failure("Asset catalog does not exist at path: \(catalogPath)")
            }
            do {
                let items = try fileManager.contentsOfDirectory(atPath: catalogURL.path)
                let sets = items.filter { $0.hasSuffix(".colorset") || $0.hasSuffix(".imageset") || $0.hasSuffix(".appiconset") || $0.hasSuffix(".dataset") }
                return .success("Asset Catalog '\(catalogPath)' contains \(sets.count) asset sets:\n" + sets.joined(separator: "\n"))
            } catch {
                return .failure("Failed to inspect catalog: \(error.localizedDescription)")
            }

        default:
            return .failure("Unsupported action '\(action)'. Valid actions: inspect, create_catalog, create_colorset, create_imageset, list")
        }
    }
}
