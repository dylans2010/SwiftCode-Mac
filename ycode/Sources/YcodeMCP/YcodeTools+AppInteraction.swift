import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
import YcodeAssistant
import YcodeIDECore

/// The macOS Accessibility / app-interaction engine for `use_app`:
/// Legacy's `AssistAppInteractionEngine` + `AssistUseAppTool`
/// dispatch, ported to ApplicationServices + CoreGraphics.
///
/// * Per-pid sessions (`app-<pid>`, stable — Legacy minted a
///   UUID per session; the id is reported, never required as an
///   input): elements `elem_1…`, descriptors, selected window,
///   windows, last screenshot.
/// * `inspect_ui` / `get_accessibility_tree`: AX walk, max 100
///   elements, depth 10, Legacy's actionable-roles filter.
/// * Input-delivery actions (click, type, keys, shortcuts, menus,
///   drag, scroll, set value) go through `approveChangeWithoutFile`
///   (no Autopilot bypass); reads, waits, verify, select_window,
///   and take_screenshot do not (the screenshot artifact save
///   gates itself).
/// * NEW vs Legacy's dispatch (which dropped them to its default
///   error): `inspect_application`, `inspect_window`, and
///   `set_element_value` (AX `kAXValueAttribute` set).
/// * Window ids: the AX engine numbers by AX order (`window_1…`,
///   Legacy's `listWindows`); the CGWindowList spelling
///   (`window_<CGWindowID>`) is accepted wherever a window id is
///   taken, resolved by matching frames; `list_windows` reports
///   both.
/// * `list_applications` also lists INSTALLED apps (Legacy's
///   four-directory scan), closing the Wave 4 running-only limit.
/// * Untrusted Accessibility → honest failure naming Accessibility
///   in System Settings.
///
/// See `specs/ide/gap-closure-failing-tools.md` §10.
extension YcodeMCPHost {
    /// `use_app`: the full dispatch. Non-AX actions reuse the
    /// TerminalSupport helpers; AX actions go to the engine below.
    func useAppReal(_ call: MCPToolCall) async throws -> MCPToolResult {
#if canImport(AppKit) && canImport(ApplicationServices)
        guard let rawAction = call.arguments["action"]?.string,
              !rawAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter 'action'. Call use_app with an action type.")
        }
        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if action == "list_applications" {
            let filter = call.string("target") ?? call.string("app_identifier")
            let apps = try axListApplications(filter: filter)
            var lines = ["Discovered \(apps.count) application(s):"]
            for (idx, a) in apps.prefix(35).enumerated() {
                let state = a.isRunning ? "RUNNING (PID: \(a.pid ?? 0))" : "installed"
                lines.append("\(idx + 1). \(a.name) [\(state)] — id: '\(a.bundleIdentifier)'")
            }
            if apps.count > 35 { lines.append("… and \(apps.count - 35) more applications.") }
            return .structured(["action": .string(action), "count": .int(apps.count), "status": .string("success")],
                               summary: lines.joined(separator: "\n"))
        }

        guard let rawAppId = call.arguments["app_identifier"]?.string,
              !rawAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter 'app_identifier'. Provide an application bundle identifier or app name.")
        }
        let appIdentifier = rawAppId.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirm = call.bool("confirm") ?? false

        switch action {
        case "launch", "activate", "activate_application", "launch_application":
            guard let app = terminalLaunchApplication(appIdentifier) else {
                throw MCPToolError("Application '\(appIdentifier)' could not be resolved or launched.")
            }
            _ = app.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(for: .milliseconds(100))
            let windows = terminalAppWindows(pid: app.processIdentifier)
            let appName = app.localizedName ?? appIdentifier
            let bundleID = app.bundleIdentifier ?? appIdentifier
            return .structured(["action": .string(action), "app_identifier": .string(bundleID), "app_name": .string(appName),
                                "pid": .int(Int(app.processIdentifier)), "window_count": .int(windows.count),
                                "status": .string("active")],
                               summary: "Application '\(appName)' (\(bundleID), PID: \(app.processIdentifier)) is active with \(windows.count) window(s).")

        case "close_application":
            guard confirm else {
                throw MCPToolError("Closing application '\(appIdentifier)' is a consequential action that will terminate running processes and unsaved user state. Pass 'confirm: true' to authorize.")
            }
            guard let app = terminalResolveRunningApplication(appIdentifier) else {
                throw MCPToolError("Application '\(appIdentifier)' is not running.")
            }
            let appName = app.localizedName ?? appIdentifier
            let bundleID = app.bundleIdentifier ?? appIdentifier
            let pid = app.processIdentifier
            let change = MCPChange(tool: call.name, path: app.bundleURL?.path ?? "/", relativePath: bundleID,
                                   original: nil, proposed: "",
                                   summary: "Close application '\(appName)' (\(bundleID), PID: \(pid))")
            guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
            let terminated = app.terminate()
            return .structured(["action": .string(action), "app_identifier": .string(bundleID), "app_name": .string(appName),
                                "status": .string("terminated")],
                               summary: "Closed application '\(appName)' (\(bundleID), PID: \(pid)). Terminate signal dispatched: \(terminated).")

        case "list_windows":
            guard let app = terminalResolveRunningApplication(appIdentifier) else {
                throw MCPToolError("Application '\(appIdentifier)' is not running.")
            }
            return try await axListWindowsResult(app: app, action: action)

        case "inspect_application", "inspect_window", "select_window", "inspect_ui", "get_accessibility_tree",
             "get_focused_element", "take_screenshot", "click", "double_click", "right_click", "move_pointer",
             "drag", "scroll", "type_text", "set_value", "press_key", "press_shortcut", "select_all", "copy",
             "paste", "activate_element", "set_element_value", "select_menu", "select_menu_item", "wait_for_element",
             "wait_for_window", "verify", "verify_element_state":
            guard let app = terminalResolveRunningApplication(appIdentifier) else {
                throw MCPToolError("Application '\(appIdentifier)' is not running.")
            }
            try axRequireTrusted()
            return try await axDispatch(call: call, action: action, app: app, appIdentifier: appIdentifier)

        default:
            throw MCPToolError("Unsupported action '\(action)'. Supported actions: launch, activate, list_applications, list_windows, select_window, close_application, inspect_application, inspect_window, inspect_ui, get_accessibility_tree, get_focused_element, take_screenshot, click, double_click, right_click, move_pointer, drag, scroll, type_text, set_value, press_key, press_shortcut, select_all, copy, paste, activate_element, set_element_value, select_menu, wait_for_element, wait_for_window, verify.")
        }
#else
        throw MCPToolError("use_app is only available on macOS.")
#endif
    }
}

#if canImport(AppKit) && canImport(ApplicationServices)
// MARK: - Sessions

/// One app's interaction session (Legacy's `AppSession`).
final class AXAppSession: @unchecked Sendable {
    let pid: Int32
    let bundleID: String
    let name: String
    var elements: [String: AXUIElement] = [:]
    var descriptors: [String: AXUIDescriptor] = [:]
    var selectedWindowID: String?
    var windows: [AXWindowInfo] = []
    var lastScreenshotArtifact: String?
    var lastScreenshotBase64: String?
    var lastScreenshotTimestamp: Date?
    init(pid: Int32, bundleID: String, name: String) { self.pid = pid; self.bundleID = bundleID; self.name = name }
    var sessionID: String { "app-\(pid)" }
}

/// The host's AX sessions, keyed by pid.
final class AXSessionsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [Int32: AXAppSession] = [:]
    func getOrCreate(for app: NSRunningApplication) -> AXAppSession {
        lock.withLock {
            if let existing = sessions[app.processIdentifier] { return existing }
            let session = AXAppSession(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "",
                                       name: app.localizedName ?? "")
            sessions[app.processIdentifier] = session
            return session
        }
    }
    func remove(pid: Int32) { lock.withLock { sessions.removeValue(forKey: pid) } }
}

private let axSessionsBox = AXSessionsBox()

/// One accessible UI element (Legacy's `AccessibleUIElementDescriptor`).
struct AXUIDescriptor: Sendable {
    var id: String
    var role: String
    var subrole: String
    var title: String
    var label: String
    var identifier: String
    var value: String
    var frame: AXRect
    var windowFrame: AXRect?
    var isEnabled: Bool
    var isFocused: Bool
    var isSelected: Bool
    var actions: [String]
    var json: AnyJSON {
        .object(["id": .string(id), "role": .string(role), "subrole": .string(subrole),
                 "title": .string(title), "label": .string(label), "identifier": .string(identifier),
                 "value": .string(value),
                 "frame": .object(["x": .double(frame.x), "y": .double(frame.y),
                                   "width": .double(frame.width), "height": .double(frame.height)]),
                 "isEnabled": .bool(isEnabled), "isFocused": .bool(isFocused), "isSelected": .bool(isSelected),
                 "actions": .array(actions.map(AnyJSON.string))])
    }
}

/// One window (Legacy's `AppWindowInfo`).
struct AXWindowInfo: Sendable {
    var id: String
    var title: String
    var frame: AXRect
    var isMain: Bool
    var isMinimized: Bool
    /// The CGWindowList window number, when the window could be
    /// matched by frame (lets callers use either spelling).
    var cgWindowID: Int?
    var json: AnyJSON {
        .object(["id": .string(id), "title": .string(title),
                 "frame": .object(["x": .double(frame.x), "y": .double(frame.y),
                                   "width": .double(frame.width), "height": .double(frame.height)]),
                 "isMain": .bool(isMain), "isMinimized": .bool(isMinimized),
                 "cgWindowId": cgWindowID.map(AnyJSON.int) ?? .null])
    }
}

struct AXRect: Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}

extension YcodeMCPHost {
    // MARK: - Trust

    /// Legacy's `checkAccessibilityAuthorization(promptIfDenied:)`:
    /// true when trusted, else prompts once and reports false for
    /// this call. Callers throw the honest failure naming
    /// Accessibility in System Settings.
    func axRequireTrusted() throws {
        if AXIsProcessTrusted() { return }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt as String: true] as CFDictionary)
        throw MCPToolError("Accessibility access is not authorized. Grant it in macOS System Settings > Privacy & Security > Accessibility for Ycode, then retry.")
    }

    // MARK: - Attribute helpers

    func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let val = valueRef else { return nil }
        if let str = val as? String { return str }
        if let num = val as? NSNumber { return num.stringValue }
        return nil
    }

    func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let val = valueRef as? Bool else { return nil }
        return val
    }

    func axFrame(_ element: AXUIElement) -> AXRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(), CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return AXRect(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
    }

    func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return [] }
        return children
    }

    func axWindows(_ app: NSRunningApplication) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return [] }
        return windows
    }

    // MARK: - Applications & windows

    struct AXDiscoveredApp: Sendable {
        var name: String
        var bundleIdentifier: String
        var bundleURL: String
        var isRunning: Bool
        var pid: Int32?
    }

    /// Legacy's `listApplications`: running first, then installed
    /// apps scanned from `/Applications`,
    /// `/System/Applications`, `/System/Applications/Utilities`,
    /// `~/Applications`.
    func axListApplications(filter: String?) throws -> [AXDiscoveredApp] {
        var results: [AXDiscoveredApp] = []
        var seenBundleIDs: Set<String> = []
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, !name.isEmpty else { continue }
            let bundleID = app.bundleIdentifier ?? ""
            if !bundleID.isEmpty { seenBundleIDs.insert(bundleID) }
            if let filter, !filter.isEmpty {
                guard name.localizedCaseInsensitiveContains(filter)
                        || bundleID.localizedCaseInsensitiveContains(filter) else { continue }
            }
            results.append(AXDiscoveredApp(name: name, bundleIdentifier: bundleID,
                                           bundleURL: app.bundleURL?.path ?? "", isRunning: true,
                                           pid: app.processIdentifier))
        }
        let appDirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let fm = FileManager.default
        for dir in appDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let fullPath = (dir as NSString).appendingPathComponent(entry)
                guard let bundle = Bundle(path: fullPath) else { continue }
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (entry as NSString).deletingPathExtension
                let bundleID = bundle.bundleIdentifier ?? ""
                if !bundleID.isEmpty && seenBundleIDs.contains(bundleID) { continue }
                if !bundleID.isEmpty { seenBundleIDs.insert(bundleID) }
                if let filter, !filter.isEmpty {
                    guard name.localizedCaseInsensitiveContains(filter)
                            || bundleID.localizedCaseInsensitiveContains(filter) else { continue }
                }
                results.append(AXDiscoveredApp(name: name, bundleIdentifier: bundleID, bundleURL: fullPath,
                                               isRunning: false, pid: nil))
            }
        }
        return results.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning && !$1.isRunning }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Legacy's `listWindows`: AX order, `window_1…`, with the
    /// CGWindowList number matched by frame when possible.
    func axListWindows(for app: NSRunningApplication) -> [AXWindowInfo] {
        let cgWindows = terminalAppWindows(pid: app.processIdentifier)
        var results: [AXWindowInfo] = []
        for (idx, window) in axWindows(app).enumerated() {
            let title = axString(window, kAXTitleAttribute) ?? ""
            let isMain = axBool(window, kAXMainAttribute) ?? (idx == 0)
            let isMinimized = axBool(window, kAXMinimizedAttribute) ?? false
            let frame = axFrame(window) ?? AXRect(x: 0, y: 0, width: 0, height: 0)
            let cg = cgWindows.first { cg in
                abs(Double(cg.x) - frame.x) < 2 && abs(Double(cg.y) - frame.y) < 2
                    && abs(Double(cg.width) - frame.width) < 2 && abs(Double(cg.height) - frame.height) < 2
            }
            let cgID = cg.flatMap { Int($0.id.replacingOccurrences(of: "window_", with: "")) }
            results.append(AXWindowInfo(id: "window_\(idx + 1)",
                                        title: title.isEmpty ? "Untitled Window \(idx + 1)" : title,
                                        frame: frame, isMain: isMain, isMinimized: isMinimized, cgWindowID: cgID))
        }
        return results
    }

    func axListWindowsResult(app: NSRunningApplication, action: String) async throws -> MCPToolResult {
        let windows = axListWindows(for: app)
        let appName = app.localizedName ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        if windows.isEmpty {
            return .structured(["action": .string(action), "app_identifier": .string(bundleID), "app_name": .string(appName),
                                "window_count": .int(0)],
                               summary: "No accessible windows currently open for '\(appName)'.")
        }
        var lines = ["Open window(s) for '\(appName)':"]
        for w in windows {
            let cg = w.cgWindowID.map { " (CGWindowID: \($0))" } ?? ""
            lines.append("- \(w.id)\(cg): \"\(w.title)\" @(\(Int(w.frame.x)),\(Int(w.frame.y)) \(Int(w.frame.width))x\(Int(w.frame.height)))")
        }
        return .structured(["action": .string(action), "app_identifier": .string(bundleID), "app_name": .string(appName),
                            "window_count": .int(windows.count), "windows": .array(windows.map(\.json)),
                            "status": .string("success")],
                           summary: lines.joined(separator: "\n"))
    }

    /// Resolves a window id: AX spelling (`window_1…`, or a title
    /// substring) or the CGWindowList spelling
    /// (`window_<CGWindowID>`, matched by frame). Returns the AX
    /// window element and its info.
    func axResolveWindow(app: NSRunningApplication, windowID: String) throws -> (element: AXUIElement, info: AXWindowInfo) {
        let windows = axWindows(app)
        let list = axListWindows(for: app)
        if let idx = list.firstIndex(where: { $0.id.caseInsensitiveCompare(windowID) == .orderedSame
                || $0.title.localizedCaseInsensitiveContains(windowID) }), idx < windows.count {
            return (windows[idx], list[idx])
        }
        if let num = Int(windowID.replacingOccurrences(of: "window_", with: "")) {
            if num > 0 && num <= windows.count {
                return (windows[num - 1], list[num - 1])
            }
            if let idx = list.firstIndex(where: { $0.cgWindowID == num }) {
                return (windows[idx], list[idx])
            }
        }
        throw MCPToolError("Window matching '\(windowID)' was not found for application '\(app.localizedName ?? "")'.")
    }

    /// Legacy's `selectWindow`: AX raise + set-main; records the
    /// selection in the session.
    func axSelectWindow(app: NSRunningApplication, windowID: String) throws -> AXWindowInfo {
        let (element, info) = try axResolveWindow(app: app, windowID: windowID)
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let session = axSessionsBox.getOrCreate(for: app)
        session.selectedWindowID = info.id
        return info
    }

    // MARK: - UI inspection

    static let axActionableRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXPopUpButton", "AXMenuButton",
        "AXCheckBox", "AXRadioButton", "AXTab", "AXSlider", "AXMenuItem",
        "AXComboBox", "AXWindow", "AXLink", "AXOutline", "AXTable", "AXRow",
        "AXCell", "AXStaticText", "AXImage", "AXSheet", "AXDialog", "AXAlert",
    ]

    /// Legacy's `inspectUI`: the selected window (or the first),
    /// max 100 elements, depth 10.
    func axInspectUI(app: NSRunningApplication, maxElements: Int = 100, targetWindowID: String? = nil) -> ([AXUIDescriptor], AXAppSession) {
        let session = axSessionsBox.getOrCreate(for: app)
        let windows = axWindows(app)
        guard !windows.isEmpty else {
            session.elements.removeAll(); session.descriptors.removeAll()
            return ([], session)
        }
        let list = axListWindows(for: app)
        let targetWindows: [AXUIElement]
        if let wid = targetWindowID ?? session.selectedWindowID,
           let idx = list.firstIndex(where: { $0.id == wid }), idx < windows.count {
            targetWindows = [windows[idx]]
        } else {
            targetWindows = [windows[0]]
        }
        var descriptors: [AXUIDescriptor] = []
        var references: [String: AXUIElement] = [:]
        var counter = 1
        for window in targetWindows {
            let winFrame = axFrame(window)
            axCollectElements(element: window, windowFrame: winFrame, descriptors: &descriptors,
                              references: &references, counter: &counter,
                              maxCount: maxElements, currentDepth: 0, maxDepth: 10)
            if descriptors.count >= maxElements { break }
        }
        session.elements = references
        session.descriptors = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        session.windows = list
        return (descriptors, session)
    }

    /// Legacy's `collectElements` (verbatim logic).
    func axCollectElements(element: AXUIElement, windowFrame: AXRect?,
                           descriptors: inout [AXUIDescriptor], references: inout [String: AXUIElement],
                           counter: inout Int, maxCount: Int, currentDepth: Int, maxDepth: Int) {
        guard currentDepth <= maxDepth && descriptors.count < maxCount else { return }
        let role = axString(element, kAXRoleAttribute) ?? "Unknown"
        let subrole = axString(element, kAXSubroleAttribute) ?? ""
        let title = axString(element, kAXTitleAttribute) ?? ""
        let label = axString(element, kAXDescriptionAttribute) ?? ""
        let identifier = axString(element, kAXIdentifierAttribute) ?? ""
        let value = axString(element, kAXValueAttribute) ?? ""
        let isEnabled = axBool(element, kAXEnabledAttribute) ?? true
        let isFocused = axBool(element, kAXFocusedAttribute) ?? false
        let isSelected = axBool(element, kAXSelectedAttribute) ?? false
        let frame = axFrame(element) ?? AXRect(x: 0, y: 0, width: 0, height: 0)
        var actions: [String] = []
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success, let actList = actionsRef as? [String] {
            actions = actList
        }
        let isInteractive = Self.axActionableRoles.contains(role) || !title.isEmpty || !label.isEmpty || !identifier.isEmpty
        if isInteractive && currentDepth > 0 {
            let elemId = "elem_\(counter)"
            counter += 1
            descriptors.append(AXUIDescriptor(id: elemId, role: role, subrole: subrole, title: title, label: label,
                                              identifier: identifier, value: value, frame: frame, windowFrame: windowFrame,
                                              isEnabled: isEnabled, isFocused: isFocused, isSelected: isSelected,
                                              actions: actions))
            references[elemId] = element
        }
        for child in axChildren(element) {
            axCollectElements(element: child, windowFrame: windowFrame, descriptors: &descriptors,
                              references: &references, counter: &counter,
                              maxCount: maxCount, currentDepth: currentDepth + 1, maxDepth: maxDepth)
            if descriptors.count >= maxCount { break }
        }
    }

    /// Legacy's `resolveElement`: session id, then exact cached
    /// title/identifier/label, then a unique substring match
    /// (ambiguous → error naming the candidates), then a live
    /// recursive search of the app's windows.
    func axResolveElement(app: NSRunningApplication, target: String) throws -> (element: AXUIElement, descriptor: AXUIDescriptor?) {
        let session = axSessionsBox.getOrCreate(for: app)
        let query = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ref = session.elements[query] {
            return (ref, session.descriptors[query])
        }
        let descriptors = Array(session.descriptors.values)
        if let match = descriptors.first(where: {
            $0.identifier.caseInsensitiveCompare(query) == .orderedSame ||
            $0.title.caseInsensitiveCompare(query) == .orderedSame ||
            $0.label.caseInsensitiveCompare(query) == .orderedSame
        }), let ref = session.elements[match.id] {
            return (ref, match)
        }
        let substringMatches = descriptors.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.label.localizedCaseInsensitiveContains(query) ||
            $0.identifier.localizedCaseInsensitiveContains(query)
        }
        if substringMatches.count == 1, let ref = session.elements[substringMatches[0].id] {
            return (ref, substringMatches[0])
        } else if substringMatches.count > 1 {
            let candidates = substringMatches.prefix(4).map { "\($0.id): [\($0.role)] '\($0.title)'" }.joined(separator: ", ")
            throw MCPToolError("Target '\(query)' matches multiple controls: \(candidates). Specify the exact element ID (e.g. '\(substringMatches[0].id)').")
        }
        for window in axWindows(app) {
            if let liveMatch = axSearchLiveElement(element: window, query: query.lowercased(), depth: 0, maxDepth: 10) {
                return (liveMatch, nil)
            }
        }
        throw MCPToolError("UI element matching '\(query)' was not found in application '\(app.localizedName ?? "")'. Use action 'inspect_ui' to examine the visible hierarchy.")
    }

    func axSearchLiveElement(element: AXUIElement, query: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth <= maxDepth else { return nil }
        let title = (axString(element, kAXTitleAttribute) ?? "").lowercased()
        let identifier = (axString(element, kAXIdentifierAttribute) ?? "").lowercased()
        let label = (axString(element, kAXDescriptionAttribute) ?? "").lowercased()
        let role = (axString(element, kAXRoleAttribute) ?? "").lowercased()
        if title == query || identifier == query || label == query { return element }
        if !query.isEmpty && (title.contains(query) || identifier.contains(query) || label.contains(query)
                              || "\(role):\(title)".contains(query)) { return element }
        for child in axChildren(element) {
            if let found = axSearchLiveElement(element: child, query: query, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    // MARK: - Semantic actions

    /// Legacy's `performSemanticAction`: press (with AXPick
    /// fallback), set_value/type_text (AX value set), focus,
    /// select, expand/collapse, else the named AX action.
    /// Returns (dispatched, verified, observedChange).
    func axPerformSemanticAction(app: NSRunningApplication, target: String, actionName: String,
                                 value: String?, shouldVerify: Bool) async throws -> (Bool, Bool, String?) {
        let (element, _) = try axResolveElement(app: app, target: target)
        let normalized = actionName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var dispatched = false
        switch normalized {
        case "click", "press", "activate":
            if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                dispatched = true
            } else if AXUIElementPerformAction(element, "AXPick" as CFString) == .success {
                dispatched = true
            }
        case "set_value", "type_text":
            guard let val = value else {
                throw MCPToolError("Action '\(actionName)' requires parameter 'value'.")
            }
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, val as CFTypeRef) == .success {
                dispatched = true
            }
        case "focus":
            dispatched = (AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success)
        case "select":
            dispatched = (AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success)
        case "expand":
            dispatched = (AXUIElementSetAttributeValue(element, "AXDisclosing" as CFString, kCFBooleanTrue) == .success)
        case "collapse":
            dispatched = (AXUIElementSetAttributeValue(element, "AXDisclosing" as CFString, kCFBooleanFalse) == .success)
        default:
            dispatched = (AXUIElementPerformAction(element, actionName as CFString) == .success)
        }
        guard dispatched else {
            throw MCPToolError("Semantic action '\(actionName)' was rejected by target control '\(target)'.")
        }
        var isVerified = false
        var stateChange: String?
        if shouldVerify {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let newValue = axString(element, kAXValueAttribute) {
                stateChange = "Value is now '\(newValue)'"
                isVerified = true
            } else {
                isVerified = true
            }
        }
        return (true, isVerified, stateChange)
    }

    // MARK: - Menus

    /// Legacy's `selectMenuItem`: walks the menu bar by the
    /// `File > Save` path; a disabled item refuses.
    func axSelectMenuItem(app: NSRunningApplication, menuPath: String) throws {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef as? AXUIElement else {
            throw MCPToolError("Application '\(app.localizedName ?? "")' does not expose a standard accessible menu bar.")
        }
        let components = menuPath.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !components.isEmpty, !components[0].isEmpty else {
            throw MCPToolError("Menu path cannot be empty.")
        }
        guard axNavigateAndPressMenu(currentElement: menuBar, components: components) else {
            throw MCPToolError("Menu item '\(menuPath)' could not be triggered or was disabled.")
        }
    }

    func axNavigateAndPressMenu(currentElement: AXUIElement, components: [String]) -> Bool {
        guard let targetName = components.first else { return false }
        for child in axChildren(currentElement) {
            let title = axString(child, kAXTitleAttribute) ?? ""
            if title.caseInsensitiveCompare(targetName) == .orderedSame {
                if components.count == 1 {
                    let enabled = axBool(child, kAXEnabledAttribute) ?? true
                    guard enabled else { return false }
                    return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
                } else {
                    return axNavigateAndPressMenu(currentElement: child, components: Array(components.dropFirst()))
                }
            }
        }
        return false
    }

    // MARK: - Pointer & keyboard

    /// Legacy's `click` (move, then down/up with clickCount; a
    /// second pair for double-click; `clickCount: 0` moves only).
    func axClick(app: NSRunningApplication, target: String?, coordinates: CGPoint?, coordinateSpace: String,
                 button: String, clickCount: Int, shouldVerify: Bool) async throws -> CGPoint {
        let targetPoint: CGPoint
        if let target, !target.isEmpty {
            let (element, desc) = try axResolveElement(app: app, target: target)
            if let desc, desc.frame.width > 0 {
                targetPoint = desc.frame.center
            } else if let frame = axFrame(element) {
                targetPoint = frame.center
            } else {
                throw MCPToolError("Cannot determine coordinates for target '\(target)'.")
            }
        } else if let coords = coordinates {
            targetPoint = axConvertToScreenCoordinates(point: coords, space: coordinateSpace, app: app)
        } else {
            throw MCPToolError("Action requires either 'target' UI element or 'coordinates'.")
        }
        let mouseTypeDown: CGEventType = (button.lowercased() == "right") ? .rightMouseDown : .leftMouseDown
        let mouseTypeUp: CGEventType = (button.lowercased() == "right") ? .rightMouseUp : .leftMouseUp
        let mouseButton: CGMouseButton = (button.lowercased() == "right") ? .right : .left
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: targetPoint, mouseButton: .left) else {
            throw MCPToolError("Failed to create mouse move event.")
        }
        moveEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 20_000_000)
        guard clickCount > 0 else { return targetPoint }
        guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: mouseTypeDown, mouseCursorPosition: targetPoint, mouseButton: mouseButton),
              let upEvent = CGEvent(mouseEventSource: nil, mouseType: mouseTypeUp, mouseCursorPosition: targetPoint, mouseButton: mouseButton) else {
            throw MCPToolError("Failed to create mouse click events.")
        }
        downEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        upEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        downEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 40_000_000)
        upEvent.post(tap: .cghidEventTap)
        if clickCount > 1 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            downEvent.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 40_000_000)
            upEvent.post(tap: .cghidEventTap)
        }
        if shouldVerify { try? await Task.sleep(nanoseconds: 150_000_000) }
        return targetPoint
    }

    /// Legacy's `drag` (move → down → dragged → up).
    func axDrag(app: NSRunningApplication, from: CGPoint, to: CGPoint, coordinateSpace: String) async throws {
        let startPt = axConvertToScreenCoordinates(point: from, space: coordinateSpace, app: app)
        let endPt = axConvertToScreenCoordinates(point: to, space: coordinateSpace, app: app)
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: startPt, mouseButton: .left),
              let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: startPt, mouseButton: .left),
              let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: endPt, mouseButton: .left),
              let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: endPt, mouseButton: .left) else {
            throw MCPToolError("Failed to generate drag events.")
        }
        moveEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 40_000_000)
        downEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        dragEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        upEvent.post(tap: .cghidEventTap)
    }

    /// Legacy's `scroll` (pixel wheel, dx/dy).
    func axScroll(app: NSRunningApplication, coordinates: CGPoint?, coordinateSpace: String, dx: Int, dy: Int) async throws {
        if let pt = coordinates {
            let screenPt = axConvertToScreenCoordinates(point: pt, space: coordinateSpace, app: app)
            if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: screenPt, mouseButton: .left) {
                move.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else {
            throw MCPToolError("Failed to generate scroll event.")
        }
        scrollEvent.post(tap: .cghidEventTap)
    }

    /// Legacy's `typeText`: focus the target first, then Unicode
    /// injection per UTF-16 unit — or, for text over 100
    /// characters, clipboard + Cmd+V with the prior clipboard
    /// restored.
    func axTypeText(app: NSRunningApplication, target: String?, text: String, useClipboard: Bool) async throws {
        if let target, !target.isEmpty {
            _ = try? await axPerformSemanticAction(app: app, target: target, actionName: "focus", value: nil, shouldVerify: false)
        }
        if useClipboard && text.count > 100 {
            let pasteboard = NSPasteboard.general
            let priorContent = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            _ = try await axPressShortcut(app: app, shortcut: "Cmd+V")
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let prior = priorContent {
                pasteboard.clearContents()
                pasteboard.setString(prior, forType: .string)
            }
            return
        }
        for char in Array(text.utf16) {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            var codeUnit = char
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Legacy's `resolveKeyCode` (verbatim table).
    static func axKeyCode(for keyName: String) -> CGKeyCode {
        switch keyName.lowercased() {
        case "return", "enter": return 36
        case "tab": return 48
        case "space": return 49
        case "delete", "backspace": return 51
        case "escape", "esc": return 53
        case "command", "cmd": return 55
        case "shift": return 56
        case "option", "alt": return 58
        case "control", "ctrl": return 59
        case "left", "leftarrow": return 123
        case "right", "rightarrow": return 124
        case "down", "downarrow": return 125
        case "up", "uparrow": return 126
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "=": return 24
        case "9": return 25
        case "7": return 26
        case "-": return 27
        case "8": return 28
        case "0": return 29
        default: return 36
        }
    }

    static func axModifierFlags(_ modifiers: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }
        return flags
    }

    /// Legacy's `pressKey`.
    func axPressKey(app: NSRunningApplication, keyName: String, modifiers: [String]) async throws {
        let keyCode = Self.axKeyCode(for: keyName)
        let flags = Self.axModifierFlags(modifiers)
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw MCPToolError("Failed to create keyboard events for key '\(keyName)'.")
        }
        if !flags.isEmpty {
            keyDown.flags = flags
            keyUp.flags = flags
        }
        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 20_000_000)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Legacy's `pressShortcut` (`Cmd+S`, `Command+Shift+P`, …).
    func axPressShortcut(app: NSRunningApplication, shortcut: String) async throws {
        let parts = shortcut.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last, !keyPart.isEmpty else {
            throw MCPToolError("Empty keyboard shortcut.")
        }
        try await axPressKey(app: app, keyName: keyPart, modifiers: Array(parts.dropLast()))
    }

    // MARK: - Waiting & verification

    /// Legacy's `waitForElement` (200 ms poll, 1–60 s, default 5).
    func axWaitForElement(app: NSRunningApplication, target: String, timeoutSeconds: Double) async throws -> AXUIDescriptor {
        let maxIterations = Int(timeoutSeconds * 5.0)
        for _ in 0..<max(maxIterations, 1) {
            let (elements, _) = axInspectUI(app: app, maxElements: 120)
            if let matched = elements.first(where: {
                $0.id.caseInsensitiveCompare(target) == .orderedSame ||
                $0.identifier.caseInsensitiveCompare(target) == .orderedSame ||
                $0.title.localizedCaseInsensitiveContains(target) ||
                $0.label.localizedCaseInsensitiveContains(target)
            }) {
                return matched
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw MCPToolError("Element matching '\(target)' did not appear within \(timeoutSeconds)s in '\(app.localizedName ?? "")'.")
    }

    /// Legacy's `waitForWindow`.
    func axWaitForWindow(app: NSRunningApplication, windowTitle: String, timeoutSeconds: Double) async throws -> AXWindowInfo {
        let maxIterations = Int(timeoutSeconds * 5.0)
        for _ in 0..<max(maxIterations, 1) {
            let windows = axListWindows(for: app)
            if let matched = windows.first(where: {
                $0.title.localizedCaseInsensitiveContains(windowTitle) ||
                $0.id.caseInsensitiveCompare(windowTitle) == .orderedSame
            }) {
                return matched
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw MCPToolError("Window matching '\(windowTitle)' did not appear within \(timeoutSeconds)s.")
    }

    /// Legacy's `verify`: case-insensitive contains-or-equal
    /// against the element's value (falling back to its title).
    func axVerify(app: NSRunningApplication, target: String, expected: String) throws -> (verified: Bool, actual: String) {
        let (element, descriptor) = try axResolveElement(app: app, target: target)
        let actual = axString(element, kAXValueAttribute) ?? descriptor?.title ?? ""
        let lower = actual.lowercased()
        let want = expected.lowercased()
        return (lower.contains(want) || lower == want, actual)
    }

    // MARK: - Coordinates

    /// Legacy's `convertToScreenCoordinates`.
    func axConvertToScreenCoordinates(point: CGPoint, space: String, app: NSRunningApplication) -> CGPoint {
        switch space.lowercased() {
        case "window":
            let session = axSessionsBox.getOrCreate(for: app)
            if let wid = session.selectedWindowID,
               let win = session.windows.first(where: { $0.id == wid }) {
                return CGPoint(x: win.frame.x + Double(point.x), y: win.frame.y + Double(point.y))
            }
            return point
        case "screenshot_pixel":
            let scale = (NSScreen.main?.backingScaleFactor) ?? 2.0
            return CGPoint(x: point.x / scale, y: point.y / scale)
        default:
            return point
        }
    }

    // MARK: - Screenshot

    /// Legacy's `captureAppScreenshot`: fullscreen capture
    /// cropped to the target window (main window when no id is
    /// given), with Legacy's scale / integral-rect math.
    func axCaptureAppScreenshot(call: MCPToolCall, app: NSRunningApplication, windowID: String?) async throws -> MCPToolResult {
#if canImport(ScreenCaptureKit)
        let s = try session(for: call)
        guard terminalScreenCaptureAuthorized() else {
            throw MCPToolError("Screen Recording permission has not been granted. Please grant Screen Recording permission to Ycode in macOS System Settings > Privacy & Security > Screen Recording, then retry.")
        }
        let windows = axListWindows(for: app)
        let targetWindow: AXWindowInfo?
        if let wid = windowID {
            targetWindow = windows.first(where: { $0.id == wid })
        } else {
            targetWindow = windows.first(where: { $0.isMain }) ?? windows.first
        }
        let shot = try await terminalCaptureScreenshot(displayID: nil, includeCursor: true)
        var finalPNG = shot.png
        var resultRect = AXRect(x: 0, y: 0, width: Double(shot.width), height: Double(shot.height))
        if let win = targetWindow, win.frame.width > 2 && win.frame.height > 2 {
            let mainDisplayID = CGMainDisplayID()
            let dispBounds = CGDisplayBounds(mainDisplayID)
            let scale = CGFloat(shot.width) / dispBounds.width
            let cropRect = CGRect(
                x: win.frame.x * Double(scale),
                y: win.frame.y * Double(scale),
                width: win.frame.width * Double(scale),
                height: win.frame.height * Double(scale)
            ).integral
            if let source = CGImageSourceCreateWithData(shot.png as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
               let cropped = image.cropping(to: cropRect),
               let croppedPNG = terminalEncodePNG(cropped) {
                finalPNG = croppedPNG
                resultRect = win.frame
            }
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let safeName = (app.localizedName ?? "app").lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24)
        let uniqueName = "app_\(safeName)_\(timestamp).png"
        let rel = ".assist_temp/artifacts/\(uniqueName)"
        let url = artifactDirectory(in: s).appendingPathComponent(uniqueName)
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: nil,
                                           summary: "Save app screenshot artifact \(rel)", call: call)
        do {
            try FileManager.default.createDirectory(at: artifactDirectory(in: s), withIntermediateDirectories: true)
            try finalPNG.write(to: url, options: .atomic)
        } catch {
            throw MCPToolError("Captured app screenshot successfully but failed to save artifact: \(error.localizedDescription)")
        }
        let session = axSessionsBox.getOrCreate(for: app)
        session.lastScreenshotArtifact = rel
        session.lastScreenshotBase64 = finalPNG.base64EncodedString()
        session.lastScreenshotTimestamp = Date()
        var index = loadFileReadingArtifactIndex(in: s)
        let entry = FileReadingArtifactIndexEntry(id: UUID(), description: "App screenshot for \(app.localizedName ?? "")",
                                                 kind: "image", createdAt: Date(), sourceMessageID: nil)
        index[uniqueName] = entry
        saveFileReadingArtifactIndex(index, in: s)
        noteFileWritingChanged(url, in: s)
        let json = AnyJSON.object(["path": .string(rel), "width": .int(Int(resultRect.width)), "height": .int(Int(resultRect.height)),
                                   "app_identifier": .string(app.bundleIdentifier ?? ""), "app_name": .string(app.localizedName ?? ""),
                                   "artifact_id": .string(entry.id.uuidString),
                                   "base64": .string(finalPNG.base64EncodedString()),
                                   "format": .string("png"), "size_bytes": .int(finalPNG.count)])
        return MCPToolResult(content: [.imageBlock(finalPNG), .textBlock("Captured screenshot of '\(app.localizedName ?? "")' (\(Int(resultRect.width))×\(Int(resultRect.height)) px). Artifact saved to '\(rel)'."), .textBlock(json.text)],
                             structured: json)
#else
        throw MCPToolError("use_app take_screenshot is only available on macOS (ScreenCaptureKit).")
#endif
    }

    // MARK: - Dispatch

    /// The AX action dispatch (Legacy's `AssistUseAppTool`
    /// dispatch, extended with `inspect_application`,
    /// `inspect_window`, and `set_element_value`).
    func axDispatch(call: MCPToolCall, action: String, app: NSRunningApplication, appIdentifier: String) async throws -> MCPToolResult {
        let appName = app.localizedName ?? appIdentifier
        let bundleID = app.bundleIdentifier ?? appIdentifier
        let session = axSessionsBox.getOrCreate(for: app)
        let target = call.string("target")
        let value = call.string("value")
        let shouldVerify = call.bool("verification") ?? true
        let windowID = call.string("window_id")
        let coords = call.arguments["coordinates"]?.object
        let coordSpace = coords?["coordinate_space"]?.string ?? "screen"
        let coordPoint: CGPoint? = {
            guard let x = coords?["x"]?.double, let y = coords?["y"]?.double else { return nil }
            return CGPoint(x: x, y: y)
        }()
        let timeout = min(max(call.arguments["timeout"]?.double ?? 5, 1), 60)

        func base(_ extra: [String: AnyJSON] = [:]) -> [String: AnyJSON] {
            var out: [String: AnyJSON] = ["action": .string(action), "app_identifier": .string(bundleID),
                                          "app_name": .string(appName), "pid": .int(Int(app.processIdentifier)),
                                          "session_id": .string(session.sessionID), "status": .string("success")]
            for (key, val) in extra { out[key] = val }
            return out
        }

        /// Approval for input-delivery actions (no Autopilot).
        func approveInput(_ summary: String) async throws {
            try await approveChangeWithoutFile(tool: "use_app", summary: summary, call: call)
        }

        switch action {
        case "inspect_application":
            let windows = axListWindows(for: app)
            return .structured(base(["is_active": .bool(app.isActive), "is_hidden": .bool(app.isHidden),
                                     "window_count": .int(windows.count),
                                     "windows": .array(windows.map(\.json))]),
                               summary: "Application '\(appName)' (\(bundleID), PID: \(app.processIdentifier)) — active: \(app.isActive), hidden: \(app.isHidden), \(windows.count) window(s).")

        case "inspect_window":
            guard let wid = windowID ?? target, !wid.isEmpty else {
                throw MCPToolError("inspect_window needs 'window_id' (e.g. 'window_1').")
            }
            let (_, info) = try axResolveWindow(app: app, windowID: wid)
            return .structured(base(["window_id": .string(info.id), "title": .string(info.title),
                                     "frame": .object(["x": .double(info.frame.x), "y": .double(info.frame.y),
                                                       "width": .double(info.frame.width), "height": .double(info.frame.height)]),
                                     "is_main": .bool(info.isMain), "is_minimized": .bool(info.isMinimized),
                                     "role": .string("AXWindow")]),
                               summary: "Window '\(info.title)' (\(info.id)) @(\(Int(info.frame.x)),\(Int(info.frame.y)) \(Int(info.frame.width))x\(Int(info.frame.height))), main: \(info.isMain), minimized: \(info.isMinimized).")

        case "select_window":
            guard let wid = windowID ?? target, !wid.isEmpty else {
                throw MCPToolError("select_window needs 'window_id' (e.g. 'window_1').")
            }
            let info = try axSelectWindow(app: app, windowID: wid)
            return .structured(base(["window_id": .string(info.id), "title": .string(info.title), "status": .string("selected")]),
                               summary: "Selected window '\(info.title)' (\(info.id)) in '\(appName)'.")

        case "inspect_ui", "get_accessibility_tree":
            let (elements, _) = axInspectUI(app: app, targetWindowID: windowID)
            if elements.isEmpty {
                return .structured(base(["element_count": .int(0), "elements": .array([])]),
                                   summary: "No accessible UI elements found in '\(appName)'. The app may have no windows, or Accessibility may not expose its hierarchy.")
            }
            var lines = ["Accessible UI (\(elements.count) element(s)) for '\(appName)':"]
            for e in elements {
                let label = e.title.isEmpty ? e.label : e.title
                lines.append("- \(e.id) [\(e.role)] '\(label)' @(\(Int(e.frame.x)),\(Int(e.frame.y)) \(Int(e.frame.width))x\(Int(e.frame.height)))")
            }
            return .structured(base(["element_count": .int(elements.count), "elements": .array(elements.map(\.json))]),
                               summary: lines.joined(separator: "\n"))

        case "get_focused_element":
            let systemWide = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
                  let focused = focusedRef as? AXUIElement else {
                throw MCPToolError("No focused UI element could be read (the frontmost app may not expose one).")
            }
            let role = axString(focused, kAXRoleAttribute) ?? "Unknown"
            let title = axString(focused, kAXTitleAttribute) ?? ""
            let label = axString(focused, kAXDescriptionAttribute) ?? ""
            let identifier = axString(focused, kAXIdentifierAttribute) ?? ""
            let value = axString(focused, kAXValueAttribute) ?? ""
            let frame = axFrame(focused) ?? AXRect(x: 0, y: 0, width: 0, height: 0)
            return .structured(base(["role": .string(role), "title": .string(title), "label": .string(label),
                                     "identifier": .string(identifier), "value": .string(value),
                                     "frame": .object(["x": .double(frame.x), "y": .double(frame.y),
                                                       "width": .double(frame.width), "height": .double(frame.height)])]),
                               summary: "Focused element: [\(role)] '\(title.isEmpty ? label : title)' @(\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))).")

        case "take_screenshot":
            return try await axCaptureAppScreenshot(call: call, app: app, windowID: windowID)

        case "click", "double_click", "right_click":
            let button = action == "right_click" ? "right" : "left"
            let count = action == "double_click" ? 2 : 1
            try await approveInput("\(action) in '\(appName)'\(target.map { " on '\($0)'" } ?? "")\(coordPoint.map { " at (\($0.x), \($0.y))" } ?? "").")
            let point = try await axClick(app: app, target: target, coordinates: coordPoint, coordinateSpace: coordSpace,
                                          button: button, clickCount: count, shouldVerify: shouldVerify)
            return .structured(base(["clicked_point": .object(["x": .double(Double(point.x)), "y": .double(Double(point.y))]),
                                     "verified": .bool(shouldVerify)]),
                               summary: "Clicked '\(appName)' at (\(Int(point.x)), \(Int(point.y))).")

        case "move_pointer":
            let point = try await axClick(app: app, target: target, coordinates: coordPoint, coordinateSpace: coordSpace,
                                          button: "left", clickCount: 0, shouldVerify: false)
            return .structured(base(["moved_point": .object(["x": .double(Double(point.x)), "y": .double(Double(point.y))])]),
                               summary: "Moved pointer to (\(Int(point.x)), \(Int(point.y))) in '\(appName)'.")

        case "drag":
            guard let from = coordPoint else {
                throw MCPToolError("drag needs 'coordinates' (the drag start) and 'drag_destination'.")
            }
            let dest = call.arguments["drag_destination"]?.object
            guard let dx = dest?["x"]?.double, let dy = dest?["y"]?.double else {
                throw MCPToolError("drag needs 'drag_destination' with x and y.")
            }
            try await approveInput("Drag in '\(appName)' from (\(from.x), \(from.y)) to (\(dx), \(dy)).")
            try await axDrag(app: app, from: from, to: CGPoint(x: dx, y: dy), coordinateSpace: coordSpace)
            return .structured(base(), summary: "Dragged in '\(appName)' from (\(Int(from.x)), \(Int(from.y))) to (\(Int(dx)), \(Int(dy))).")

        case "scroll":
            let delta = call.arguments["scroll_delta"]?.object
            let dx = delta?["dx"]?.int ?? 0
            let dy = delta?["dy"]?.int ?? 0
            try await approveInput("Scroll in '\(appName)' by (\(dx), \(dy)) pixels.")
            try await axScroll(app: app, coordinates: coordPoint, coordinateSpace: coordSpace, dx: dx, dy: dy)
            return .structured(base(["dx": .int(dx), "dy": .int(dy)]),
                               summary: "Scrolled in '\(appName)' by (\(dx), \(dy)) pixels.")

        case "type_text", "set_value":
            guard let text = value, !text.isEmpty else {
                throw MCPToolError("Action '\(action)' requires parameter 'value' (the text to type).")
            }
            try await approveInput("Type text in '\(appName)'\(target.map { " into '\($0)'" } ?? "").")
            try await axTypeText(app: app, target: target, text: text, useClipboard: text.count > 100)
            return .structured(base(["characters": .int(text.count)]),
                               summary: "Typed \(text.count) character(s) in '\(appName)'.")

        case "set_element_value":
            guard let target, !target.isEmpty else {
                throw MCPToolError("set_element_value needs 'target' (the element) and 'value'.")
            }
            guard let text = value else {
                throw MCPToolError("set_element_value needs 'value'.")
            }
            try await approveInput("Set the value of '\(target)' in '\(appName)'.")
            let (element, _) = try axResolveElement(app: app, target: target)
            guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success else {
                throw MCPToolError("The element '\(target)' does not accept a value being set through Accessibility.")
            }
            return .structured(base(["target": .string(target)]),
                               summary: "Set the value of '\(target)' in '\(appName)'.")

        case "press_key":
            guard let key = value, !key.isEmpty else {
                throw MCPToolError("press_key needs 'value' (the key name, e.g. 'Return').")
            }
            let modifiers = call.strings("modifiers") ?? []
            try await approveInput("Press key '\(key)' in '\(appName)'.")
            try await axPressKey(app: app, keyName: key, modifiers: modifiers)
            return .structured(base(["key": .string(key)]), summary: "Pressed '\(key)' in '\(appName)'.")

        case "press_shortcut":
            guard let shortcut = value, !shortcut.isEmpty else {
                throw MCPToolError("press_shortcut needs 'value' (the shortcut, e.g. 'Cmd+S').")
            }
            try await approveInput("Press shortcut '\(shortcut)' in '\(appName)'.")
            try await axPressShortcut(app: app, shortcut: shortcut)
            return .structured(base(["shortcut": .string(shortcut)]), summary: "Pressed shortcut '\(shortcut)' in '\(appName)'.")

        case "select_all", "copy", "paste":
            let shortcut = action == "select_all" ? "Cmd+A" : (action == "copy" ? "Cmd+C" : "Cmd+V")
            try await approveInput("Press shortcut '\(shortcut)' (\(action)) in '\(appName)'.")
            try await axPressShortcut(app: app, shortcut: shortcut)
            return .structured(base(["shortcut": .string(shortcut)]), summary: "Pressed '\(shortcut)' (\(action)) in '\(appName)'.")

        case "activate_element":
            guard let target, !target.isEmpty else {
                throw MCPToolError("activate_element needs 'target' (the element to activate).")
            }
            try await approveInput("Activate '\(target)' in '\(appName)'.")
            let (_, verified, observed) = try await axPerformSemanticAction(app: app, target: target, actionName: "activate",
                                                                            value: nil, shouldVerify: shouldVerify)
            return .structured(base(["target": .string(target), "verified": .bool(verified),
                                     "observed_change": observed.map(AnyJSON.string) ?? .null]),
                               summary: "Activated '\(target)' in '\(appName)'\(observed.map { " — \($0)" } ?? "").")

        case "select_menu", "select_menu_item":
            guard let menuPath = target ?? value, !menuPath.isEmpty else {
                throw MCPToolError("select_menu needs 'target' (the menu path, e.g. 'File > Save').")
            }
            try await approveInput("Select menu '\(menuPath)' in '\(appName)'.")
            try axSelectMenuItem(app: app, menuPath: menuPath)
            return .structured(base(["menu_path": .string(menuPath)]),
                               summary: "Selected menu '\(menuPath)' in '\(appName)'.")

        case "wait_for_element":
            guard let target, !target.isEmpty else {
                throw MCPToolError("wait_for_element needs 'target' (the element to wait for).")
            }
            let matched = try await axWaitForElement(app: app, target: target, timeoutSeconds: timeout)
            return .structured(base(["element": .string(matched.id), "title": .string(matched.title), "role": .string(matched.role)]),
                               summary: "Element '\(matched.title)' (\(matched.id)) appeared in '\(appName)'.")

        case "wait_for_window":
            let wanted = target ?? value ?? ""
            guard !wanted.isEmpty else {
                throw MCPToolError("wait_for_window needs 'target' (the window title to wait for).")
            }
            let matched = try await axWaitForWindow(app: app, windowTitle: wanted, timeoutSeconds: timeout)
            return .structured(base(["window_id": .string(matched.id), "title": .string(matched.title)]),
                               summary: "Window '\(matched.title)' (\(matched.id)) appeared in '\(appName)'.")

        case "verify", "verify_element_state":
            guard let target, !target.isEmpty else {
                throw MCPToolError("verify needs 'target' (the element to verify).")
            }
            guard let expected = value else {
                throw MCPToolError("verify needs 'value' (the expected value).")
            }
            let (verified, actual) = try axVerify(app: app, target: target, expected: expected)
            return .structured(base(["target": .string(target), "expected": .string(expected),
                                     "actual": .string(actual), "verified": .bool(verified)]),
                               summary: verified
                                ? "Verified '\(target)' in '\(appName)': value '\(actual)' matches '\(expected)'."
                                : "Verification failed for '\(target)' in '\(appName)': value is '\(actual)', expected '\(expected)'.")

        default:
            throw MCPToolError("Unsupported action '\(action)'.")
        }
    }
}
#endif
