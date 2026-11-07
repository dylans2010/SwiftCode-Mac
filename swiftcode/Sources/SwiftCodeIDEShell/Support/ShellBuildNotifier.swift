import Foundation
import Observation
import SwiftCodeIDECore

@MainActor
@Observable
public final class ShellBuildNotifier {
    @ObservationIgnored private var tracker = BehaviorEventTracker()
    @ObservationIgnored public private(set) var timeline = BezelTimeline()

    public private(set) var bezel: BuildNotice?
    public private(set) var isFading = false
    public private(set) var fadesStarted = 0

    @ObservationIgnored public var isWindowActive = true
    @ObservationIgnored public var reduceMotion = false
    @ObservationIgnored public var workspaceName = ""
    @ObservationIgnored public var postSystemNotification: (@MainActor (BuildNotice, String) -> Void)?
    @ObservationIgnored public var announce: (@MainActor (String) -> Void)?
    @ObservationIgnored public var preferences: () -> Preferences = { .shared }
    @ObservationIgnored public var timeScale = 1.0

    public private(set) var log: [String] = []

    public init() {}

    public func activityChanged(_ a: WorkspaceSession.Activity, hasErrors: Bool, hasWarnings: Bool) {
        let events = tracker.events(for: a, hasErrors: hasErrors, hasWarnings: hasWarnings)
        for n in BuildNotificationPolicy.notices(for: events, activity: a, preferences: preferences()) { notify(n) }
    }

    public func notify(_ n: BuildNotice) {
        let state = BuildNotificationPolicy.WindowState(isVisible: isWindowActive, isKey: isWindowActive, appIsActive: isWindowActive)
        switch BuildNotificationPolicy.route(state) {
        case .bezel: show(n)
        case .systemNotification:
            log.append("system \(n.title)")
            postSystemNotification?(n, workspaceName)
        }
    }

    private func show(_ n: BuildNotice) {
        let g = timeline.show(n, at: Date(), reduceMotion: reduceMotion)
        bezel = n
        isFading = false
        log.append("bezel \(n.title)")
        announce?(n.title)
        let t = timeline, k = timeScale
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(t.fadeStartsAfter * k * 1e9))
            guard let self, self.timeline.generation == g else { return }
            if t.currentFadeDuration > 0 {
                self.isFading = true
                self.fadesStarted += 1
                try? await Task.sleep(nanoseconds: UInt64(t.currentFadeDuration * k * 1e9))
            }
            if self.timeline.expire(generation: g) {
                self.bezel = nil
                self.isFading = false
            }
        }
    }
}

extension WorkspaceShellModel {
    func noteActivityForNotifications() {
        notifier.workspaceName = workspaceName
        let shown = session.displayedIssues
        notifier.activityChanged(activity, hasErrors: shown.contains { $0.severity == .error },
                                 hasWarnings: shown.contains { $0.severity == .warning })
    }
}
