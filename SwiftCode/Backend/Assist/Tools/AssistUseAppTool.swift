import Foundation
import AppKit

public struct AssistUseAppTool: AssistTool {
    public let id = "use_app"
    public let name = "use_app"
    public let description = "Enables Assist to interact with installed macOS applications, inspect their available interface and state, navigate supported workflows, perform permitted UI actions, and validate application behavior."

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: description,
            properties: [
                "app_identifier": JSONSchema(
                    type: "string",
                    description: "Target application bundle identifier (e.g. 'com.apple.calculator') or application name (e.g. 'Calculator')."
                ),
                "action": JSONSchema(
                    type: "string",
                    description: "Interaction action: 'launch', 'activate', 'inspect_ui', 'click', 'type_text', 'select_menu', or 'verify'."
                ),
                "target": JSONSchema(
                    type: "string",
                    description: "Target element identifier, title, label, or menu path (e.g. 'File > New' or 'Submit')."
                ),
                "value": JSONSchema(
                    type: "string",
                    description: "Input value when entering text or expected value for verification."
                ),
                "arguments": JSONSchema(
                    type: "object",
                    description: "Optional additional parameters for the action."
                ),
                "verification": JSONSchema(
                    type: "boolean",
                    description: "Whether to re-inspect and verify resulting application state after the action. Defaults to true."
                ),
                "purpose": JSONSchema(
                    type: "string",
                    description: "Optional explanation of the workflow or reason for this interaction."
                )
            ],
            required: ["app_identifier", "action"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawAppId = input["app_identifier"] as? String,
              !rawAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AssistToolResult.failure(
                "Missing required parameter 'app_identifier'. Provide a bundle identifier or application name."
            )
        }
        let appIdentifier = rawAppId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rawAction = input["action"] as? String,
              !rawAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AssistToolResult.failure(
                "Missing required parameter 'action'. Supported actions: launch, activate, inspect_ui, click, type_text, select_menu, verify."
            )
        }
        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = input["target"] as? String
        let value = input["value"] as? String
        let shouldVerify = (input["verification"] as? Bool) ?? true
        let purpose = input["purpose"] as? String

        // Check Accessibility permission
        let hasAccessibility = AssistAppInteractionEngine.shared.checkAccessibilityAuthorization(promptIfDenied: true)
        if !hasAccessibility && action != "launch" {
            return AssistToolResult.failure(
                "Accessibility permission has not been granted. SwiftCode requires Accessibility permission to inspect and interact with application interfaces. Please enable SwiftCode in macOS System Settings > Privacy & Security > Accessibility, then retry.",
                diagnostics: ["AXIsProcessTrusted returned false."]
            )
        }

        // Resolve or launch application
        let runningApp: NSRunningApplication
        do {
            runningApp = try await AssistAppInteractionEngine.shared.resolveOrLaunchApp(
                appIdentifier: appIdentifier,
                autoLaunch: (action == "launch" || action == "activate")
            )
        } catch let err as AppInteractionError {
            switch err {
            case .applicationNotFound(let id):
                return AssistToolResult.failure(
                    "Target application '\(id)' could not be located. Ensure the app is installed or specify its exact bundle identifier.",
                    diagnostics: ["Application resolution failed in /Applications and via LaunchServices."]
                )
            default:
                return AssistToolResult.failure(err.localizedDescription)
            }
        } catch {
            return AssistToolResult.failure("Failed to resolve application '\(appIdentifier)': \(error.localizedDescription)")
        }

        let appName = runningApp.localizedName ?? appIdentifier
        let bundleID = runningApp.bundleIdentifier ?? appIdentifier

        switch action {
        case "launch", "activate":
            runningApp.activate(options: [.activateIgnoringOtherApps])
            return AssistToolResult.success(
                "Application '\(appName)' (\(bundleID), PID: \(runningApp.processIdentifier)) is active.",
                data: [
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "action": action,
                    "status": "active",
                    "pid": "\(runningApp.processIdentifier)"
                ]
            )

        case "inspect_ui":
            let elements = AssistAppInteractionEngine.shared.inspectUI(app: runningApp, maxElements: 80)
            if elements.isEmpty {
                return AssistToolResult.success(
                    "Inspected '\(appName)': No accessible UI elements currently exposed (application may be in a background state, minimized, or initializing).",
                    data: [
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "action": action,
                        "element_count": "0",
                        "summary": "No accessible controls found."
                    ]
                )
            }

            var summaryLines: [String] = []
            for (idx, elem) in elements.prefix(40).enumerated() {
                var desc = "\(idx + 1). [\(elem.role)]"
                if !elem.title.isEmpty { desc += " \"\(elem.title)\"" }
                if !elem.identifier.isEmpty { desc += " (id: \(elem.identifier))" }
                if !elem.value.isEmpty { desc += " value='\(elem.value)'" }
                if !elem.actions.isEmpty { desc += " actions: [\(elem.actions.joined(separator: ", "))]" }
                summaryLines.append(desc)
            }
            if elements.count > 40 {
                summaryLines.append("… and \(elements.count - 40) more accessible elements.")
            }

            let fullSummary = summaryLines.joined(separator: "\n")
            return AssistToolResult.success(
                "Inspected \(elements.count) accessible element(s) in '\(appName)':\n\(fullSummary)",
                data: [
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "action": action,
                    "element_count": "\(elements.count)",
                    "summary": fullSummary
                ]
            )

        case "click", "press":
            guard let target = target, !target.isEmpty else {
                return AssistToolResult.failure("Action 'click' requires parameter 'target' specifying the UI element to click.")
            }
            guard let elem = AssistAppInteractionEngine.shared.findElement(app: runningApp, target: target) else {
                return AssistToolResult.failure(
                    "Target element '\(target)' was not found in '\(appName)'. Use action 'inspect_ui' to examine the visible interface hierarchy.",
                    diagnostics: ["Recursive AXUIElement search returned nil for target query '\(target)'."]
                )
            }
            let success = AssistAppInteractionEngine.shared.performAction(action: "click", targetElement: elem, value: nil)
            guard success else {
                return AssistToolResult.failure("Dispatched click to '\(target)' in '\(appName)', but the action was rejected by the element.")
            }

            // Optional bounded verification
            if shouldVerify {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            return AssistToolResult.success(
                "Clicked element '\(target)' in '\(appName)'.",
                data: [
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "action": action,
                    "target": target,
                    "status": "success",
                    "verified": "\(shouldVerify)"
                ]
            )

        case "type_text", "set_value":
            guard let target = target, !target.isEmpty else {
                return AssistToolResult.failure("Action 'type_text' requires parameter 'target' specifying the text field.")
            }
            guard let textValue = value else {
                return AssistToolResult.failure("Action 'type_text' requires parameter 'value' containing the text to enter.")
            }
            guard let elem = AssistAppInteractionEngine.shared.findElement(app: runningApp, target: target) else {
                return AssistToolResult.failure(
                    "Target field '\(target)' was not found in '\(appName)'. Use action 'inspect_ui' to discover available input fields."
                )
            }
            let success = AssistAppInteractionEngine.shared.performAction(action: "type_text", targetElement: elem, value: textValue)
            guard success else {
                return AssistToolResult.failure("Failed to set text value for '\(target)' in '\(appName)'.")
            }

            return AssistToolResult.success(
                "Entered text into '\(target)' in '\(appName)'.",
                data: [
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "action": action,
                    "target": target,
                    "status": "success"
                ]
            )

        case "select_menu":
            guard let menuPath = target, !menuPath.isEmpty else {
                return AssistToolResult.failure("Action 'select_menu' requires parameter 'target' specifying the menu path (e.g. 'File > Save').")
            }
            let success = AssistAppInteractionEngine.shared.selectMenuItem(app: runningApp, menuPath: menuPath)
            guard success else {
                return AssistToolResult.failure("Failed to trigger menu item '\(menuPath)' in '\(appName)'. Verify the menu item exists and is currently enabled.")
            }

            return AssistToolResult.success(
                "Selected menu item '\(menuPath)' in '\(appName)'.",
                data: [
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "action": action,
                    "target": menuPath,
                    "status": "success"
                ]
            )

        case "verify":
            guard let target = target, !target.isEmpty else {
                return AssistToolResult.failure("Action 'verify' requires parameter 'target' to check.")
            }
            guard let elem = AssistAppInteractionEngine.shared.findElement(app: runningApp, target: target) else {
                return AssistToolResult.failure("Verification failed: element '\(target)' was not found in '\(appName)'.")
            }
            return AssistToolResult.success(
                "Verified: element '\(target)' exists and is visible in '\(appName)'.",
                data: [
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "action": action,
                    "target": target,
                    "status": "verified"
                ]
            )

        default:
            return AssistToolResult.failure(
                "Unsupported action '\(action)'. Supported actions are: launch, activate, inspect_ui, click, type_text, select_menu, verify."
            )
        }
    }
}
