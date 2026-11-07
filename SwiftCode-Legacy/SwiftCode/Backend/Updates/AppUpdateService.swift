import AppKit
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    static let shared = AppUpdateService()

    private var updater: SPUUpdater!

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
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: self,
            delegate: self
        )
    }

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

    func checkForUpdates() {
        if updater.sessionInProgress || pendingUpdate != nil {
            bringUpdateWindowToFront()
            if !updater.sessionInProgress, pendingUpdate != nil {
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

    func closeUpdateWindow() {
        closePresentation()
    }

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

    func feedURLString(for updater: SPUUpdater) -> String? {
        AppUpdateConfiguration.feedURLString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheckDate = updater.lastUpdateCheckDate
        sessionInProgress = updater.sessionInProgress
        isChecking = false
        isManualCheckPending = false
        if let error {
            if lastErrorMessage == nil, pendingUpdate == nil {
                lastErrorMessage = error.localizedDescription
            }
            LoggingTool.error("SwiftCode updates: update cycle failed: \(error.localizedDescription)")
        }
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
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

        let deferrals = RemindLaterGate.loadFromDefaults()
        if RemindLaterGate.shouldSuppressOffer(
            version: info.versionString,
            remindUntil: deferrals,
            userInitiated: state.userInitiated
        ) {
            reply(.dismiss)
            return
        }

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
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
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
