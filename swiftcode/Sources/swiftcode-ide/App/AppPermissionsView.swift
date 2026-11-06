import Foundation
import SwiftUI

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(AppKit)
import AppKit
#endif

// App permissions, adapted from Legacy's
// `SwiftCode/Views/Settings/AppPermsView.swift`. The destination has no
// permissions surface, so this is a real status dashboard: it reads
// each permission's actual authorization state from the system
// frameworks (camera/microphone via AVFoundation, speech recognition
// via Speech, screen recording via CoreGraphics, notifications via
// UserNotifications) and reports it; granting happens in System
// Settings, which the view opens on macOS. Every framework is
// `canImport`-gated so the view still builds where the framework is
// absent, and on those platforms the row honestly reports the check
// as unavailable instead of inventing a status.

/// One permission row: its current system authorization state.
struct AppPermissionStatus: Identifiable {
    var id: String { name }
    var name: String
    var detail: String
    var granted: Bool?
}

/// Read-only dashboard of the app's system permission states.
struct AppPermissionsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var statuses: [AppPermissionStatus] = []
    @State private var isLoading = true

    var body: some View {
        let c = ShellColors(scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text("App Permissions").font(ShellFonts.rowBold)
            Text("Permissions are granted in System Settings, not here. This view shows the current state of each permission the IDE can request.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
            if isLoading {
                ProgressView("Checking permissions…")
            } else {
                List(statuses) { status in
                    HStack(spacing: 8) {
                        Image(systemName: status.granted == true
                              ? "checkmark.circle.fill"
                              : status.granted == false ? "xmark.circle.fill" : "questionmark.circle.fill")
                            .foregroundStyle(status.granted == true ? .green : status.granted == false ? .red : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: status.name).font(ShellFonts.rowBold)
                            Text(verbatim: status.detail)
                                .font(ShellFonts.small)
                                .foregroundStyle(c.secondaryLabel)
                        }
                        Spacer()
                    }
                }
                .listStyle(.plain)
            }
            HStack {
#if os(macOS)
                Button("Open Privacy Settings") { openPrivacySettings() }
#else
                Text("Open the system privacy settings to change a permission.")
                    .font(ShellFonts.small)
                    .foregroundStyle(c.secondaryLabel)
#endif
                Spacer()
                Button("Refresh") { load() }
            }
            Spacer()
        }
        .padding(12)
        .onAppear { load() }
    }

#if os(macOS)
    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
#endif

    private func load() {
        isLoading = true
        Task {
            var rows: [AppPermissionStatus] = []
#if canImport(AVFoundation)
            let camera = AVCaptureDevice.authorizationStatus(for: .video)
            rows.append(AppPermissionStatus(
                name: "Camera",
                detail: "Used for device camera previews. Status: \(authorizationWord(camera)).",
                granted: camera == .authorized))
            let mic = AVCaptureDevice.authorizationStatus(for: .audio)
            rows.append(AppPermissionStatus(
                name: "Microphone",
                detail: "Used for voice input. Status: \(authorizationWord(mic)).",
                granted: mic == .authorized))
#else
            rows.append(AppPermissionStatus(
                name: "Camera", detail: "Camera status cannot be checked on this platform.", granted: nil))
            rows.append(AppPermissionStatus(
                name: "Microphone", detail: "Microphone status cannot be checked on this platform.", granted: nil))
#endif
#if canImport(Speech)
            let speech = SFSpeechRecognizer.authorizationStatus()
            rows.append(AppPermissionStatus(
                name: "Speech Recognition",
                detail: "Used for dictating to the assistant. Status: \(speechAuthorizationWord(speech)).",
                granted: speech == .authorized))
#else
            rows.append(AppPermissionStatus(
                name: "Speech Recognition", detail: "Speech-recognition status cannot be checked on this platform.", granted: nil))
#endif
#if os(macOS)
            let screenGranted = CGPreflightScreenCaptureAccess()
            rows.append(AppPermissionStatus(
                name: "Screen Recording",
                detail: screenGranted
                    ? "Authorized: the IDE may capture the screen for screenshots and recordings."
                    : "Not authorized: screenshots and screen recordings will be refused until granted in System Settings.",
                granted: screenGranted))
#else
            rows.append(AppPermissionStatus(
                name: "Screen Recording", detail: "Screen-recording status cannot be checked on this platform.", granted: nil))
#endif
#if canImport(UserNotifications)
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            rows.append(AppPermissionStatus(
                name: "Notifications",
                detail: "Authorization: \(settings.authorizationStatus == .authorized ? "authorized" : settings.authorizationStatus == .denied ? "denied" : settings.authorizationStatus == .provisional ? "provisional" : "not determined").",
                granted: settings.authorizationStatus == .authorized))
#else
            rows.append(AppPermissionStatus(
                name: "Notifications", detail: "Notification status cannot be checked on this platform.", granted: nil))
#endif
            statuses = rows
            isLoading = false
        }
    }
}

#if canImport(AVFoundation)
/// Human-readable word for an `AVAuthorizationStatus` value.
private func authorizationWord(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not determined"
    @unknown default: return "unknown"
    }
}
#endif

#if canImport(Speech)
/// Human-readable word for an `SFSpeechRecognizerAuthorizationStatus` value.
private func speechAuthorizationWord(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not determined"
    @unknown default: return "unknown"
    }
}
#endif
