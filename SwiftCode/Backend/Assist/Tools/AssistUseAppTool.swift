import Foundation
import AppKit

public struct AssistUseAppTool: AssistTool {
    public let id = "use_app"
    public let name = "use_app"
    public let description = "Enables Assist to operate native macOS applications through real Accessibility APIs, CoreGraphics synthetic events, ScreenCaptureKit visual perception, and window management."

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: description,
            properties: [
                "app_identifier": JSONSchema(
                    type: "string",
                    description: "Target application bundle identifier (e.g. 'com.apple.finder'), app name (e.g. 'Finder', 'Calculator'), process ID, or session ID."
                ),
                "action": JSONSchema(
                    type: "string",
                    description: "Action to perform: 'launch', 'activate', 'list_applications', 'inspect_application', 'list_windows', 'select_window', 'close_application', 'inspect_ui', 'get_accessibility_tree', 'get_focused_element', 'take_screenshot', 'inspect_window', 'click', 'double_click', 'right_click', 'move_pointer', 'drag', 'scroll', 'type_text', 'press_key', 'press_shortcut', 'select_all', 'copy', 'paste', 'activate_element', 'set_element_value', 'select_menu', 'wait_for_element', 'wait_for_window', 'verify'."
                ),
                "target": JSONSchema(
                    type: "string",
                    description: "Target UI element session ID (e.g. 'elem_1'), title, accessibility identifier, label, or menu path (e.g. 'File > Save')."
                ),
                "value": JSONSchema(
                    type: "string",
                    description: "Text input to type, shortcut name (e.g. 'Cmd+S'), key name (e.g. 'Return'), or expected value for verification."
                ),
                "coordinates": JSONSchema(
                    type: "object",
                    description: "Optional point coordinates for pointer interactions (e.g. {\"x\": 150, \"y\": 220}).",
                    properties: [
                        "x": JSONSchema(type: "number", description: "X coordinate."),
                        "y": JSONSchema(type: "number", description: "Y coordinate."),
                        "coordinate_space": JSONSchema(type: "string", description: "Coordinate space: 'screen', 'window', or 'screenshot_pixel'. Defaults to 'screen'.")
                    ]
                ),
                "drag_destination": JSONSchema(
                    type: "object",
                    description: "Destination point for drag actions (e.g. {\"x\": 300, \"y\": 400}).",
                    properties: [
                        "x": JSONSchema(type: "number", description: "Destination X coordinate."),
                        "y": JSONSchema(type: "number", description: "Destination Y coordinate.")
                    ]
                ),
                "scroll_delta": JSONSchema(
                    type: "object",
                    description: "Pixel deltas for scroll action (e.g. {\"dy\": -100, \"dx\": 0}).",
                    properties: [
                        "dx": JSONSchema(type: "integer", description: "Horizontal scroll delta in pixels."),
                        "dy": JSONSchema(type: "integer", description: "Vertical scroll delta in pixels.")
                    ]
                ),
                "window_id": JSONSchema(
                    type: "string",
                    description: "Optional target window identifier (e.g. 'window_1')."
                ),
                "modifiers": JSONSchema(
                    type: "array",
                    description: "Optional key modifier list (e.g. ['command', 'shift']).",
                    items: JSONSchema(type: "string")
                ),
                "timeout": JSONSchema(
                    type: "number",
                    description: "Timeout in seconds for wait operations (1-60, default 5)."
                ),
                "verification": JSONSchema(
                    type: "boolean",
                    description: "Whether to re-inspect and verify resulting application state after action. Defaults to true."
                ),
                "confirm": JSONSchema(
                    type: "boolean",
                    description: "Explicit user authorization required for consequential actions such as 'close_application'."
                ),
                "purpose": JSONSchema(
                    type: "string",
                    description: "Natural-language explanation of the intended workflow or interaction purpose."
                )
            ],
            required: ["app_identifier", "action"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawAction = input["action"] as? String,
              !rawAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AssistToolResult.failure(
                "Missing required parameter 'action'. Call use_app with an action type.",
                code: .missingArgument
            )
        }
        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Handle list_applications early (does not require a running app_identifier)
        if action == "list_applications" {
            let filter = (input["target"] as? String) ?? (input["app_identifier"] as? String)
            let apps = AssistAppInteractionEngine.shared.listApplications(filter: filter)
            var lines = ["Discovered \(apps.count) application(s):"]
            for (idx, a) in apps.prefix(35).enumerated() {
                let status = a.isRunning ? "RUNNING (PID: \(a.pid ?? 0))" : "INSTALLED"
                lines.append("\(idx + 1). \(a.name) [\(status)] — id: '\(a.bundleIdentifier)'")
            }
            if apps.count > 35 {
                lines.append("… and \(apps.count - 35) more applications.")
            }
            return AssistToolResult.success(
                lines.joined(separator: "\n"),
                data: [
                    "action": action,
                    "count": "\(apps.count)",
                    "status": "success"
                ]
            )
        }

        guard let rawAppId = input["app_identifier"] as? String,
              !rawAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AssistToolResult.failure(
                "Missing required parameter 'app_identifier'. Provide an application bundle identifier or app name.",
                code: .missingArgument
            )
        }
        let appIdentifier = rawAppId.trimmingCharacters(in: .whitespacesAndNewlines)

        let target = input["target"] as? String
        let value = input["value"] as? String
        let windowId = input["window_id"] as? String
        let shouldVerify = (input["verification"] as? Bool) ?? true
        let confirm = (input["confirm"] as? Bool) ?? false
        let timeoutSeconds = min(max((input["timeout"] as? Double) ?? 5.0, 1.0), 60.0)

        // Preflight accessibility permission
        let hasAccessibility = AssistAppInteractionEngine.shared.checkAccessibilityAuthorization(promptIfDenied: true)
        if !hasAccessibility && action != "launch" && action != "activate" {
            return AssistToolResult.failure(
                "Accessibility permission has not been granted. SwiftCode requires Accessibility permission to inspect and operate application interfaces. Please enable SwiftCode in macOS System Settings > Privacy & Security > Accessibility, then retry.",
                code: .permissionDenied,
                diagnostics: ["AXIsProcessTrustedWithOptions returned false."]
            )
        }

        // Consequential action safeguard
        if action == "close_application" && !confirm {
            return AssistToolResult.failure(
                "Closing application '\(appIdentifier)' is a consequential action that will terminate running processes and unsaved user state. Pass 'confirm: true' to authorize.",
                code: .permissionDenied
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
            return AssistToolResult.failure(
                err.localizedDescription,
                code: err.assistErrorCode,
                diagnostics: [err.recoveryHint]
            )
        } catch {
            return AssistToolResult.failure(
                "Failed to resolve application '\(appIdentifier)': \(error.localizedDescription)",
                code: .executionFailed
            )
        }

        let appName = runningApp.localizedName ?? appIdentifier
        let bundleID = runningApp.bundleIdentifier ?? appIdentifier
        let pidStr = "\(runningApp.processIdentifier)"
        let session = AssistAppSessionManager.shared.getOrCreateSession(for: runningApp)

        switch action {
        case "launch", "activate", "activate_application", "launch_application":
            runningApp.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 100_000_000)
            let windows = AssistAppInteractionEngine.shared.listWindows(for: runningApp)
            session.windows = windows
            let winCount = windows.count
            return AssistToolResult.success(
                "Application '\(appName)' (\(bundleID), PID: \(pidStr)) is active with \(winCount) window(s).",
                data: [
                    "action": action,
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "pid": pidStr,
                    "session_id": session.sessionId,
                    "window_count": "\(winCount)",
                    "status": "active"
                ]
            )

        case "close_application":
            let terminated = runningApp.terminate()
            AssistAppSessionManager.shared.terminateSession(id: session.sessionId)
            return AssistToolResult.success(
                "Closed application '\(appName)' (\(bundleID), PID: \(pidStr)). Terminate signal dispatched: \(terminated).",
                data: [
                    "action": action,
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "status": "terminated"
                ]
            )

        case "list_windows":
            let windows = AssistAppInteractionEngine.shared.listWindows(for: runningApp)
            session.windows = windows
            if windows.isEmpty {
                return AssistToolResult.success(
                    "No accessible windows currently open for '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "window_count": "0"
                    ]
                )
            }
            var lines = ["Open window(s) for '\(appName)':"]
            for win in windows {
                let mainMark = win.isMain ? " [MAIN]" : ""
                let minMark = win.isMinimized ? " [MINIMIZED]" : ""
                lines.append("- \(win.id): \"\(win.title)\"\(mainMark)\(minMark) @(\(Int(win.frame.x)),\(Int(win.frame.y)) \(Int(win.frame.width))x\(Int(win.frame.height)))")
            }
            return AssistToolResult.success(
                lines.joined(separator: "\n"),
                data: [
                    "action": action,
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "window_count": "\(windows.count)",
                    "status": "success"
                ]
            )

        case "select_window":
            guard let targetWin = windowId ?? target, !targetWin.isEmpty else {
                return AssistToolResult.failure(
                    "Action 'select_window' requires parameter 'window_id' or 'target' specifying the window to select.",
                    code: .missingArgument
                )
            }
            do {
                let selected = try AssistAppInteractionEngine.shared.selectWindow(app: runningApp, windowId: targetWin)
                return AssistToolResult.success(
                    "Selected and focused window '\(selected.id)' (\"\(selected.title)\") in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "window_id": selected.id,
                        "window_title": selected.title,
                        "status": "focused"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Failed to select window: \(error.localizedDescription)", code: .executionFailed)
            }

        case "inspect_ui", "get_accessibility_tree":
            let (elements, updatedSession) = AssistAppInteractionEngine.shared.inspectUI(
                app: runningApp,
                maxElements: 100,
                targetWindowId: windowId
            )
            if elements.isEmpty {
                return AssistToolResult.success(
                    "Inspected '\(appName)': No accessible UI elements currently exposed. The app may be minimized, hidden, or rendering custom graphics.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "session_id": updatedSession.sessionId,
                        "element_count": "0"
                    ]
                )
            }
            var lines = ["Accessible controls in '\(appName)' (Session: \(updatedSession.sessionId)):"]
            for elem in elements.prefix(40) {
                lines.append("\(elem.id). \(elem.displayDescription)")
            }
            if elements.count > 40 {
                lines.append("… and \(elements.count - 40) more elements. Target elements by their exact ID (e.g. 'elem_3').")
            }
            return AssistToolResult.success(
                lines.joined(separator: "\n"),
                data: [
                    "action": action,
                    "app_identifier": bundleID,
                    "app_name": appName,
                    "session_id": updatedSession.sessionId,
                    "element_count": "\(elements.count)",
                    "status": "success"
                ]
            )

        case "get_focused_element":
            let (elements, _) = AssistAppInteractionEngine.shared.inspectUI(app: runningApp, maxElements: 100)
            if let focused = elements.first(where: { $0.isFocused }) {
                return AssistToolResult.success(
                    "Focused element in '\(appName)': \(focused.displayDescription)",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "target": focused.id,
                        "element_role": focused.role,
                        "value": focused.value,
                        "status": "focused"
                    ]
                )
            } else {
                return AssistToolResult.success(
                    "No element currently reports active focus in '\(appName)'.",
                    data: ["action": action, "app_identifier": bundleID, "status": "none"]
                )
            }

        case "take_screenshot":
            do {
                let capture = try await AssistAppInteractionEngine.shared.captureAppScreenshot(
                    app: runningApp,
                    windowId: windowId,
                    context: context
                )
                return AssistToolResult.success(
                    "Captured screenshot for '\(appName)' window bounds (\(Int(capture.rect.width))x\(Int(capture.rect.height))). Saved to '\(capture.artifactPath)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "artifact_path": capture.artifactPath,
                        "base64": capture.base64,
                        "width": "\(Int(capture.rect.width))",
                        "height": "\(Int(capture.rect.height))",
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Screenshot failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "click", "press":
            let coords = parseCoordinates(from: input["coordinates"])
            let coordSpace = (input["coordinates"] as? [String: Any])?["coordinate_space"] as? String ?? "screen"
            do {
                let res = try await AssistAppInteractionEngine.shared.click(
                    app: runningApp,
                    target: target,
                    coordinates: coords,
                    coordinateSpace: coordSpace,
                    button: "left",
                    clickCount: 1,
                    shouldVerify: shouldVerify
                )
                let tgtDesc = target ?? "@(\(Int(res.clickedPoint.x)),\(Int(res.clickedPoint.y)))"
                return AssistToolResult.success(
                    "Clicked '\(tgtDesc)' in '\(appName)' (verified: \(res.verified)).",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "target": tgtDesc,
                        "verified": "\(res.verified)",
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Click failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "double_click":
            let coords = parseCoordinates(from: input["coordinates"])
            let coordSpace = (input["coordinates"] as? [String: Any])?["coordinate_space"] as? String ?? "screen"
            do {
                let res = try await AssistAppInteractionEngine.shared.click(
                    app: runningApp,
                    target: target,
                    coordinates: coords,
                    coordinateSpace: coordSpace,
                    button: "left",
                    clickCount: 2,
                    shouldVerify: shouldVerify
                )
                let tgtDesc = target ?? "@(\(Int(res.clickedPoint.x)),\(Int(res.clickedPoint.y)))"
                return AssistToolResult.success(
                    "Double-clicked '\(tgtDesc)' in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "target": tgtDesc,
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Double-click failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "right_click":
            let coords = parseCoordinates(from: input["coordinates"])
            let coordSpace = (input["coordinates"] as? [String: Any])?["coordinate_space"] as? String ?? "screen"
            do {
                let res = try await AssistAppInteractionEngine.shared.click(
                    app: runningApp,
                    target: target,
                    coordinates: coords,
                    coordinateSpace: coordSpace,
                    button: "right",
                    clickCount: 1,
                    shouldVerify: shouldVerify
                )
                let tgtDesc = target ?? "@(\(Int(res.clickedPoint.x)),\(Int(res.clickedPoint.y)))"
                return AssistToolResult.success(
                    "Right-clicked '\(tgtDesc)' in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "target": tgtDesc,
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Right-click failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "move_pointer":
            guard let coords = parseCoordinates(from: input["coordinates"]) else {
                return AssistToolResult.failure("Action 'move_pointer' requires parameter 'coordinates'.", code: .missingArgument)
            }
            let coordSpace = (input["coordinates"] as? [String: Any])?["coordinate_space"] as? String ?? "screen"
            _ = try? await AssistAppInteractionEngine.shared.click(app: runningApp, coordinates: coords, coordinateSpace: coordSpace, button: "left", clickCount: 0, shouldVerify: false)
            return AssistToolResult.success(
                "Moved pointer to (\(Int(coords.x)),\(Int(coords.y))) in '\(appName)'.",
                data: ["action": action, "app_identifier": bundleID, "status": "success"]
            )

        case "drag":
            guard let fromCoords = parseCoordinates(from: input["coordinates"]),
                  let toCoords = parseCoordinates(from: input["drag_destination"]) else {
                return AssistToolResult.failure("Action 'drag' requires 'coordinates' and 'drag_destination'.", code: .missingArgument)
            }
            let coordSpace = (input["coordinates"] as? [String: Any])?["coordinate_space"] as? String ?? "screen"
            do {
                _ = try await AssistAppInteractionEngine.shared.drag(app: runningApp, from: fromCoords, to: toCoords, coordinateSpace: coordSpace)
                return AssistToolResult.success(
                    "Dragged from (\(Int(fromCoords.x)),\(Int(fromCoords.y))) to (\(Int(toCoords.x)),\(Int(toCoords.y))) in '\(appName)'.",
                    data: ["action": action, "app_identifier": bundleID, "status": "success"]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Drag failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "scroll":
            let scrollDict = input["scroll_delta"] as? [String: Any]
            let dx = scrollDict?["dx"] as? Int ?? 0
            let dy = scrollDict?["dy"] as? Int ?? 0
            let coords = parseCoordinates(from: input["coordinates"])
            let coordSpace = (input["coordinates"] as? [String: Any])?["coordinate_space"] as? String ?? "screen"
            do {
                _ = try await AssistAppInteractionEngine.shared.scroll(app: runningApp, coordinates: coords, coordinateSpace: coordSpace, dx: dx, dy: dy)
                return AssistToolResult.success(
                    "Scrolled in '\(appName)' (dx: \(dx), dy: \(dy)).",
                    data: ["action": action, "app_identifier": bundleID, "status": "success"]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Scroll failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "type_text", "set_value":
            guard let text = value else {
                return AssistToolResult.failure("Action 'type_text' requires parameter 'value' containing the text to enter.", code: .missingArgument)
            }
            do {
                _ = try await AssistAppInteractionEngine.shared.typeText(app: runningApp, target: target, text: text)
                let tgtDesc = target ?? "active field"
                return AssistToolResult.success(
                    "Entered text into '\(tgtDesc)' in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "app_name": appName,
                        "target": tgtDesc,
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Text typing failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "press_key":
            guard let key = value else {
                return AssistToolResult.failure("Action 'press_key' requires parameter 'value' containing key name (e.g. 'Return', 'Tab', 'Escape').", code: .missingArgument)
            }
            let mods = (input["modifiers"] as? [String]) ?? []
            do {
                _ = try await AssistAppInteractionEngine.shared.pressKey(app: runningApp, keyName: key, modifiers: mods)
                return AssistToolResult.success(
                    "Pressed key '\(key)' in '\(appName)'.",
                    data: ["action": action, "app_identifier": bundleID, "status": "success"]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Key press failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "press_shortcut":
            guard let shortcut = value else {
                return AssistToolResult.failure("Action 'press_shortcut' requires parameter 'value' with shortcut name (e.g. 'Cmd+S', 'Cmd+Shift+P').", code: .missingArgument)
            }
            do {
                _ = try await AssistAppInteractionEngine.shared.pressShortcut(app: runningApp, shortcut: shortcut)
                return AssistToolResult.success(
                    "Triggered keyboard shortcut '\(shortcut)' in '\(appName)'.",
                    data: ["action": action, "app_identifier": bundleID, "status": "success"]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Shortcut failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "select_all":
            _ = try? await AssistAppInteractionEngine.shared.pressShortcut(app: runningApp, shortcut: "Cmd+A")
            return AssistToolResult.success("Selected all in '\(appName)'.", data: ["action": action, "app_identifier": bundleID, "status": "success"])

        case "copy":
            _ = try? await AssistAppInteractionEngine.shared.pressShortcut(app: runningApp, shortcut: "Cmd+C")
            return AssistToolResult.success("Triggered copy in '\(appName)'.", data: ["action": action, "app_identifier": bundleID, "status": "success"])

        case "paste":
            _ = try? await AssistAppInteractionEngine.shared.pressShortcut(app: runningApp, shortcut: "Cmd+V")
            return AssistToolResult.success("Triggered paste in '\(appName)'.", data: ["action": action, "app_identifier": bundleID, "status": "success"])

        case "activate_element":
            guard let target = target, !target.isEmpty else {
                return AssistToolResult.failure("Action 'activate_element' requires parameter 'target'.", code: .missingArgument)
            }
            do {
                let res = try await AssistAppInteractionEngine.shared.performSemanticAction(app: runningApp, target: target, actionName: "activate")
                return AssistToolResult.success(
                    "Activated control '\(target)' in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "target": target,
                        "verified": "\(res.verified)",
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Semantic activation failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "select_menu", "select_menu_item":
            guard let menuPath = target, !menuPath.isEmpty else {
                return AssistToolResult.failure("Action 'select_menu' requires parameter 'target' with menu path (e.g. 'File > Save').", code: .missingArgument)
            }
            do {
                _ = try AssistAppInteractionEngine.shared.selectMenuItem(app: runningApp, menuPath: menuPath)
                return AssistToolResult.success(
                    "Selected menu item '\(menuPath)' in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "target": menuPath,
                        "status": "success"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Menu selection failed: \(error.localizedDescription)", code: .executionFailed)
            }

        case "wait_for_element":
            guard let target = target, !target.isEmpty else {
                return AssistToolResult.failure("Action 'wait_for_element' requires parameter 'target'.", code: .missingArgument)
            }
            do {
                let elem = try await AssistAppInteractionEngine.shared.waitForElement(app: runningApp, target: target, timeoutSeconds: timeoutSeconds)
                return AssistToolResult.success(
                    "Element '\(target)' appeared: \(elem.displayDescription)",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "target": elem.id,
                        "element_role": elem.role,
                        "status": "appeared"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Wait failed: \(error.localizedDescription)", code: .timeout)
            }

        case "wait_for_window":
            guard let winTitle = target ?? windowId, !winTitle.isEmpty else {
                return AssistToolResult.failure("Action 'wait_for_window' requires parameter 'target' with expected window title.", code: .missingArgument)
            }
            do {
                let win = try await AssistAppInteractionEngine.shared.waitForWindow(app: runningApp, windowTitle: winTitle, timeoutSeconds: timeoutSeconds)
                return AssistToolResult.success(
                    "Window '\(win.title)' appeared: \(win.id) @(\(Int(win.frame.x)),\(Int(win.frame.y))).",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "window_id": win.id,
                        "window_title": win.title,
                        "status": "appeared"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Wait failed: \(error.localizedDescription)", code: .timeout)
            }

        case "verify", "verify_element_state":
            guard let target = target, !target.isEmpty else {
                return AssistToolResult.failure("Action 'verify' requires parameter 'target'.", code: .missingArgument)
            }
            do {
                let (_, desc) = try AssistAppInteractionEngine.shared.resolveElement(app: runningApp, target: target, session: session)
                let actualVal = desc?.value ?? ""
                if let expected = value, !expected.isEmpty {
                    let matches = actualVal.localizedCaseInsensitiveContains(expected) || actualVal == expected
                    if matches {
                        return AssistToolResult.success(
                            "Verified: element '\(target)' exists with expected value '\(expected)' (actual: '\(actualVal)').",
                            data: [
                                "action": action,
                                "app_identifier": bundleID,
                                "target": target,
                                "verified": "true",
                                "observed_state": actualVal
                            ]
                        )
                    } else {
                        return AssistToolResult.failure(
                            "Verification failed: element '\(target)' value '\(actualVal)' does not match expected '\(expected)'.",
                            code: .executionFailed,
                            diagnostics: ["Actual: '\(actualVal)'", "Expected: '\(expected)'"]
                        )
                    }
                }
                return AssistToolResult.success(
                    "Verified: element '\(target)' exists and is visible in '\(appName)'.",
                    data: [
                        "action": action,
                        "app_identifier": bundleID,
                        "target": target,
                        "verified": "true"
                    ]
                )
            } catch let err as AppInteractionError {
                return AssistToolResult.failure(err.localizedDescription, code: err.assistErrorCode, diagnostics: [err.recoveryHint])
            } catch {
                return AssistToolResult.failure("Verification failed: \(error.localizedDescription)", code: .executionFailed)
            }

        default:
            return AssistToolResult.failure(
                "Unsupported action '\(action)'. Supported actions: launch, activate, list_applications, list_windows, select_window, close_application, inspect_ui, get_accessibility_tree, get_focused_element, take_screenshot, click, double_click, right_click, move_pointer, drag, scroll, type_text, press_key, press_shortcut, select_all, copy, paste, activate_element, select_menu, wait_for_element, wait_for_window, verify.",
                code: .unsupportedOperation
            )
        }
    }

    private func parseCoordinates(from raw: Any?) -> CGPoint? {
        guard let dict = raw as? [String: Any] else { return nil }
        guard let x = dict["x"] as? Double ?? (dict["x"] as? Int).map(Double.init),
              let y = dict["y"] as? Double ?? (dict["y"] as? Int).map(Double.init) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }
}
