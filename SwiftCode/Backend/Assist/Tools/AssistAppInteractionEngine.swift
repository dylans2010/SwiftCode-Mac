import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistAppInteraction")

// MARK: - Geometry & Normalization Types

public struct AccessibleRect: Sendable, Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(cgRect: CGRect) {
        self.x = Double(cgRect.origin.x)
        self.y = Double(cgRect.origin.y)
        self.width = Double(cgRect.size.width)
        self.height = Double(cgRect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var center: CGPoint {
        CGPoint(x: x + width / 2.0, y: y + height / 2.0)
    }
}

public struct AccessibleUIElementDescriptor: Sendable, Codable, Identifiable {
    public let id: String
    public let role: String
    public let subrole: String
    public let title: String
    public let label: String
    public let identifier: String
    public let value: String
    public let frame: AccessibleRect
    public let windowFrame: AccessibleRect?
    public let isEnabled: Bool
    public let isFocused: Bool
    public let isSelected: Bool
    public let actions: [String]
    public let parentRole: String
    public let childrenCount: Int
    public let timestamp: Date

    public init(
        id: String,
        role: String,
        subrole: String = "",
        title: String = "",
        label: String = "",
        identifier: String = "",
        value: String = "",
        frame: AccessibleRect = AccessibleRect(x: 0, y: 0, width: 0, height: 0),
        windowFrame: AccessibleRect? = nil,
        isEnabled: Bool = true,
        isFocused: Bool = false,
        isSelected: Bool = false,
        actions: [String] = [],
        parentRole: String = "",
        childrenCount: Int = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.subrole = subrole
        self.title = title
        self.label = label
        self.identifier = identifier
        self.value = value
        self.frame = frame
        self.windowFrame = windowFrame
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.isSelected = isSelected
        self.actions = actions
        self.parentRole = parentRole
        self.childrenCount = childrenCount
        self.timestamp = timestamp
    }

    /// Primary display description for humans and AI models
    public var displayDescription: String {
        var parts: [String] = ["[\(role)]"]
        let effectiveTitle = !title.isEmpty ? title : label
        if !effectiveTitle.isEmpty { parts.append("\"\(effectiveTitle)\"") }
        if !identifier.isEmpty { parts.append("(id: \(identifier))") }
        if !value.isEmpty { parts.append("val: '\(value)'") }
        if isFocused { parts.append("[FOCUSED]") }
        if isSelected { parts.append("[SELECTED]") }
        if !isEnabled { parts.append("[DISABLED]") }
        if frame.width > 0 && frame.height > 0 {
            parts.append("@(\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height)))")
        }
        if !actions.isEmpty {
            parts.append("actions: [\(actions.joined(separator: ", "))]")
        }
        return parts.joined(separator: " ")
    }
}

public struct AppWindowInfo: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let frame: AccessibleRect
    public let isMain: Bool
    public let isMinimized: Bool
    public let layer: Int

    public init(id: String, title: String, frame: AccessibleRect, isMain: Bool, isMinimized: Bool, layer: Int = 0) {
        self.id = id
        self.title = title
        self.frame = frame
        self.isMain = isMain
        self.isMinimized = isMinimized
        self.layer = layer
    }
}

public struct DiscoveredAppInfo: Sendable, Codable, Identifiable {
    public var id: String { bundleIdentifier.isEmpty ? name : bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public let bundleURL: String
    public let isRunning: Bool
    public let pid: Int32?
}

// MARK: - Capability Reporting

public enum CapabilitySupportStatus: String, Sendable, Codable {
    case supported
    case partiallySupported = "partially_supported"
    case unavailable
    case permissionDenied = "permission_denied"
    case notTested = "not_tested"
}

public struct AppCapabilityReport: Sendable, Codable {
    public let appIdentifier: String
    public var discoveryStatus: CapabilitySupportStatus
    public var windowEnumerationStatus: CapabilitySupportStatus
    public var accessibilityStatus: CapabilitySupportStatus
    public var pointerInputStatus: CapabilitySupportStatus
    public var keyboardInputStatus: CapabilitySupportStatus
    public var screenshotCaptureStatus: CapabilitySupportStatus
    public var menuNavigationStatus: CapabilitySupportStatus

    public init(
        appIdentifier: String,
        discoveryStatus: CapabilitySupportStatus = .supported,
        windowEnumerationStatus: CapabilitySupportStatus = .notTested,
        accessibilityStatus: CapabilitySupportStatus = .notTested,
        pointerInputStatus: CapabilitySupportStatus = .notTested,
        keyboardInputStatus: CapabilitySupportStatus = .notTested,
        screenshotCaptureStatus: CapabilitySupportStatus = .notTested,
        menuNavigationStatus: CapabilitySupportStatus = .notTested
    ) {
        self.appIdentifier = appIdentifier
        self.discoveryStatus = discoveryStatus
        self.windowEnumerationStatus = windowEnumerationStatus
        self.accessibilityStatus = accessibilityStatus
        self.pointerInputStatus = pointerInputStatus
        self.keyboardInputStatus = keyboardInputStatus
        self.screenshotCaptureStatus = screenshotCaptureStatus
        self.menuNavigationStatus = menuNavigationStatus
    }
}

// MARK: - Structured Error Taxonomy

public enum AppInteractionError: Error, LocalizedError, Sendable {
    case applicationNotFound(String)
    case applicationLaunchFailed(String)
    case applicationTerminated(String)
    case windowNotFound(String)
    case windowAmbiguous(String)
    case accessibilityPermissionDenied(String)
    case screenCapturePermissionDenied(String)
    case automationNotAuthorized(String)
    case targetNotFound(String)
    case targetAmbiguous(String)
    case targetStale(String)
    case elementDisabled(String)
    case actionUnsupported(String)
    case inputDeliveryFailed(String)
    case focusChanged(String)
    case stateVerificationFailed(String)
    case operationTimeout(String)
    case operationCancelled(String)
    case applicationUnresponsive(String)
    case captureUnavailable(String)
    case unsupportedInterface(String)
    case userInterventionRequired(String)
    case destructiveActionConfirmationRequired(String)
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .applicationNotFound(let msg): return "Application not found: \(msg)"
        case .applicationLaunchFailed(let msg): return "Application launch failed: \(msg)"
        case .applicationTerminated(let msg): return "Application terminated: \(msg)"
        case .windowNotFound(let msg): return "Window not found: \(msg)"
        case .windowAmbiguous(let msg): return "Ambiguous window target: \(msg)"
        case .accessibilityPermissionDenied(let msg): return "Accessibility permission required: \(msg)"
        case .screenCapturePermissionDenied(let msg): return "Screen capture permission required: \(msg)"
        case .automationNotAuthorized(let msg): return "Automation not authorized: \(msg)"
        case .targetNotFound(let msg): return "UI target not found: \(msg)"
        case .targetAmbiguous(let msg): return "Ambiguous UI target: \(msg)"
        case .targetStale(let msg): return "Target element is stale: \(msg)"
        case .elementDisabled(let msg): return "UI element is disabled: \(msg)"
        case .actionUnsupported(let msg): return "Action unsupported on element: \(msg)"
        case .inputDeliveryFailed(let msg): return "Input event delivery failed: \(msg)"
        case .focusChanged(let msg): return "Focus changed unexpectedly: \(msg)"
        case .stateVerificationFailed(let msg): return "State verification failed: \(msg)"
        case .operationTimeout(let msg): return "Operation timed out: \(msg)"
        case .operationCancelled(let msg): return "Operation cancelled: \(msg)"
        case .applicationUnresponsive(let msg): return "Application unresponsive: \(msg)"
        case .captureUnavailable(let msg): return "Visual capture unavailable: \(msg)"
        case .unsupportedInterface(let msg): return "Interface not supported: \(msg)"
        case .userInterventionRequired(let msg): return "User intervention required: \(msg)"
        case .destructiveActionConfirmationRequired(let msg): return "Consequential action requires explicit confirmation: \(msg)"
        case .internalError(let msg): return "Internal interaction error: \(msg)"
        }
    }

    /// Maps to standard Assist tool error code
    public var assistErrorCode: AssistToolErrorCode {
        switch self {
        case .applicationNotFound, .windowNotFound, .targetNotFound:
            return .notFound
        case .accessibilityPermissionDenied, .screenCapturePermissionDenied, .automationNotAuthorized:
            return .permissionDenied
        case .destructiveActionConfirmationRequired:
            return .permissionDenied
        case .operationTimeout:
            return .timeout
        case .operationCancelled:
            return .cancelled
        case .targetAmbiguous, .windowAmbiguous, .elementDisabled:
            return .invalidInput
        case .actionUnsupported, .unsupportedInterface:
            return .unsupportedOperation
        case .applicationLaunchFailed, .applicationTerminated, .inputDeliveryFailed, .stateVerificationFailed, .applicationUnresponsive, .captureUnavailable, .focusChanged, .targetStale:
            return .executionFailed
        case .userInterventionRequired:
            return .unknown
        case .internalError:
            return .unknown
        }
    }

    /// Actionable sentence telling the model how to recover
    public var recoveryHint: String {
        switch self {
        case .accessibilityPermissionDenied:
            return "Enable SwiftCode in macOS System Settings > Privacy & Security > Accessibility, then retry."
        case .screenCapturePermissionDenied:
            return "Enable SwiftCode in macOS System Settings > Privacy & Security > Screen Recording, then retry."
        case .applicationNotFound:
            return "Call action 'list_applications' to find the exact installed bundle identifier or app name."
        case .windowNotFound:
            return "Call action 'list_windows' to inspect currently open windows, or 'activate' the application."
        case .targetNotFound:
            return "Call action 'inspect_ui' or 'take_screenshot' to examine the current interface and update the target descriptor."
        case .targetAmbiguous:
            return "Narrow your target by specifying an exact element ID (e.g. 'elem_1') or unique label from 'inspect_ui'."
        case .targetStale:
            return "The interface changed. Run action 'inspect_ui' to refresh UI references before retrying."
        case .elementDisabled:
            return "The target control is currently disabled. Check prerequisite fields or selections in the application."
        case .actionUnsupported:
            return "This control does not support that semantic action. Try coordinate-based click or keypress."
        case .inputDeliveryFailed:
            return "Verify the target application is frontmost by calling 'activate', then re-issue the input."
        case .focusChanged:
            return "Call 'activate' and 'select_window' to restore target window focus before interacting."
        case .stateVerificationFailed:
            return "Inspect current UI with 'inspect_ui' or 'take_screenshot' to determine actual application state."
        case .operationTimeout:
            return "The operation exceeded its timeout. Call 'inspect_ui' to verify if the transition completed."
        case .destructiveActionConfirmationRequired:
            return "This consequential action requires 'confirm: true' parameter. Request confirmation before continuing."
        case .userInterventionRequired:
            return "A dialog (such as authentication or system authorization) requires manual user input."
        default:
            return assistErrorCode.recoveryHint
        }
    }
}

// MARK: - Application Session Management

public final class AppSession: @unchecked Sendable {
    public let sessionId: String
    public let appIdentifier: String
    public var bundleIdentifier: String
    public var pid: pid_t
    public var appURL: URL?
    public var runningApp: NSRunningApplication?

    public var selectedWindowId: String?
    public var windows: [AppWindowInfo] = []

    public var elementDescriptors: [String: AccessibleUIElementDescriptor] = [:]
    public var elementAXReferences: [String: AXUIElement] = [:]

    public var lastScreenshotArtifact: String?
    public var lastScreenshotBase64: String?
    public var lastScreenshotTimestamp: Date?

    public var capabilities: AppCapabilityReport
    public let createdAt: Date
    public var updatedAt: Date

    private let lock = NSLock()

    public init(
        sessionId: String = UUID().uuidString,
        appIdentifier: String,
        bundleIdentifier: String,
        pid: pid_t,
        appURL: URL? = nil,
        runningApp: NSRunningApplication? = nil
    ) {
        self.sessionId = sessionId
        self.appIdentifier = appIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.appURL = appURL
        self.runningApp = runningApp
        self.capabilities = AppCapabilityReport(appIdentifier: bundleIdentifier)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block()
    }

    public func updateTimestamp() {
        withLock {
            self.updatedAt = Date()
        }
    }

    public func registerElements(_ descriptors: [AccessibleUIElementDescriptor], references: [String: AXUIElement]) {
        withLock {
            self.elementDescriptors = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
            self.elementAXReferences = references
            self.updatedAt = Date()
        }
    }

    public func clearElements() {
        withLock {
            self.elementDescriptors.removeAll()
            self.elementAXReferences.removeAll()
            self.updatedAt = Date()
        }
    }

    public func getElementReference(for id: String) -> AXUIElement? {
        withLock {
            self.elementAXReferences[id]
        }
    }

    public func getElementDescriptor(for id: String) -> AccessibleUIElementDescriptor? {
        withLock {
            self.elementDescriptors[id]
        }
    }
}

public final class AssistAppSessionManager: @unchecked Sendable {
    public static let shared = AssistAppSessionManager()

    private var sessions: [String: AppSession] = [:]
    private var appToSessionId: [String: String] = [:]
    private let lock = NSLock()

    private init() {}

    public func getOrCreateSession(for app: NSRunningApplication) -> AppSession {
        lock.lock()
        defer { lock.unlock() }

        let bundleId = app.bundleIdentifier ?? "\(app.processIdentifier)"
        if let existingId = appToSessionId[bundleId], let session = sessions[existingId] {
            session.runningApp = app
            session.pid = app.processIdentifier
            session.updateTimestamp()
            return session
        }

        let newSession = AppSession(
            sessionId: "app_session_\(UUID().uuidString.prefix(8).lowercased())",
            appIdentifier: bundleId,
            bundleIdentifier: bundleId,
            pid: app.processIdentifier,
            appURL: app.bundleURL,
            runningApp: app
        )
        sessions[newSession.sessionId] = newSession
        appToSessionId[bundleId] = newSession.sessionId
        return newSession
    }

    public func getSession(byIdentifier id: String) -> AppSession? {
        lock.lock()
        defer { lock.unlock() }

        if let direct = sessions[id] {
            return direct
        }
        if let sessionId = appToSessionId[id], let direct = sessions[sessionId] {
            return direct
        }
        return sessions.values.first {
            $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame ||
            $0.appIdentifier.caseInsensitiveCompare(id) == .orderedSame ||
            "\($0.pid)" == id
        }
    }

    public func terminateSession(id: String) {
        lock.lock()
        defer { lock.unlock() }

        if let session = sessions.removeValue(forKey: id) {
            appToSessionId.removeValue(forKey: session.bundleIdentifier)
        }
    }

    public func cleanStaleSessions(maxAge: TimeInterval = 3600) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let staleIds = sessions.filter { now.timeIntervalSince($0.value.updatedAt) > maxAge }.map { $0.key }
        for sid in staleIds {
            if let sess = sessions.removeValue(forKey: sid) {
                appToSessionId.removeValue(forKey: sess.bundleIdentifier)
            }
        }
    }
}

// MARK: - Central Application Interaction Engine

@MainActor
public final class AssistAppInteractionEngine: Sendable {
    public static let shared = AssistAppInteractionEngine()

    private init() {}

    // MARK: - Permissions Preflight

    public func checkAccessibilityAuthorization(promptIfDenied: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: promptIfDenied] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func checkScreenCaptureAuthorization(promptIfDenied: Bool = false) -> Bool {
        return AssistScreenCaptureEngine.shared.checkAuthorization(promptIfDenied: promptIfDenied)
    }

    // MARK: - Application Discovery & Resolution

    public func listApplications(filter: String? = nil) -> [DiscoveredAppInfo] {
        var results: [DiscoveredAppInfo] = []
        var seenBundleIDs: Set<String> = []

        // Running applications first
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard let name = app.localizedName, !name.isEmpty else { continue }
            let bundleId = app.bundleIdentifier ?? ""
            let bundleURL = app.bundleURL?.path ?? ""
            if !bundleId.isEmpty { seenBundleIDs.insert(bundleId) }

            if let filter = filter, !filter.isEmpty {
                let matches = name.localizedCaseInsensitiveContains(filter) || bundleId.localizedCaseInsensitiveContains(filter)
                guard matches else { continue }
            }

            results.append(DiscoveredAppInfo(
                name: name,
                bundleIdentifier: bundleId,
                bundleURL: bundleURL,
                isRunning: true,
                pid: app.processIdentifier
            ))
        }

        // Search standard application paths
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSString(string: "~/Applications").expandingTildeInPath
        ]

        let fm = FileManager.default
        for dir in appDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let fullPath = (dir as NSString).appendingPathComponent(entry)
                guard let bundle = Bundle(path: fullPath) else { continue }
                let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                           (entry as NSString).deletingPathExtension
                let bundleId = bundle.bundleIdentifier ?? ""

                if !bundleId.isEmpty && seenBundleIDs.contains(bundleId) {
                    continue
                }
                if !bundleId.isEmpty { seenBundleIDs.insert(bundleId) }

                if let filter = filter, !filter.isEmpty {
                    let matches = name.localizedCaseInsensitiveContains(filter) || bundleId.localizedCaseInsensitiveContains(filter)
                    guard matches else { continue }
                }

                results.append(DiscoveredAppInfo(
                    name: name,
                    bundleIdentifier: bundleId,
                    bundleURL: fullPath,
                    isRunning: false,
                    pid: nil
                ))
            }
        }

        return results.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning && !$1.isRunning }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func resolveOrLaunchApp(appIdentifier: String, autoLaunch: Bool = true) async throws -> NSRunningApplication {
        let trimmed = appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppInteractionError.applicationNotFound("Empty application identifier.")
        }

        // 1. Check session manager
        if let session = AssistAppSessionManager.shared.getSession(byIdentifier: trimmed),
           let running = session.runningApp, !running.isTerminated {
            return running
        }

        // 2. Check running applications by PID, bundle identifier, or name
        let runningApps = NSWorkspace.shared.runningApplications
        if let pid = Int32(trimmed), let running = runningApps.first(where: { $0.processIdentifier == pid }) {
            return running
        }

        if let running = runningApps.first(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(trimmed) == .orderedSame ||
            $0.localizedName?.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return running
        }

        guard autoLaunch else {
            throw AppInteractionError.applicationNotFound("Application '\(trimmed)' is not running.")
        }

        // 3. Locate application URL via LaunchServices
        var targetURL: URL?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            targetURL = url
        } else {
            // Search standard folders
            let candidates = listApplications(filter: trimmed)
            if let matched = candidates.first(where: {
                $0.bundleIdentifier.caseInsensitiveCompare(trimmed) == .orderedSame ||
                $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }), !matched.bundleURL.isEmpty {
                targetURL = URL(fileURLWithPath: matched.bundleURL)
            } else if candidates.count > 1 {
                let candidateList = candidates.prefix(5).map { "\($0.name) (\($0.bundleIdentifier))" }.joined(separator: ", ")
                throw AppInteractionError.targetAmbiguous("Multiple applications match '\(trimmed)': \(candidateList). Please specify the exact bundle identifier.")
            } else if let first = candidates.first, !first.bundleURL.isEmpty {
                targetURL = URL(fileURLWithPath: first.bundleURL)
            }
        }

        guard let appURL = targetURL else {
            throw AppInteractionError.applicationNotFound("Could not locate installed application bundle for '\(trimmed)'.")
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        do {
            let launchedApp = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            // Bounded wait for launch completion (up to 4.0 seconds)
            for _ in 0..<40 {
                if launchedApp.isFinishedLaunching { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return launchedApp
        } catch {
            throw AppInteractionError.applicationLaunchFailed("Failed to launch '\(appURL.path)': \(error.localizedDescription)")
        }
    }

    public func activateApp(appIdentifier: String) async throws -> NSRunningApplication {
        let app = try await resolveOrLaunchApp(appIdentifier: appIdentifier, autoLaunch: true)
        app.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 150_000_000)
        return app
    }

    // MARK: - Window Management

    public func listWindows(for app: NSRunningApplication) -> [AppWindowInfo] {
        var results: [AppWindowInfo] = []
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return results
        }

        for (idx, window) in windows.enumerated() {
            let title = copyStringAttribute(element: window, attribute: kAXTitleAttribute) ?? ""
            let isMain = copyBoolAttribute(element: window, attribute: kAXMainAttribute) ?? (idx == 0)
            let isMinimized = copyBoolAttribute(element: window, attribute: kAXMinimizedAttribute) ?? false
            let frame = copyElementFrame(element: window) ?? AccessibleRect(x: 0, y: 0, width: 0, height: 0)

            let winId = "window_\(idx + 1)"
            results.append(AppWindowInfo(
                id: winId,
                title: title.isEmpty ? "Untitled Window \(idx + 1)" : title,
                frame: frame,
                isMain: isMain,
                isMinimized: isMinimized,
                layer: idx
            ))
        }

        return results
    }

    public func selectWindow(app: NSRunningApplication, windowId: String) throws -> AppWindowInfo {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            throw AppInteractionError.windowNotFound("No accessible windows found for application '\(app.localizedName ?? "")'.")
        }

        let windowsList = listWindows(for: app)
        var targetIndex: Int?

        if let directIndex = windowsList.firstIndex(where: {
            $0.id.caseInsensitiveCompare(windowId) == .orderedSame ||
            $0.title.localizedCaseInsensitiveContains(windowId)
        }) {
            targetIndex = directIndex
        } else if let num = Int(windowId.replacingOccurrences(of: "window_", with: "")), num > 0 && num <= windows.count {
            targetIndex = num - 1
        }

        guard let idx = targetIndex, idx < windows.count else {
            throw AppInteractionError.windowNotFound("Window matching '\(windowId)' was not found.")
        }

        let targetWindow = windows[idx]
        _ = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)

        let session = AssistAppSessionManager.shared.getOrCreateSession(for: app)
        session.selectedWindowId = windowsList[idx].id
        return windowsList[idx]
    }

    // MARK: - UI Inspection & Accessibility Hierarchy

    public func inspectUI(
        app: NSRunningApplication,
        maxElements: Int = 100,
        targetWindowId: String? = nil
    ) -> (elements: [AccessibleUIElementDescriptor], session: AppSession) {
        let session = AssistAppSessionManager.shared.getOrCreateSession(for: app)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            session.clearElements()
            return ([], session)
        }

        var descriptors: [AccessibleUIElementDescriptor] = []
        var references: [String: AXUIElement] = [:]
        var counter = 1

        let targetWindows: [AXUIElement]
        if let wid = targetWindowId ?? session.selectedWindowId,
           let idx = listWindows(for: app).firstIndex(where: { $0.id == wid }), idx < windows.count {
            targetWindows = [windows[idx]]
        } else {
            targetWindows = [windows[0]] // active / main window first
        }

        for window in targetWindows {
            let winFrame = copyElementFrame(element: window)
            collectElements(
                element: window,
                windowFrame: winFrame,
                descriptors: &descriptors,
                references: &references,
                counter: &counter,
                maxCount: maxElements,
                currentDepth: 0,
                maxDepth: 10
            )
            if descriptors.count >= maxElements { break }
        }

        session.registerElements(descriptors, references: references)
        session.windows = listWindows(for: app)
        return (descriptors, session)
    }

    private func collectElements(
        element: AXUIElement,
        windowFrame: AccessibleRect?,
        descriptors: inout [AccessibleUIElementDescriptor],
        references: inout [String: AXUIElement],
        counter: inout Int,
        maxCount: Int,
        currentDepth: Int,
        maxDepth: Int
    ) {
        guard currentDepth <= maxDepth && descriptors.count < maxCount else { return }

        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute) ?? "Unknown"
        let subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute) ?? ""
        let title = copyStringAttribute(element: element, attribute: kAXTitleAttribute) ?? ""
        let label = copyStringAttribute(element: element, attribute: kAXDescriptionAttribute) ?? ""
        let identifier = copyStringAttribute(element: element, attribute: kAXIdentifierAttribute) ?? ""
        let value = copyStringAttribute(element: element, attribute: kAXValueAttribute) ?? ""
        let isEnabled = copyBoolAttribute(element: element, attribute: kAXEnabledAttribute) ?? true
        let isFocused = copyBoolAttribute(element: element, attribute: kAXFocusedAttribute) ?? false
        let isSelected = copyBoolAttribute(element: element, attribute: kAXSelectedAttribute) ?? false
        let frame = copyElementFrame(element: element) ?? AccessibleRect(x: 0, y: 0, width: 0, height: 0)

        var actions: [String] = []
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success, let actList = actionsRef as? [String] {
            actions = actList
        }

        // Actionable roles filter
        let actionableRoles: Set<String> = [
            "AXButton", "AXTextField", "AXTextArea", "AXPopUpButton", "AXMenuButton",
            "AXCheckBox", "AXRadioButton", "AXTab", "AXSlider", "AXMenuItem",
            "AXComboBox", "AXWindow", "AXLink", "AXOutline", "AXTable", "AXRow",
            "AXCell", "AXStaticText", "AXImage", "AXSheet", "AXDialog", "AXAlert"
        ]

        let isInteractive = actionableRoles.contains(role) || !title.isEmpty || !label.isEmpty || !identifier.isEmpty
        if isInteractive && currentDepth > 0 {
            let elemId = "elem_\(counter)"
            counter += 1

            let desc = AccessibleUIElementDescriptor(
                id: elemId,
                role: role,
                subrole: subrole,
                title: title,
                label: label,
                identifier: identifier,
                value: value,
                frame: frame,
                windowFrame: windowFrame,
                isEnabled: isEnabled,
                isFocused: isFocused,
                isSelected: isSelected,
                actions: actions,
                parentRole: "",
                childrenCount: 0,
                timestamp: Date()
            )
            descriptors.append(desc)
            references[elemId] = element
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectElements(
                    element: child,
                    windowFrame: windowFrame,
                    descriptors: &descriptors,
                    references: &references,
                    counter: &counter,
                    maxCount: maxCount,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth
                )
                if descriptors.count >= maxCount { break }
            }
        }
    }

    // MARK: - Target Resolution

    public func resolveElement(
        app: NSRunningApplication,
        target: String,
        session: AppSession? = nil
    ) throws -> (element: AXUIElement, descriptor: AccessibleUIElementDescriptor?) {
        let activeSession = session ?? AssistAppSessionManager.shared.getOrCreateSession(for: app)
        let query = target.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Direct session-local element ID lookup (e.g. "elem_4")
        if let ref = activeSession.getElementReference(for: query) {
            return (ref, activeSession.getElementDescriptor(for: query))
        }

        // 2. Search cached descriptors in session
        let descriptors = Array(activeSession.elementDescriptors.values)
        if let match = descriptors.first(where: {
            $0.identifier.caseInsensitiveCompare(query) == .orderedSame ||
            $0.title.caseInsensitiveCompare(query) == .orderedSame ||
            $0.label.caseInsensitiveCompare(query) == .orderedSame
        }), let ref = activeSession.getElementReference(for: match.id) {
            return (ref, match)
        }

        // 3. Substring matching in cached descriptors
        let substringMatches = descriptors.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.label.localizedCaseInsensitiveContains(query) ||
            $0.identifier.localizedCaseInsensitiveContains(query)
        }
        if substringMatches.count == 1, let ref = activeSession.getElementReference(for: substringMatches[0].id) {
            return (ref, substringMatches[0])
        } else if substringMatches.count > 1 {
            let candidates = substringMatches.prefix(4).map { "\($0.id): [\($0.role)] '\($0.title)'" }.joined(separator: ", ")
            throw AppInteractionError.targetAmbiguous("Target '\(query)' matches multiple controls: \(candidates). Specify the exact element ID (e.g. '\(substringMatches[0].id)').")
        }

        // 4. Live recursive search in active window
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw AppInteractionError.targetNotFound("No accessible windows found for target search '\(query)'.")
        }

        for window in windows {
            if let liveMatch = searchLiveElement(element: window, query: query.lowercased(), depth: 0, maxDepth: 10) {
                return (liveMatch, nil)
            }
        }

        throw AppInteractionError.targetNotFound("UI element matching '\(query)' was not found in application '\(app.localizedName ?? "")'. Use action 'inspect_ui' to examine the visible hierarchy.")
    }

    private func searchLiveElement(element: AXUIElement, query: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth <= maxDepth else { return nil }

        let title = (copyStringAttribute(element: element, attribute: kAXTitleAttribute) ?? "").lowercased()
        let identifier = (copyStringAttribute(element: element, attribute: kAXIdentifierAttribute) ?? "").lowercased()
        let label = (copyStringAttribute(element: element, attribute: kAXDescriptionAttribute) ?? "").lowercased()
        let role = (copyStringAttribute(element: element, attribute: kAXRoleAttribute) ?? "").lowercased()

        if title == query || identifier == query || label == query {
            return element
        }
        if !query.isEmpty && (title.contains(query) || identifier.contains(query) || label.contains(query) || "\(role):\(title)".contains(query)) {
            return element
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = searchLiveElement(element: child, query: query, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: - Semantic Actions

    public func performSemanticAction(
        app: NSRunningApplication,
        target: String,
        actionName: String,
        value: String? = nil,
        shouldVerify: Bool = true
    ) async throws -> (success: Bool, verified: Bool, observedChange: String?) {
        let (element, _) = try resolveElement(app: app, target: target)
        let normalizedAction = actionName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var actionDispatched = false
        switch normalizedAction {
        case "click", "press", "activate":
            if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                actionDispatched = true
            } else if AXUIElementPerformAction(element, "AXPick" as CFString) == .success {
                actionDispatched = true
            }

        case "set_value", "type_text":
            guard let val = value else {
                throw AppInteractionError.actionUnsupported("Action '\(actionName)' requires parameter 'value'.")
            }
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, val as CFTypeRef) == .success {
                actionDispatched = true
            }

        case "focus":
            actionDispatched = (AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success)

        case "select":
            actionDispatched = (AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success)

        case "expand":
            actionDispatched = (AXUIElementSetAttributeValue(element, "AXDisclosing" as CFString, kCFBooleanTrue) == .success)

        case "collapse":
            actionDispatched = (AXUIElementSetAttributeValue(element, "AXDisclosing" as CFString, kCFBooleanFalse) == .success)

        default:
            actionDispatched = (AXUIElementPerformAction(element, actionName as CFString) == .success)
        }

        guard actionDispatched else {
            throw AppInteractionError.inputDeliveryFailed("Semantic action '\(actionName)' was rejected by target control '\(target)'.")
        }

        var isVerified = false
        var stateChange: String? = nil
        if shouldVerify {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let newValue = copyStringAttribute(element: element, attribute: kAXValueAttribute) {
                stateChange = "Value is now '\(newValue)'"
                isVerified = true
            } else {
                isVerified = true
            }
        }

        return (true, isVerified, stateChange)
    }

    // MARK: - Native Menu Navigation

    public func selectMenuItem(app: NSRunningApplication, menuPath: String) throws -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            throw AppInteractionError.actionUnsupported("Application '\(app.localizedName ?? "")' does not expose a standard accessible menu bar.")
        }

        let components = menuPath.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !components.isEmpty else {
            throw AppInteractionError.targetNotFound("Menu path cannot be empty.")
        }

        guard navigateAndPressMenu(currentElement: menuBar as! AXUIElement, components: components) else {
            throw AppInteractionError.targetNotFound("Menu item '\(menuPath)' could not be triggered or was disabled.")
        }
        return true
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
                    let enabled = copyBoolAttribute(element: child, attribute: kAXEnabledAttribute) ?? true
                    guard enabled else { return false }
                    return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
                } else {
                    return navigateAndPressMenu(currentElement: child, components: Array(components.dropFirst()))
                }
            }
        }
        return false
    }

    // MARK: - Pointer Interaction & Synthetic Events

    public func click(
        app: NSRunningApplication,
        target: String? = nil,
        coordinates: CGPoint? = nil,
        coordinateSpace: String = "screen",
        button: String = "left",
        clickCount: Int = 1,
        shouldVerify: Bool = true
    ) async throws -> (success: Bool, clickedPoint: CGPoint, verified: Bool) {
        let targetPoint: CGPoint
        if let target = target, !target.isEmpty {
            let (element, desc) = try resolveElement(app: app, target: target)
            if let desc = desc, desc.frame.width > 0 {
                targetPoint = desc.frame.center
            } else if let frame = copyElementFrame(element: element) {
                targetPoint = frame.center
            } else {
                throw AppInteractionError.targetNotFound("Cannot determine coordinates for target '\(target)'.")
            }
        } else if let coords = coordinates {
            targetPoint = convertToScreenCoordinates(point: coords, space: coordinateSpace, app: app)
        } else {
            throw AppInteractionError.targetNotFound("Action requires either 'target' UI element or 'coordinates'.")
        }

        // Post synthetic mouse click
        let mouseTypeDown: CGEventType = (button.lowercased() == "right") ? .rightMouseDown : .leftMouseDown
        let mouseTypeUp: CGEventType = (button.lowercased() == "right") ? .rightMouseUp : .leftMouseUp
        let mouseButton: CGMouseButton = (button.lowercased() == "right") ? .right : .left

        // Move first
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: targetPoint, mouseButton: .left) else {
            throw AppInteractionError.inputDeliveryFailed("Failed to create mouse move event.")
        }
        moveEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Mouse Down & Up
        guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: mouseTypeDown, mouseCursorPosition: targetPoint, mouseButton: mouseButton),
              let upEvent = CGEvent(mouseEventSource: nil, mouseType: mouseTypeUp, mouseCursorPosition: targetPoint, mouseButton: mouseButton) else {
            throw AppInteractionError.inputDeliveryFailed("Failed to create mouse click events.")
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

        if shouldVerify {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        return (true, targetPoint, shouldVerify)
    }

    public func drag(
        app: NSRunningApplication,
        from: CGPoint,
        to: CGPoint,
        coordinateSpace: String = "screen"
    ) async throws -> Bool {
        let startPt = convertToScreenCoordinates(point: from, space: coordinateSpace, app: app)
        let endPt = convertToScreenCoordinates(point: to, space: coordinateSpace, app: app)

        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: startPt, mouseButton: .left),
              let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: startPt, mouseButton: .left),
              let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: endPt, mouseButton: .left),
              let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: endPt, mouseButton: .left) else {
            throw AppInteractionError.inputDeliveryFailed("Failed to generate drag events.")
        }

        moveEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 40_000_000)
        downEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        dragEvent.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        upEvent.post(tap: .cghidEventTap)
        return true
    }

    public func scroll(
        app: NSRunningApplication,
        coordinates: CGPoint? = nil,
        coordinateSpace: String = "screen",
        dx: Int = 0,
        dy: Int = 0
    ) async throws -> Bool {
        if let pt = coordinates {
            let screenPt = convertToScreenCoordinates(point: pt, space: coordinateSpace, app: app)
            if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: screenPt, mouseButton: .left) {
                move.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else {
            throw AppInteractionError.inputDeliveryFailed("Failed to generate scroll event.")
        }
        scrollEvent.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Keyboard Input & Shortcuts

    public func typeText(
        app: NSRunningApplication,
        target: String? = nil,
        text: String,
        useClipboard: Bool = false
    ) async throws -> Bool {
        // Activate target control if specified
        if let target = target, !target.isEmpty {
            _ = try? await performSemanticAction(app: app, target: target, actionName: "focus")
        }

        if useClipboard && text.count > 100 {
            // Safe clipboard-assisted input
            let pasteboard = NSPasteboard.general
            let priorContent = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            // Trigger Cmd+V
            try await pressShortcut(app: app, shortcut: "Cmd+V")

            // Wait briefly and restore prior clipboard
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let prior = priorContent {
                pasteboard.clearContents()
                pasteboard.setString(prior, forType: .string)
            }
            return true
        }

        // Direct synthetic Unicode text injection
        let utf16 = Array(text.utf16)
        for char in utf16 {
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
        return true
    }

    public func pressKey(
        app: NSRunningApplication,
        keyName: String,
        modifiers: [String] = []
    ) async throws -> Bool {
        let (keyCode, defaultMods) = resolveKeyCode(for: keyName)
        let flags = resolveModifierFlags(modifiers: modifiers.isEmpty ? defaultMods : modifiers)

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw AppInteractionError.inputDeliveryFailed("Failed to create keyboard events for key '\(keyName)'.")
        }

        if !flags.isEmpty {
            keyDown.flags = flags
            keyUp.flags = flags
        }

        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 20_000_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    public func pressShortcut(app: NSRunningApplication, shortcut: String) async throws -> Bool {
        // e.g. "Cmd+S", "Command+Shift+P", "Ctrl+C"
        let parts = shortcut.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last else {
            throw AppInteractionError.actionUnsupported("Empty keyboard shortcut.")
        }
        let modifierParts = Array(parts.dropLast())
        return try await pressKey(app: app, keyName: keyPart, modifiers: modifierParts)
    }

    // MARK: - State-Based Waiting & Verification

    public func waitForElement(
        app: NSRunningApplication,
        target: String,
        timeoutSeconds: Double = 5.0
    ) async throws -> AccessibleUIElementDescriptor {
        let maxIterations = Int(timeoutSeconds * 5.0)
        for _ in 0..<max(maxIterations, 1) {
            let (elements, _) = inspectUI(app: app, maxElements: 120)
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
        throw AppInteractionError.operationTimeout("Element matching '\(target)' did not appear within \(timeoutSeconds)s in '\(app.localizedName ?? "")'.")
    }

    public func waitForWindow(
        app: NSRunningApplication,
        windowTitle: String,
        timeoutSeconds: Double = 5.0
    ) async throws -> AppWindowInfo {
        let maxIterations = Int(timeoutSeconds * 5.0)
        for _ in 0..<max(maxIterations, 1) {
            let windows = listWindows(for: app)
            if let matched = windows.first(where: {
                $0.title.localizedCaseInsensitiveContains(windowTitle) ||
                $0.id.caseInsensitiveCompare(windowTitle) == .orderedSame
            }) {
                return matched
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw AppInteractionError.operationTimeout("Window matching '\(windowTitle)' did not appear within \(timeoutSeconds)s.")
    }

    // MARK: - Visual Perception Integration

    public func captureAppScreenshot(
        app: NSRunningApplication,
        windowId: String? = nil,
        context: AssistContext
    ) async throws -> (artifactPath: String, base64: String, rect: AccessibleRect) {
        guard checkScreenCaptureAuthorization(promptIfDenied: true) else {
            throw AppInteractionError.screenCapturePermissionDenied("Screen Recording access is not authorized by the operating system.")
        }

        let windows = listWindows(for: app)
        let targetWindow: AppWindowInfo?
        if let wid = windowId {
            targetWindow = windows.first(where: { $0.id == wid })
        } else {
            targetWindow = windows.first(where: { $0.isMain }) ?? windows.first
        }

        let captureResult = try await AssistScreenCaptureEngine.shared.captureFullScreen()
        var finalData = captureResult.pngData
        var resultRect = AccessibleRect(x: 0, y: 0, width: Double(captureResult.width), height: Double(captureResult.height))

        if let win = targetWindow, win.frame.width > 2 && win.frame.height > 2 {
            // Crop to window bounds
            let mainDisplayID = CGMainDisplayID()
            let dispBounds = CGDisplayBounds(mainDisplayID)
            let scale = CGFloat(captureResult.width) / dispBounds.width

            let cropRect = CGRect(
                x: win.frame.x * Double(scale),
                y: win.frame.y * Double(scale),
                width: win.frame.width * Double(scale),
                height: win.frame.height * Double(scale)
            ).integral

            if let cropped = captureResult.image.cropping(to: cropRect),
               let croppedData = try? AssistScreenCaptureEngine.shared.encodePNG(image: cropped) {
                finalData = croppedData
                resultRect = win.frame
            }
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueName = "app_\(app.localizedName ?? "app")_\(timestamp).png"
        let artifact = try AssistArtifactStore.shared.createBinaryArtifact(
            name: uniqueName,
            data: finalData,
            description: "App screenshot for \(app.localizedName ?? "")",
            kind: .image,
            workspaceRoot: context.workspaceRoot
        )

        let session = AssistAppSessionManager.shared.getOrCreateSession(for: app)
        session.lastScreenshotArtifact = artifact.relativePath
        let b64 = finalData.base64EncodedString()
        session.lastScreenshotBase64 = b64
        session.lastScreenshotTimestamp = Date()

        return (artifact.relativePath, b64, resultRect)
    }

    // MARK: - Helper Methods

    private func convertToScreenCoordinates(point: CGPoint, space: String, app: NSRunningApplication) -> CGPoint {
        switch space.lowercased() {
        case "window":
            if let session = AssistAppSessionManager.shared.getSession(byIdentifier: app.bundleIdentifier ?? ""),
               let wid = session.selectedWindowId,
               let win = session.windows.first(where: { $0.id == wid }) {
                return CGPoint(x: win.frame.x + Double(point.x), y: win.frame.y + Double(point.y))
            }
            return point
        case "screenshot_pixel":
            let mainDisplayID = CGMainDisplayID()
            let dispBounds = CGDisplayBounds(mainDisplayID)
            let scale = (NSScreen.main?.backingScaleFactor) ?? 2.0
            return CGPoint(x: point.x / scale, y: point.y / scale)
        default:
            return point
        }
    }

    private func resolveKeyCode(for keyName: String) -> (CGKeyCode, [String]) {
        switch keyName.lowercased() {
        case "return", "enter": return (36, [])
        case "tab": return (48, [])
        case "space": return (49, [])
        case "delete", "backspace": return (51, [])
        case "escape", "esc": return (53, [])
        case "command", "cmd": return (55, [])
        case "shift": return (56, [])
        case "option", "alt": return (58, [])
        case "control", "ctrl": return (59, [])
        case "left", "leftarrow": return (123, [])
        case "right", "rightarrow": return (124, [])
        case "down", "downarrow": return (125, [])
        case "up", "uparrow": return (126, [])
        case "a": return (0, [])
        case "s": return (1, [])
        case "d": return (2, [])
        case "f": return (3, [])
        case "h": return (4, [])
        case "g": return (5, [])
        case "z": return (6, [])
        case "x": return (7, [])
        case "c": return (8, [])
        case "v": return (9, [])
        case "b": return (11, [])
        case "q": return (12, [])
        case "w": return (13, [])
        case "e": return (14, [])
        case "r": return (15, [])
        case "y": return (16, [])
        case "t": return (17, [])
        case "1": return (18, [])
        case "2": return (19, [])
        case "3": return (20, [])
        case "4": return (21, [])
        case "6": return (22, [])
        case "5": return (23, [])
        case "=": return (24, [])
        case "9": return (25, [])
        case "7": return (26, [])
        case "-": return (27, [])
        case "8": return (28, [])
        case "0": return (29, [])
        default: return (36, [])
        }
    }

    private func resolveModifierFlags(modifiers: [String]) -> CGEventFlags {
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

    private func copyStringAttribute(element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard err == .success, let val = valueRef else { return nil }
        if let str = val as? String {
            return str
        } else if let num = val as? NSNumber {
            return num.stringValue
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

    private func copyElementFrame(element: AXUIElement) -> AccessibleRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        if CFGetTypeID(posVal) == AXValueGetTypeID(), CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            return AccessibleRect(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
        }
        return nil
    }
}
