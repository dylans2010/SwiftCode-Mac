import AppKit
import Foundation
import Sparkle
import SwiftUI

/// The one and only update service in SwiftCode.
///
/// Sparkle 2 owns discovery, EdDSA signature verification, download,
/// installation and relaunch. This service is Sparkle's user driver and
/// updater delegate, and the single integration point the rest of the app
/// talks to. There is no second feed, no second timer, and no legacy
/// GitHub API check: `GitHubReleaseCheck` was removed when this service
/// landed, and every entry point (app menu, Settings) routes here.
///
/// Presentation: Sparkle's standard alert is NOT used. This driver
/// presents the Commander-style `UpdateWindowView` for every update,
/// whether the check was scheduled or user-initiated, and translates its
/// three actions back into Sparkle replies:
/// - Install Update -> `.install` (Sparkle downloads/verifies/installs)
/// - Skip This Version -> `.skip` (Sparkle persists the skip itself)
/// - Remind Me Later -> `.dismiss` + a persistent 7-day deferral gate
///   (see `RemindLaterGate`; Sparkle's own gentle-reminder schedule
///   still applies on top of it)
///
/// Automatic download/install is NOT a cosmetic checkbox: it is bound
/// directly to `SPUUpdater.automaticallyDownloadsUpdates`, which Sparkle
/// persists in the host bundle's user defaults.
///
/// Security notes:
/// - Downloads and metadata are HTTPS only (the feed URL is HTTPS and
///   release-notes links are fetched only over HTTPS).
/// - Artifact authenticity comes from Sparkle's EdDSA verification
///   against `SUPublicEDKey`, never from HTTPS alone. If no public key
///   is embedded, Sparkle fails closed at install time and Settings
///   surfaces that fact; this service never disables verification and
///   never installs anything itself.
/// - The app must still launch if the updater is misconfigured:
///   `start()` catches Sparkle's startup error, logs it, and leaves the
///   app running. Manual checks then report the error instead of
///   crashing or blocking launch.
///
/// Mac-build note: Sparkle's Swift API surface is large and this file is
/// the single place that touches it. If a future Sparkle release renames
/// a driver method, the fix belongs here and nowhere else.
@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    static let shared = AppUpdateService()

    // MARK: - Sparkle engine

    private var updater: SPUUpdater!

    // MARK: - Published presentation state

    @Published private(set) var pendingUpdate: AppUpdateInfo?
    @Published private(set) var pendingStage: PendingStage = .notDownloaded
    @Published private(set) var phase: AppUpdatePhase = .idle
    @Published private(set) var releaseNoteBlocks: [ReleaseNoteBlock] = []
    @Published private(set) var isLoadingReleaseNotes = false
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadStatusText: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var lastCheckWasUpToDate = false
    @Published private(set) var isChecking = false
    @Published private(set) var sessionInProgress = false
    @Published private(set) var canRetryTermination = false
    @Published private(set) var startupErrorMessage: String?

    /// What the Commander window's primary button should say.
    var installButtonTitle: String {
        pendingStage == .installing ? "Install and Relaunch" : "Install Update"
    }

    var publicKeyConfigured: Bool { AppUpdateConfiguration.isPublicKeyConfigured }
    var feedURL: URL? { updater.feedURL ?? AppUpdateConfiguration.feedURL }
    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate ?? lastCheckDate }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticUpdates: Bool { updater.allowsAutomaticUpdates }
    var canCheckForUpdates: Bool { updater.canCheckForUpdates && !sessionInProgress }

    // MARK: - Private driver state

    enum PendingStage {
        case notDownloaded
        case downloaded
        case installing
    }

    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var downloadCancellation: (() -> Void)?
    private var retryTermination: (() -> Void)?
    private var isManualCheckPending = false
    private var expectedContentLength: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private var updateWindowController: UpdateWindowController?

    override init() {
        super.init()
        // SAFETY: `updater` is implicitly unwrapped only to break the
        // init cycle (SPUUpdater needs `self` as driver/delegate). It is
        // assigned before init returns and never reassigned afterwards.
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: self,
            delegate: self
        )
    }

    // MARK: - Lifecycle

    /// Start Sparkle's scheduled update cycle. Called once from
    /// `AppDelegate.applicationDidFinishLaunching`. A startup failure
    /// (for example a missing feed URL) is logged and surfaced in
    /// Settings; it never prevents SwiftCode from launching.
    func start() {
        do {
            try updater.start()
            sessionInProgress = updater.sessionInProgress
            lastCheckDate = updater.lastUpdateCheckDate
            if !publicKeyConfigured {
                LoggingTool.error(
                    "SwiftCode updates: SUPublicEDKey is not configured. " +
                    "Sparkle will refuse to install updates until an EdDSA public key is embedded. See Docs/Updates.md."
                )
            }
        } catch {
            startupErrorMessage = error.localizedDescription
            LoggingTool.error("SwiftCode updates: failed to start Sparkle updater: \(error.localizedDescription)")
        }
    }

    /// User-initiated check (app menu "Check for Updates…" and Settings).
    /// Works even when automatic checking is disabled. If a session is
    /// already in progress, the existing update window is brought forward
    /// instead of starting a duplicate check.
    func checkForUpdates() {
        if updater.sessionInProgress || pendingUpdate != nil {
            bringUpdateWindowToFront()
            if !updater.sessionInProgress, pendingUpdate != nil {
                // An offer is already on screen; nothing new to check.
                return
            }
        }
        isManualCheckPending = true
        lastErrorMessage = nil
        lastCheckWasUpToDate = false
        isChecking = true
        updater.checkForUpdates()
    }

    func bringUpdateWindowToFront() {
        guard pendingUpdate != nil else { return }
        presentUpdateWindow()
    }

    /// Close the update window without answering Sparkle (used for the
    /// error screen's Close button, where the reply was already consumed
    /// or Sparkle's teardown will follow). This never skips a version.
    func closeUpdateWindow() {
        closePresentation()
    }

    /// Called when the window is closed via its traffic-light button.
    /// Closing is a plain dismissal, not a skip and not a reminder:
    /// Sparkle may offer the update again on its own schedule.
    /// This clears presentation state only; it does not close the
    /// window again (it is already closing).
    func handleWindowClosed() {
        if let reply = pendingReply {
            pendingReply = nil
            reply(.dismiss)
        }
        if let reply = readyReply {
            readyReply = nil
            reply(.dismiss)
        }
        clearPresentationState()
    }

    // MARK: - Commander window actions (Sparkle replies)

    func installPendingUpdate() {
        guard let reply = pendingReply else { return }
        pendingReply = nil
        phase = pendingStage == .installing ? .installing : .downloading
        downloadStatusText = pendingStage == .installing
            ? "Installing update…"
            : "Downloading update…"
        reply(.install)
    }

    func skipPendingUpdate() {
        guard let reply = pendingReply else { return }
        pendingReply = nil
        reply(.skip)
        closePresentation()
    }

    func remindPendingUpdateLater() {
        guard let reply = pendingReply, let update = pendingUpdate else { return }
        pendingReply = nil
        var deferrals = RemindLaterGate.loadFromDefaults()
        deferrals[update.versionString] = RemindLaterGate.remindUntil()
        RemindLaterGate.saveToDefaults(deferrals)
        reply(.dismiss)
        closePresentation()
    }

    func learnMoreAboutPendingUpdate() {
        guard let reply = pendingReply, let update = pendingUpdate else { return }
        pendingReply = nil
        if let infoURL = update.infoURL {
            NSWorkspace.shared.open(infoURL)
        }
        reply(.dismiss)
        closePresentation()
    }

    func installReadyUpdate() {
        guard let reply = readyReply else { return }
        readyReply = nil
        phase = .installing
        downloadStatusText = "Installing update…"
        reply(.install)
    }

    func dismissReadyUpdate() {
        guard let reply = readyReply else { return }
        readyReply = nil
        reply(.dismiss)
        closePresentation()
    }

    func cancelDownload() {
        downloadCancellation?()
        downloadCancellation = nil
    }

    func retryTerminatingApplication() {
        retryTermination?()
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        // The delegate is authoritative for the feed URL, so a stale
        // Info.plist value can never silently create a second feed.
        AppUpdateConfiguration.feedURLString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheckDate = updater.lastUpdateCheckDate
        sessionInProgress = updater.sessionInProgress
        isChecking = false
        isManualCheckPending = false
        if let error {
            // User-visible errors are surfaced by the driver methods
            // (showUpdaterError); the cycle callback only records the
            // failure for Settings when no driver error was shown.
            if lastErrorMessage == nil, pendingUpdate == nil {
                lastErrorMessage = error.localizedDescription
            }
            LoggingTool.error("SwiftCode updates: update cycle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // SUEnableAutomaticChecks is set in Info.plist, so Sparkle does
        // not normally prompt. If it ever does, default to automatic
        // checks on, without sending system-profile data.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        isChecking = true
        sessionInProgress = true
        downloadCancellation = cancellation
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        isChecking = false
        sessionInProgress = true
        let info = AppUpdateInfo(
            versionString: appcastItem.versionString,
            displayVersionString: appcastItem.displayVersionString,
            title: appcastItem.title,
            fileURL: appcastItem.fileURL,
            infoURL: appcastItem.infoURL,
            releaseNotesURL: appcastItem.releaseNotesURL,
            embeddedReleaseNotes: appcastItem.itemDescription,
            isInformationOnly: appcastItem.isInformationOnlyUpdate,
            contentLength: appcastItem.contentLength
        )

        // "Remind Me Later" gate: scheduled offers for a deferred version
        // are dismissed immediately, without showing the window again.
        // Manual checks bypass the gate (Sparkle also clears skips on
        // manual checks, so a manual check always re-offers).
        let deferrals = RemindLaterGate.loadFromDefaults()
        if RemindLaterGate.shouldSuppressOffer(
            version: info.versionString,
            remindUntil: deferrals,
            userInitiated: state.userInitiated
        ) {
            reply(.dismiss)
            return
        }

        // If an offer for a different version is already on screen,
        // dismiss it before presenting the new one. If it is the same
        // version, just bring the existing window forward.
        if let existing = pendingUpdate, existing.versionString != info.versionString {
            if let oldReply = pendingReply {
                pendingReply = nil
                oldReply(.dismiss)
            }
            closePresentation()
        } else if pendingUpdate != nil {
            presentUpdateWindow()
            return
        }

        pendingReply = reply
        pendingUpdate = info
        pendingStage = mapStage(state.stage)
        phase = .offer
        lastErrorMessage = nil
        expectedContentLength = info.contentLength
        receivedBytes = 0
        downloadProgress = nil
        downloadStatusText = nil

        if let embedded = info.embeddedReleaseNotes, !embedded.isEmpty {
            releaseNoteBlocks = ReleaseNotesFormatter.blocks(fromFeedText: embedded)
            isLoadingReleaseNotes = false
        } else if let notesURL = info.releaseNotesURL, notesURL.scheme == "https" {
            isLoadingReleaseNotes = true
            releaseNoteBlocks = []
            Task { [weak self] in
                let blocks = await self?.fetchReleaseNotes(from: notesURL) ?? []
                await MainActor.run {
                    // Only apply notes for the update still on screen.
                    guard let self, self.pendingUpdate?.versionString == info.versionString else { return }
                    self.releaseNoteBlocks = blocks
                    self.isLoadingReleaseNotes = false
                }
            }
        } else {
            releaseNoteBlocks = []
            isLoadingReleaseNotes = false
        }
        presentUpdateWindow()
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Release notes are rendered from the appcast item (embedded
        // description, or fetched over HTTPS in showUpdateFound), so
        // Sparkle's separately downloaded copy is not needed here.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // The window already shows the empty-notes fallback text, so a
        // failed notes download is not an update failure.
        isLoadingReleaseNotes = false
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        isChecking = false
        sessionInProgress = false
        lastCheckDate = updater.lastUpdateCheckDate ?? Date()
        if isManualCheckPending {
            lastCheckWasUpToDate = true
            lastErrorMessage = nil
        }
        isManualCheckPending = false
    }

    func showUpdaterError(_ error: any Error) async {
        isChecking = false
        sessionInProgress = false
        lastErrorMessage = error.localizedDescription
        lastCheckWasUpToDate = false
        isManualCheckPending = false
        if pendingUpdate != nil {
            phase = .error
            downloadStatusText = nil
        }
        LoggingTool.error("SwiftCode updates: updater error: \(error.localizedDescription)")
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
        phase = .downloading
        downloadStatusText = "Downloading update…"
        downloadProgress = expectedContentLength > 0 ? 0 : nil
        receivedBytes = 0
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
        if expectedContentLength > 0 {
            downloadProgress = Double(receivedBytes) / Double(expectedContentLength)
        }
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        if expectedContentLength > 0 {
            downloadProgress = min(1, Double(receivedBytes) / Double(expectedContentLength))
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .extracting
        downloadStatusText = "Extracting update…"
        downloadProgress = nil
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        phase = .extracting
        downloadStatusText = "Extracting update…"
        downloadProgress = progress
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        phase = .readyToInstall
        downloadStatusText = "Update downloaded and ready to install."
        downloadProgress = 1
        presentUpdateWindow()
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        downloadStatusText = applicationTerminated
            ? "Installing update…"
            : "Installing update… SwiftCode will quit and relaunch."
        downloadProgress = nil
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        canRetryTermination = !applicationTerminated
        presentUpdateWindow()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        // Rarely reached (the app usually quits for installation).
        // A fresh launch resets all presentation state anyway.
        closePresentation()
    }

    func dismissUpdateInstallation() {
        downloadCancellation = nil
        readyReply = nil
        retryTermination = nil
        canRetryTermination = false
        sessionInProgress = false
        isChecking = false
        closePresentation()
    }

    func showUpdateInFocus() {
        presentUpdateWindow()
    }

    // MARK: - Private helpers

    private func mapStage(_ stage: SPUUserUpdateStage) -> PendingStage {
        switch stage {
        case .notDownloaded: return .notDownloaded
        case .downloaded: return .downloaded
        case .installing: return .installing
        default: return .notDownloaded
        }
    }

    private func presentUpdateWindow() {
        if updateWindowController == nil {
            updateWindowController = UpdateWindowController(service: self)
        }
        updateWindowController?.present()
    }

    private func closePresentation() {
        updateWindowController?.dismiss()
        clearPresentationState()
    }

    private func clearPresentationState() {
        pendingUpdate = nil
        pendingReply = nil
        readyReply = nil
        phase = .idle
        releaseNoteBlocks = []
        isLoadingReleaseNotes = false
        downloadProgress = nil
        downloadStatusText = nil
    }

    private func fetchReleaseNotes(from url: URL) async -> [ReleaseNoteBlock] {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
            return ReleaseNotesFormatter.blocks(from: ReleaseNotesFormatter.plainText(from: text))
        } catch {
            LoggingTool.error("SwiftCode updates: failed to fetch release notes: \(error.localizedDescription)")
            return []
        }
    }
}
