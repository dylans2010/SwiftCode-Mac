import SwiftUI

// MARK: - SDKFirstLaunchInstallerView
//
// First-launch sheet for SwiftCode Studio (spec §5, "Studio first-launch
// SDK installer").
//
// Presented once per the persisted choice in `SDKStudioFirstLaunchChoice`
// (wired from `SDKStudioView`). Explains what the SDK is, where it will
// be installed (`~/.swiftcode/sdk`), and offers Install / Remind me
// later / Decline.
//
// - Install runs the REAL `SDKInstaller` (live stdout/stderr streaming,
//   post-install verification; success is reported only when
//   `node_modules/@swiftcode/sdk/package.json` resolves with a version).
// - Failure shows the REAL error text, never a fake "installed".
// - Decline (or Remind me later) leaves Studio fully usable: the choice
//   is persisted in UserDefaults and the sheet simply dismisses. Nothing
//   in Studio is gated on the SDK being installed.
//
// macOS 15, Swift 6. Installer and shell checks are documented in
// SDK/Documentation/Release-Readiness.md; full-app QA remains a release gate.

@MainActor
public struct SDKFirstLaunchInstallerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SDKFirstLaunchInstallerModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .prompt:
                promptContent
            case .installing:
                installingContent
            case .succeeded(let result):
                successContent(result)
            case .failed(let result):
                failureContent(result)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 620, maxWidth: 720)
        .interactiveDismissDisabled(model.phase == .installing)
    }

    // MARK: - Prompt

    private var promptContent: some View {
        Group {
            Label("Install the SwiftCode SDK?", systemImage: "shippingbox")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The SwiftCode SDK is the toolkit Studio uses to build, package, and run extensions and SwiftCode-platform apps: the `@swiftcode/sdk` runtime library, the `swiftcode` project CLI, and the capability contracts Studio validates your projects against.")
                .font(.body)
                .foregroundStyle(.secondary)

            installLocationRow

            Text("Installing downloads the SDK from GitHub and verifies the installed copy before reporting success. You can skip this entirely — Studio stays fully usable without the SDK, and you can install it later.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Decline") {
                    SDKStudioFirstLaunchChoice.recordDeclined()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Remind Me Later") {
                    SDKStudioFirstLaunchChoice.recordRemindLater()
                    dismiss()
                }

                Button("Install SDK") {
                    model.startInstall()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
    }

    private var installLocationRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Install location")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(SDKInstaller.defaultPrefix.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Installing

    private var installingContent: some View {
        Group {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing SwiftCode SDK…")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text("Running npm install. Every line below is live output from the installer.")
                .font(.callout)
                .foregroundStyle(.secondary)

            logTranscript
        }
    }

    private var logTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.logLines.indices, id: \.self) { index in
                        let line = model.logLines[index]
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(line.stream == .stderr ? .red : .primary)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(minHeight: 180, idealHeight: 220, maxHeight: 320)
            .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: model.logLines.count) { _, count in
                if count > 0 {
                    withAnimation(.none) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Success

    private func successContent(_ result: SDKInstaller.InstallResult) -> some View {
        Group {
            Label("SDK Installed", systemImage: "checkmark.circle.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.green)

            Text(result.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !model.logLines.isEmpty {
                logTranscript
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Failure

    private func failureContent(_ result: SDKInstaller.InstallResult) -> some View {
        Group {
            Label("Installation Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.red)

            Text("The SDK was not installed. This is the real error — nothing was faked:")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(result.message)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 120, idealHeight: 180, maxHeight: 300)
            .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Not Now") {
                    SDKStudioFirstLaunchChoice.recordRemindLater()
                    dismiss()
                }
                Button("Try Again") {
                    model.startInstall()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - SDKFirstLaunchInstallerModel

/// View model driving the install sheet. All installer callbacks hop
/// back to the main actor before touching `@Published` state.
@MainActor
final class SDKFirstLaunchInstallerModel: ObservableObject {
    enum Phase: Equatable {
        case prompt
        case installing
        case succeeded(SDKInstaller.InstallResult)
        case failed(SDKInstaller.InstallResult)
    }

    @Published private(set) var phase: Phase = .prompt
    @Published private(set) var logLines: [SDKInstaller.LogLine] = []

    func startInstall() {
        switch phase {
        case .installing:
            return
        case .prompt, .succeeded, .failed:
            break
        }
        phase = .installing
        logLines = []

        Task { [weak self] in
            let result = await SDKInstaller.install { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.append(line: line)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if result.success {
                    SDKStudioFirstLaunchChoice.recordInstalled()
                    self.phase = .succeeded(result)
                } else {
                    self.phase = .failed(result)
                }
            }
        }
    }

    private func append(line: SDKInstaller.LogLine) {
        logLines.append(line)
        // Bound the transcript; the full log is also in the result.
        if logLines.count > 1000 {
            logLines.removeFirst(logLines.count - 1000)
        }
    }
}

// MARK: - SDKStudioFirstLaunchChoice

/// Persists the user's first-launch SDK choice. Non-secret UI state, so
/// UserDefaults is the right store (never Keychain, never the leaky
/// general KeychainService).
enum SDKStudioFirstLaunchChoice {
    private static let choiceKey = "com.swiftcode.sdk.studio.firstLaunch.choice"
    private static let remindLaterDateKey = "com.swiftcode.sdk.studio.firstLaunch.remindLaterDate"

    /// How long "Remind me later" snoozes the prompt.
    private static let remindLaterInterval: TimeInterval = 7 * 24 * 60 * 60

    private enum Choice: String {
        case installed
        case declined
        case remindLater
    }

    /// Whether the first-launch sheet should be presented. False when
    /// the SDK already verifies as installed, when the user declined,
    /// or when a "remind later" snooze is still active.
    static func shouldPrompt() -> Bool {
        // A healthy install needs no prompt — and re-records the choice
        // in case the install happened outside this sheet.
        if case .ok = SDKInstaller.inspect() {
            recordInstalled()
            return false
        }
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: choiceKey),
              let choice = Choice(rawValue: raw)
        else {
            return true
        }
        switch choice {
        case .installed:
            // Install was recorded but no longer verifies (missing /
            // corrupt / version mismatch): this IS the idempotent repair
            // path — prompt again so the user can re-install.
            return true
        case .declined:
            return false
        case .remindLater:
            guard let date = defaults.object(forKey: remindLaterDateKey) as? Date else {
                return true
            }
            return Date().timeIntervalSince(date) >= remindLaterInterval
        }
    }

    static func recordInstalled() {
        UserDefaults.standard.set(Choice.installed.rawValue, forKey: choiceKey)
    }

    static func recordDeclined() {
        UserDefaults.standard.set(Choice.declined.rawValue, forKey: choiceKey)
    }

    static func recordRemindLater() {
        let defaults = UserDefaults.standard
        defaults.set(Choice.remindLater.rawValue, forKey: choiceKey)
        defaults.set(Date(), forKey: remindLaterDateKey)
    }
}
