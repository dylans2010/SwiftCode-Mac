import AppKit
import SwiftUI

/// Hosts `UpdateWindowView` in a real macOS window with standard chrome
/// (title bar and traffic-light buttons). The window is reused across
/// offers so a second check never opens a duplicate window.
///
/// Closing the window with the traffic-light button is treated as a
/// plain dismissal (not a skip, not a reminder): Sparkle is told
/// `.dismiss` and may offer the update again on its own schedule.
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let service: AppUpdateService
    private var window: NSWindow?
    private var didCenter = false

    init(service: AppUpdateService) {
        self.service = service
        super.init()
    }

    func present() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: UpdateWindowView().environmentObject(service)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Software Update"
            window.contentViewController = hosting
            window.minSize = NSSize(width: 520, height: 480)
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        guard let window else { return }
        if !didCenter {
            window.center()
            didCenter = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        service.handleWindowClosed()
    }
}

/// Commander-inspired update window, rendered with native SwiftUI.
///
/// Header: the real SwiftCode icon, "A new version of SwiftCode is
/// available!", the installed version and the available version, all
/// from the live bundle and the live appcast item — nothing here is
/// hardcoded sample data. Release notes come from the appcast item and
/// are shown in a scrollable area; an empty-notes feed shows a fallback
/// line instead of invented notes.
struct UpdateWindowView: View {
    @EnvironmentObject private var service: AppUpdateService

    var body: some View {
        Group {
            if let update = service.pendingUpdate {
                switch service.phase {
                case .offer:
                    offerView(update: update)
                case .downloading, .extracting:
                    progressView(update: update)
                case .readyToInstall:
                    readyView(update: update)
                case .installing:
                    installingView(update: update)
                case .error:
                    errorView(update: update)
                case .idle:
                    offerView(update: update)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking for updates…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    // MARK: - Offer

    private func offerView(update: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityLabel("SwiftCode app icon")
                VStack(alignment: .leading, spacing: 6) {
                    Text("A new version of SwiftCode is available!")
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let title = update.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("You’re running SwiftCode \(AppUpdateConfiguration.currentDisplayVersion) (build \(AppUpdateConfiguration.currentBuildVersion)). Version \(update.displayVersion) is now available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .padding(.bottom, 4)

            Divider()

            // Release notes
            VStack(alignment: .leading, spacing: 8) {
                Text("What’s new in \(update.displayVersion)")
                    .font(.headline)
                if service.isLoadingReleaseNotes {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading release notes…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if service.releaseNoteBlocks.isEmpty {
                    Text("No release notes were provided for this version.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let notesURL = update.releaseNotesURL {
                        Link("View release notes online", destination: notesURL)
                            .font(.subheadline)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(service.releaseNoteBlocks.enumerated()), id: \.offset) { _, block in
                                switch block {
                                case .heading(let text):
                                    Text(text)
                                        .font(.headline)
                                        .padding(.top, 8)
                                case .bullet(let text):
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                        Text(text)
                                    }
                                    .font(.subheadline)
                                case .body(let text):
                                    Text(text)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Spacer()

            Divider()

            // Actions
            VStack(alignment: .leading, spacing: 12) {
                if !service.publicKeyConfigured {
                    Label(
                        "This build has no update signing key configured, so Sparkle will block installation until one is set. See Docs/Updates.md.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    if service.pendingStage != .installing {
                        Button("Skip This Version") {
                            service.skipPendingUpdate()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Skip this version")
                    }
                    Button("Remind Me Later") {
                        service.remindPendingUpdateLater()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    if update.isInformationOnly {
                        Button("Learn More…") {
                            service.learnMoreAboutPendingUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(service.installButtonTitle) {
                            service.installPendingUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Install update")
                    }
                }
                Toggle(
                    "Automatically download and install updates in the future",
                    isOn: Binding(
                        get: { service.automaticallyDownloadsUpdates },
                        set: { service.automaticallyDownloadsUpdates = $0 }
                    )
                )
                .disabled(!service.allowsAutomaticUpdates)
                .font(.subheadline)
                Text("Updates are delivered over HTTPS and verified with EdDSA signatures before installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    // MARK: - Progress / ready / installing / error

    private func progressView(update: AppUpdateInfo) -> some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Updating to SwiftCode \(update.displayVersion)")
                .font(.title3.bold())
            if let progress = service.downloadProgress {
                ProgressView(value: progress)
                    .frame(width: 320)
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if let status = service.downloadStatusText {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") {
                service.cancelDownload()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func readyView(update: AppUpdateInfo) -> some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("SwiftCode \(update.displayVersion) is ready to install")
                .font(.title3.bold())
            Text("The update has been downloaded and verified. SwiftCode will quit and relaunch with the new version.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Later") {
                    service.dismissReadyUpdate()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                Button("Install and Relaunch") {
                    service.installReadyUpdate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func installingView(update: AppUpdateInfo) -> some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Installing SwiftCode \(update.displayVersion)…")
                .font(.title3.bold())
            ProgressView()
            if let status = service.downloadStatusText {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if service.canRetryTermination {
                Button("Retry") {
                    service.retryTerminatingApplication()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorView(update: AppUpdateInfo) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("The update could not be installed")
                .font(.title3.bold())
            if let message = service.lastErrorMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Your current version of SwiftCode is unchanged. You can try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close") {
                    service.closeUpdateWindow()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                Button("Retry Check") {
                    service.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
