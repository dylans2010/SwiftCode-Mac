//
//  AppPermsView.swift
//  SwiftCode
//
//  Comprehensive System Permissions & Tool Authorizations Hub.
//  Discovers, displays, and assists users in granting all macOS permissions
//  required for full SwiftCode and Assist operation:
//  - Accessibility (use_app, UI automation)
//  - Screen Recording (take_screenshot, take_screenrecord)
//  - Full Disk Access / Filesystem (file_read, file_write, dir_read, Git operations)
//  - Developer Tools & Execution (use_terminal, project_build, CLI tools)
//  - Automation / Apple Events (open_in_finder, reveal_in_finder, System Events)
//  - Microphone (Assist Voice Assistant prompt)
//  - Speech Recognition (Real-time dictation)
//  - System Notifications (Build/worker alerts)
//

import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices
import ScreenCaptureKit
import AVFoundation
import Speech
import UserNotifications

// MARK: - Permission Model

public struct AppPermissionItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let icon: String
    public let tintColor: Color
    public let toolsReliedUpon: [String]
    public let description: String
    public let systemSettingsURLString: String
    public var isGranted: Bool

    public init(
        id: String,
        name: String,
        category: String,
        icon: String,
        tintColor: Color,
        toolsReliedUpon: [String],
        description: String,
        systemSettingsURLString: String,
        isGranted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.tintColor = tintColor
        self.toolsReliedUpon = toolsReliedUpon
        self.description = description
        self.systemSettingsURLString = systemSettingsURLString
        self.isGranted = isGranted
    }
}

// MARK: - App Permissions State Manager

@MainActor
public final class AppPermissionsManager: ObservableObject {
    public static let shared = AppPermissionsManager()

    @Published public private(set) var permissions: [AppPermissionItem] = []
    @Published public private(set) var lastRefreshed: Date = Date()

    public var grantedCount: Int {
        permissions.filter { $0.isGranted }.count
    }

    public var totalCount: Int {
        permissions.count
    }

    public var allGranted: Bool {
        grantedCount == totalCount && totalCount > 0
    }

    private init() {
        refreshStatus()
    }

    public func refreshStatus() {
        var items: [AppPermissionItem] = []

        // 1. Accessibility (use_app, UI interaction)
        let axGranted = AXIsProcessTrusted()
        items.append(AppPermissionItem(
            id: "accessibility",
            name: "Accessibility",
            category: "System Interaction",
            icon: "figure.roll",
            tintColor: .blue,
            toolsReliedUpon: ["use_app", "interact_app", "UI Element Automation"],
            description: "Allows Assist to interact with running macOS applications, click controls, type text, and inspect accessibility UI hierarchies.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            isGranted: axGranted
        ))

        // 2. Screen Recording (take_screenshot, take_screenrecord)
        let screenGranted = CGPreflightScreenCaptureAccess()
        items.append(AppPermissionItem(
            id: "screen_recording",
            name: "Screen Recording",
            category: "Diagnostics & Vision",
            icon: "display.trianglebadge.exclamationmark",
            tintColor: .indigo,
            toolsReliedUpon: ["take_screenshot", "take_screenrecord", "Vision Diagnostics"],
            description: "Allows Assist to capture high-resolution display screenshots and record application windows for visual verification.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            isGranted: screenGranted
        ))

        // 3. Full Disk Access (filesystem tools, external projects)
        let fdaGranted: Bool = {
            let path = NSHomeDirectory() + "/Library/Safari"
            return FileManager.default.isReadableFile(atPath: path)
        }()
        items.append(AppPermissionItem(
            id: "full_disk_access",
            name: "Full Disk Access",
            category: "File Operations",
            icon: "internaldrive.fill",
            tintColor: .purple,
            toolsReliedUpon: ["file_read", "file_write", "dir_read", "file_delete", "Git Repositories"],
            description: "Grants SwiftCode uninhibited filesystem access to read and edit codebases across custom directories, Desktop, and Downloads.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            isGranted: fdaGranted
        ))

        // 4. Developer Tools & Shell Execution (use_terminal, project_build)
        let devModeGranted = DeveloperModeManager.shared.isDeveloperModeEnabled
        items.append(AppPermissionItem(
            id: "developer_tools",
            name: "Developer Tools & Terminal",
            category: "Build & Execution",
            icon: "hammer.fill",
            tintColor: .orange,
            toolsReliedUpon: ["use_terminal", "project_build", "project_test", "Shell Scripts"],
            description: "Authorizes compilation via xcodebuild, test execution, process debugging, and autonomous terminal execution.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools",
            isGranted: devModeGranted
        ))

        // 5. Automation / Apple Events (Finder & System Events)
        items.append(AppPermissionItem(
            id: "automation",
            name: "Apple Events Automation",
            category: "System Integration",
            icon: "applescript.fill",
            tintColor: .teal,
            toolsReliedUpon: ["open_in_finder", "reveal_in_finder", "Finder Control"],
            description: "Enables SwiftCode to reveal files and control macOS Finder and target applications via Apple Events.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            isGranted: true // Typically granted on first target dispatch
        ))

        // 6. Microphone (Assist Speech UI)
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        items.append(AppPermissionItem(
            id: "microphone",
            name: "Microphone",
            category: "Voice Assistant",
            icon: "mic.fill",
            tintColor: .red,
            toolsReliedUpon: ["Assist Voice Prompt", "Audio Dictation"],
            description: "Enables speech input when speaking tasks directly to Assist via the microphone prompt interface.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            isGranted: micGranted
        ))

        // 7. Speech Recognition (SFSpeechRecognizer)
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        items.append(AppPermissionItem(
            id: "speech_recognition",
            name: "Speech Recognition",
            category: "Voice Assistant",
            icon: "waveform.badge.magnifyingglass",
            tintColor: .pink,
            toolsReliedUpon: ["Voice-to-Text Transcription"],
            description: "Transcribes voice prompts in real time directly inside the SwiftCode Assist input bar.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
            isGranted: speechGranted
        ))

        // 8. System Notifications
        let sema = DispatchSemaphore(value: 0)
        var notifGranted = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            notifGranted = (settings.authorizationStatus == .authorized)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 0.05)

        items.append(AppPermissionItem(
            id: "notifications",
            name: "System Notifications",
            category: "Alerts & Status",
            icon: "bell.badge.fill",
            tintColor: .yellow,
            toolsReliedUpon: ["report_to_user", "Build Completion Alerts", "Worker Status"],
            description: "Sends native macOS banner notifications when autonomous builds, tests, or multi-worker tasks finish.",
            systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.notifications",
            isGranted: notifGranted
        ))

        self.permissions = items
        self.lastRefreshed = Date()
    }

    public func grant(permission: AppPermissionItem) {
        switch permission.id {
        case "accessibility":
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            openSettingsURL(permission.systemSettingsURLString)

        case "screen_recording":
            _ = CGRequestScreenCaptureAccess()
            openSettingsURL(permission.systemSettingsURLString)

        case "full_disk_access", "developer_tools", "automation":
            if permission.id == "developer_tools" {
                DeveloperModeManager.shared.enableDeveloperMode()
            }
            openSettingsURL(permission.systemSettingsURLString)

        case "microphone":
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatus()
                }
            }
            openSettingsURL(permission.systemSettingsURLString)

        case "speech_recognition":
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatus()
                }
            }
            openSettingsURL(permission.systemSettingsURLString)

        case "notifications":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.refreshStatus()
                }
            }
            openSettingsURL(permission.systemSettingsURLString)

        default:
            openSettingsURL(permission.systemSettingsURLString)
        }
    }

    public func grantAll() {
        // Trigger all native authorization prompts
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        _ = CGRequestScreenCaptureAccess()
        DeveloperModeManager.shared.enableDeveloperMode()

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }

        // Open System Settings to Accessibility / Security as primary hub
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshStatus()
        }
    }

    private func openSettingsURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - AppPermsView

public struct AppPermsView: View {
    @ObservedObject private var manager = AppPermissionsManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    heroStatusCard
                    permissionsList
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            manager.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshStatus()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("System Permissions & Authorizations")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Enable macOS permissions to unlock all native Assist tools and system automation capabilities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.refreshStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Refresh permission statuses")

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.thinMaterial)
    }

    // MARK: - Hero Status Card

    private var heroStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(manager.allGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: manager.allGranted ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(manager.allGranted ? Color.green : Color.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(manager.grantedCount) of \(manager.totalCount) Permissions Granted")
                            .font(.headline)
                            .fontWeight(.bold)

                        Text(manager.allGranted ? "Fully Authorized" : "Action Required")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(manager.allGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15)))
                            .foregroundStyle(manager.allGranted ? Color.green : Color.orange)
                    }

                    Text(manager.allGranted
                         ? "All native Assist tools (screen capture, app automation, build tools, files) are ready."
                         : "Tools like use_app, take_screenshot, take_screenrecord, and terminal commands require approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !manager.allGranted {
                    Button {
                        manager.grantAll()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Grant All Permissions")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(manager.allGranted ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(manager.grantedCount) / CGFloat(max(manager.totalCount, 1)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .liquidGlass(style: .standard, cornerRadius: 10)
    }

    // MARK: - Permissions List

    private var permissionsList: some View {
        VStack(spacing: 12) {
            ForEach(manager.permissions) { item in
                permissionRow(for: item)
            }
        }
    }

    private func permissionRow(for item: AppPermissionItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            iconBadge(for: item)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.bold)

                    Text(item.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())

                    Spacer()

                    statusPill(for: item)
                }

                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                toolsBadgeList(for: item)
            }

            actionButton(for: item)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.isGranted ? Color.secondary.opacity(0.12) : item.tintColor.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func iconBadge(for item: AppPermissionItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.tintColor.opacity(0.15))
                .frame(width: 38, height: 38)

            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.tintColor)
        }
    }

    @ViewBuilder
    private func statusPill(for item: AppPermissionItem) -> some View {
        let tint = item.isGranted ? Color.green : Color.orange
        HStack(spacing: 4) {
            Image(systemName: item.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption2)
            Text(item.isGranted ? "Granted" : "Required")
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private func toolsBadgeList(for item: AppPermissionItem) -> some View {
        HStack(spacing: 6) {
            Text("Required by:")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ForEach(item.toolsReliedUpon, id: \.self) { tool in
                Text(tool)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.primary)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actionButton(for item: AppPermissionItem) -> some View {
        if item.isGranted {
            Button {
                manager.grant(permission: item)
            } label: {
                Text("Configure")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 70)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .padding(.leading, 8)
        } else {
            Button {
                manager.grant(permission: item)
            } label: {
                Text("Grant")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .tint(item.tintColor)
            .padding(.leading, 8)
        }
    }
}
