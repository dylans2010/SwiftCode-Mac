import Foundation

@MainActor
public final class AssistCreateNewAppTool: AssistTool {
    public let id = "create_new_app"
    public let name = "create_new_app"
    public let description = "Creates a new native application project from user specifications or autonomous request parameters."

    public var capability: ToolCapability {
        .projectManagement
    }

    public var riskLevel: ToolRiskLevel {
        .safeMutation
    }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: description,
            properties: [
                "appName": JSONSchema(
                    type: "string",
                    description: "Display name of the application (e.g. My Notes)."
                ),
                "bundleIdentifier": JSONSchema(
                    type: "string",
                    description: "Reverse domain bundle identifier (e.g. com.example.mynotes)."
                ),
                "version": JSONSchema(
                    type: "string",
                    description: "Marketing version number (e.g. 1.0)."
                ),
                "build": JSONSchema(
                    type: "string",
                    description: "Build number (e.g. 1)."
                ),
                "platform": JSONSchema(
                    type: "string",
                    description: "Target platform: macOS, iOS, iPadOS, watchOS, or visionOS."
                ),
                "projectLocation": JSONSchema(
                    type: "string",
                    description: "Absolute file URL path where the project directory should be generated."
                ),
                "applicationDescription": JSONSchema(
                    type: "string",
                    description: "Natural language description or feature specification of the application."
                ),
                "uiPreferences": JSONSchema(
                    type: "object",
                    description: "UI and UX preferences (style, layout, theme, accessibility, persistence)."
                ),
                "architecturePreferences": JSONSchema(
                    type: "string",
                    description: "Preferred software architecture pattern (e.g. MVVM, TCA, Observable Stores)."
                ),
                "additionalRequirements": JSONSchema(
                    type: "string",
                    description: "Any extra technical requirements or constraints."
                ),
                "overwriteExistingMetadata": JSONSchema(
                    type: "boolean",
                    description: "Whether to overwrite existing project metadata if an active project exists."
                )
            ],
            required: ["appName", "applicationDescription"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let appName = input["appName"] as? String ?? "NewApp"
        let applicationDescription = input["applicationDescription"] as? String ?? "A modern Swift application."
        let platform = input["platform"] as? String ?? "macOS"
        let version = input["version"] as? String ?? "1.0"
        let build = input["build"] as? String ?? "1"
        let rawBundle = input["bundleIdentifier"] as? String ?? ""
        let safeName = appName.replacingOccurrences(of: " ", with: "")
        let bundleIdentifier = rawBundle.isEmpty ? "com.swiftcode.\(safeName.lowercased())" : rawBundle

        let targetDirURL: URL
        if let locationStr = input["projectLocation"] as? String, !locationStr.isEmpty {
            targetDirURL = URL(fileURLWithPath: locationStr)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
            targetDirURL = documents.appendingPathComponent(appName)
        }

        do {
            try FileManager.default.createDirectory(at: targetDirURL, withIntermediateDirectories: true)
        } catch {
            return AssistToolResult(
                toolId: id,
                success: false,
                output: "Failed to create target project directory at \(targetDirURL.path): \(error.localizedDescription)"
            )
        }

        // Apply starter template based on platform
        let template = selectTemplate(for: platform)
        let newProject = Project(
            id: UUID(),
            name: appName,
            directoryURL: targetDirURL,
            creationDate: Date(),
            lastModifiedDate: Date()
        )

        do {
            try ProjectTemplateManager.shared.applyTemplate(template, to: newProject)
        } catch {
            return AssistToolResult(
                toolId: id,
                success: false,
                output: "Failed to scaffold template for \(appName): \(error.localizedDescription)"
            )
        }

        // Open newly created project into active session
        ProjectSessionStore.shared.openProject(at: targetDirURL)

        // Inject initial project.json metadata if needed
        let metadataDict: [String: Any] = [
            "name": appName,
            "bundleIdentifier": bundleIdentifier,
            "version": version,
            "build": build,
            "platform": platform,
            "description": applicationDescription
        ]

        if let metadataData = try? JSONSerialization.data(withJSONObject: metadataDict, options: .prettyPrinted) {
            let metaURL = targetDirURL.appendingPathComponent("project.json")
            try? metadataData.write(to: metaURL)
        }

        return AssistToolResult(
            toolId: id,
            success: true,
            output: """
            Successfully initialized Create New App workflow for '\(appName)'.
            Target Directory: \(targetDirURL.path)
            Bundle Identifier: \(bundleIdentifier)
            Platform: \(platform)
            Version: \(version) (\(build))
            Initial scaffolding applied using standard Swift package structure.
            Ready for autonomous implementation and iteration.
            """
        )
    }

    private func selectTemplate(for platform: String) -> ProjectTemplate {
        let templates = ProjectTemplateManager.shared.templates
        switch platform.lowercased() {
        case "ios", "ipados":
            return templates.first(where: { $0.id == "swiftui_app" }) ?? templates[0]
        case "watchos":
            return templates.first(where: { $0.id == "watch_app" }) ?? templates[0]
        case "visionos":
            return templates.first(where: { $0.id == "visionos_app" }) ?? templates[0]
        default:
            return templates.first(where: { $0.id == "swiftui_app" }) ?? templates[0]
        }
    }
}
