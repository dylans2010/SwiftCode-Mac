import Foundation
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistAppInteraction")

public struct AccessibleElementInfo: Sendable, Codable {
    public let role: String
    public let title: String
    public let identifier: String
    public let value: String
    public let isEnabled: Bool
    public let actions: [String]
}

public struct AppInteractionResult: Sendable {
    public let success: Bool
    public let action: String
    public let target: String?
    public let message: String
    public let elements: [AccessibleElementInfo]
    public let verified: Bool
    public let observedState: [String: String]
    public let diagnostics: [String]
}

public enum AppInteractionError: Error, LocalizedError {
    case accessibilityPermissionDenied(String)
    case applicationNotFound(String)
    case applicationLaunchFailed(String)
    case elementNotFound(String)
    case actionFailed(String)
    case unsupportedAction(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied(let msg):
            return "Accessibility permission required: \(msg). Please enable SwiftCode in macOS System Settings > Privacy & Security > Accessibility."
        case .applicationNotFound(let id):
            return "Application '\(id)' could not be found or resolved."
        case .applicationLaunchFailed(let msg):
            return "Failed to launch application: \(msg)"
        case .elementNotFound(let target):
            return "UI element matching target '\(target)' was not found in the application interface."
        case .actionFailed(let msg):
            return "UI interaction failed: \(msg)"
        case .unsupportedAction(let act):
            return "Action '\(act)' is not supported. Supported actions: launch, activate, inspect_ui, click, type_text, select_menu, verify."
        }
    }
}

public final class AssistAppInteractionEngine: Sendable {
    public static let shared = AssistAppInteractionEngine()

    private init() {}

    /// Checks if Accessibility access is trusted by macOS.
    public func checkAccessibilityAuthorization(promptIfDenied: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfDenied] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Resolves or launches the target application.
    @MainActor
    public func resolveOrLaunchApp(appIdentifier: String, autoLaunch: Bool = true) async throws -> NSRunningApplication {
        let trimmed = appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check running applications first
        let runningApps = NSWorkspace.shared.runningApplications
        if let running = runningApps.first(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(trimmed) == .orderedSame ||
            $0.localizedName?.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return running
        }

        guard autoLaunch else {
            throw AppInteractionError.applicationNotFound(trimmed)
        }

        // Try to locate URL by bundle identifier or app name
        var targetURL: URL?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            targetURL = url
        } else {
            // Check in standard /Applications or /System/Applications directories
            let appDirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
            for dir in appDirs {
                let candidate = URL(fileURLWithPath: "\(dir)/\(trimmed).app")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    targetURL = candidate
                    break
                }
            }
        }

        guard let appURL = targetURL else {
            throw AppInteractionError.applicationNotFound("Could not locate application bundle for '\(trimmed)'.")
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let launchedApp = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)

        // Wait up to 3 seconds for the app to finish launching
        for _ in 0..<30 {
            if launchedApp.isFinishedLaunching { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return launchedApp
    }

    /// Inspects the accessible UI hierarchy of the target application.
    public func inspectUI(app: NSRunningApplication, maxElements: Int = 100) -> [AccessibleElementInfo] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var results: [AccessibleElementInfo] = []

        var windowsRef: CFTypeRef?
        let axErr = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard axErr == .success, let windows = windowsRef as? [AXUIElement] else {
            return results
        }

        for window in windows {
            collectElements(element: window, results: &results, maxCount: maxElements, currentDepth: 0, maxDepth: 8)
            if results.count >= maxElements { break }
        }

        return results
    }

    private func collectElements(
        element: AXUIElement,
        results: inout [AccessibleElementInfo],
        maxCount: Int,
        currentDepth: Int,
        maxDepth: Int
    ) {
        guard currentDepth <= maxDepth && results.count < maxCount else { return }

        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute) ?? "Unknown"
        let title = copyStringAttribute(element: element, attribute: kAXTitleAttribute) ??
                    copyStringAttribute(element: element, attribute: kAXDescriptionAttribute) ?? ""
        let identifier = copyStringAttribute(element: element, attribute: kAXIdentifierAttribute) ?? ""
        let value = copyStringAttribute(element: element, attribute: kAXValueAttribute) ?? ""
        let enabled = copyBoolAttribute(element: element, attribute: kAXEnabledAttribute) ?? true

        var actionNames: [String] = []
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success, let actions = actionsRef as? [String] {
            actionNames = actions
        }

        // Only record interactive or named elements (buttons, text fields, menus, tabs, etc.)
        let interactiveRoles: Set<String> = [
            "AXButton", "AXTextField", "AXTextArea", "AXPopUpButton", "AXMenuButton",
            "AXCheckBox", "AXRadioButton", "AXTab", "AXSlider", "AXMenuItem",
            "AXComboBox", "AXWindow", "AXLink", "AXOutline", "AXTable"
        ]

        if interactiveRoles.contains(role) || !title.isEmpty || !identifier.isEmpty {
            results.append(AccessibleElementInfo(
                role: role,
                title: title,
                identifier: identifier,
                value: value,
                isEnabled: enabled,
                actions: actionNames
            ))
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectElements(element: child, results: &results, maxCount: maxCount, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                if results.count >= maxCount { break }
            }
        }
    }

    /// Searches for a target element within the application matching the given target query.
    public func findElement(app: NSRunningApplication, target: String) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        let query = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for window in windows {
            if let found = searchElement(element: window, query: query, depth: 0, maxDepth: 10) {
                return found
            }
        }
        return nil
    }

    private func searchElement(element: AXUIElement, query: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth <= maxDepth else { return nil }

        let title = (copyStringAttribute(element: element, attribute: kAXTitleAttribute) ?? "").lowercased()
        let identifier = (copyStringAttribute(element: element, attribute: kAXIdentifierAttribute) ?? "").lowercased()
        let desc = (copyStringAttribute(element: element, attribute: kAXDescriptionAttribute) ?? "").lowercased()
        let role = (copyStringAttribute(element: element, attribute: kAXRoleAttribute) ?? "").lowercased()

        if title == query || identifier == query || desc == query {
            return element
        }

        if !query.isEmpty && (title.contains(query) || identifier.contains(query) || desc.contains(query) || "\(role):\(title)".contains(query)) {
            return element
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = searchElement(element: child, query: query, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }

        return nil
    }

    /// Performs a UI action on the target element.
    public func performAction(action: String, targetElement: AXUIElement, value: String?) -> Bool {
        switch action.lowercased() {
        case "click", "press":
            // Try standard press action
            let err = AXUIElementPerformAction(targetElement, kAXPressAction as CFString)
            if err == .success { return true }
            // Try pick action
            let pickErr = AXUIElementPerformAction(targetElement, "AXPick" as CFString)
            return pickErr == .success

        case "type_text", "set_value":
            guard let value = value else { return false }
            let err = AXUIElementSetAttributeValue(targetElement, kAXValueAttribute as CFString, value as CFTypeRef)
            return err == .success

        case "focus":
            let err = AXUIElementSetAttributeValue(targetElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return err == .success

        default:
            let err = AXUIElementPerformAction(targetElement, action as CFString)
            return err == .success
        }
    }

    /// Selects a menu item from the application's menu bar (e.g. "File > New Window").
    public func selectMenuItem(app: NSRunningApplication, menuPath: String) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }

        let components = menuPath.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !components.isEmpty else { return false }

        return navigateAndPressMenu(currentElement: menuBar as! AXUIElement, components: components)
    }

    private func navigateAndPressMenu(currentElement: AXUIElement, components: [String]) -> Bool {
        guard let targetName = components.first else { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(currentElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        for child in children {
            let title = copyStringAttribute(element: child, attribute: kAXTitleAttribute) ?? ""
            if title.caseInsensitiveCompare(targetName) == .orderedSame {
                if components.count == 1 {
                    // Final menu item to trigger
                    return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
                } else {
                    // Submenu
                    return navigateAndPressMenu(currentElement: child, components: Array(components.dropFirst()))
                }
            }
        }
        return false
    }

    // MARK: - Attribute Extraction Helpers

    private func copyStringAttribute(element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard err == .success, let val = valueRef else { return nil }
        if let str = val as? String {
            return str
        } else if let num = val as? NSNumber {
            return num.stringValue
        } else if CFGetTypeID(val) == AXValueGetTypeID() {
            return nil
        }
        return nil
    }

    private func copyBoolAttribute(element: AXUIElement, attribute: String) -> Bool? {
        var valueRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard err == .success, let val = valueRef else { return nil }
        if let b = val as? Bool {
            return b
        }
        return nil
    }
}
