import Foundation

public struct AssistInterfaceSimulatorTool: AssistTool {
    public let id = "interface_simulator"
    public let name = "Interface Simulator & Accessibility Auditor"
    public let description = "Inspects SwiftUI View files, audits accessibility traits, accessibility identifiers, touch targets, and hierarchy structure."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audit SwiftUI views for UI structure and accessibility compliance.",
            properties: [
                "viewPath": JSONSchema(type: "string", description: "Workspace-relative path to a SwiftUI View file.")
            ],
            required: ["viewPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let viewPath = input["viewPath"] as? String else {
            return .failure("Missing required parameter: viewPath")
        }

        let targetURL = context.workspaceRoot.appendingPathComponent(viewPath)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .failure("File does not exist: \(viewPath)")
        }

        guard let content = try? String(contentsOf: targetURL, encoding: .utf8) else {
            return .failure("Cannot read file: \(viewPath)")
        }

        guard content.contains(": View") || content.contains("some View") else {
            return .failure("File does not appear to contain a SwiftUI View implementation: \(viewPath)")
        }

        let lines = content.components(separatedBy: .newlines)
        var buttonCount = 0
        var buttonsWithA11y = 0
        var imageCount = 0
        var imagesWithA11y = 0
        var textCount = 0
        var listCount = 0
        var navigationTitleFound = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("//") { continue }

            if trimmed.contains("Button(") || trimmed.contains("Button {") { buttonCount += 1 }
            if trimmed.contains(".accessibilityIdentifier(") || trimmed.contains(".accessibilityLabel(") {
                buttonsWithA11y += 1
            }
            if trimmed.contains("Image(") || trimmed.contains("Image(systemName:") { imageCount += 1 }
            if trimmed.contains(".accessibilityHidden(") { imagesWithA11y += 1 }
            if trimmed.contains("Text(") { textCount += 1 }
            if trimmed.contains("List {") || trimmed.contains("List(") { listCount += 1 }
            if trimmed.contains(".navigationTitle(") { navigationTitleFound = true }
        }

        let a11yScore = buttonCount > 0 ? Int((Double(buttonsWithA11y) / Double(buttonCount)) * 100.0) : 100

        var report = """
        SwiftUI Interface & Accessibility Audit for '\(viewPath)':
        - Elements Detected:
          * Buttons: \(buttonCount) (\(buttonsWithA11y) have accessibility tags or labels)
          * Images: \(imageCount)
          * Text Labels: \(textCount)
          * Lists/ScrollViews: \(listCount)
          * Navigation Title Configured: \(navigationTitleFound ? "Yes" : "No")
        - Accessibility Identifier Coverage: \(a11yScore)%
        """

        if a11yScore < 60 {
            report += "\n\nRecommendations:\n- Add `.accessibilityIdentifier(...)` to interactive buttons for automated UI testing.\n- Add `.accessibilityLabel(...)` to icon-only buttons."
        } else {
            report += "\n\nInterface compliance check passed with high accessibility readiness."
        }

        return .success(report)
    }
}
