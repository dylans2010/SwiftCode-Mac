import Foundation

public struct BehaviorEventTracker {
    public private(set) var previous: WorkspaceSession.Activity?
    public private(set) var runPrintedOutput = false
    public private(set) var consoleEntriesAtRunStart = 0

    public init() {}

    private static func isRunning(_ a: WorkspaceSession.Activity?) -> Bool {
        switch a {
        case .running?, .paused?: true
        default: false
        }
    }

    private static func isBuilding(_ a: WorkspaceSession.Activity?) -> Bool {
        if case .building? = a { return true }
        return false
    }

    public mutating func events(for a: WorkspaceSession.Activity, hasErrors: Bool, hasWarnings: Bool,
                                consoleEntries: Int = 0) -> [Preferences.Event] {
        var out: [Preferences.Event] = []
        let wasRunning = Self.isRunning(previous)
        switch a {
        case .idle:
            break
        case .building:
            if !Self.isBuilding(previous) { out.append(.buildStarts) }
        case .running:
            if !wasRunning {
                runPrintedOutput = false
                consoleEntriesAtRunStart = consoleEntries
                out.append(.runStarts)
            }
        case .paused:
            out.append(.runPauses)
        case .finished(let s):
            out += Self.finishedEvents(s, hasErrors: hasErrors, hasWarnings: hasWarnings)
        }
        previous = a
        return out
    }

    public static func finishedEvents(_ s: String, hasErrors: Bool, hasWarnings: Bool) -> [Preferences.Event] {
        let lower = s.lowercased()
        if lower.contains("run failed") || s.contains("exited unexpectedly") { return [.runExitsUnexpectedly] }
        if s == WorkspaceSession.RunActivityText.testSucceeded || s == WorkspaceSession.RunActivityText.testCompleted { return [.testSucceeds] }
        if s == WorkspaceSession.RunActivityText.testFailed { return [.testFails] }
        if s.hasPrefix("Test") { return [] }
        if s.contains("Finished running") { return [.runEnds] }
        if s.hasSuffix("Succeeded") { return (hasWarnings ? [.buildWarnings] : []) + [.buildSucceeds] }
        if s.hasSuffix("Failed") { return (hasErrors ? [.buildErrors] : []) + [.buildFails] }
        return []
    }

    public mutating func noteConsoleOutput(targetOutput: Bool) -> Preferences.Event? {
        guard Self.isRunning(previous), !runPrintedOutput, targetOutput else { return nil }
        runPrintedOutput = true
        return .runOutput
    }
}

public struct BuildNotice: Equatable, Sendable {
    public enum Outcome: Sendable { case succeeded, failed, other }
    public var title: String
    public var symbolName: String
    public var outcome: Outcome
    public init(title: String, symbolName: String, outcome: Outcome) {
        self.title = title
        self.symbolName = symbolName
        self.outcome = outcome
    }
}

public enum BuildNotificationPolicy {
    public static func notice(for event: Preferences.Event, activity: String?) -> BuildNotice {
        func result(_ suffix: String) -> String? { activity.flatMap { $0.hasSuffix(suffix) ? $0 : nil } }
        switch event {
        case .buildSucceeds: return BuildNotice(title: result("Succeeded") ?? "Build Succeeded", symbolName: "hammer", outcome: .succeeded)
        case .buildFails: return BuildNotice(title: result("Failed") ?? "Build Failed", symbolName: "hammer", outcome: .failed)
        case .testSucceeds:
            let t = activity == WorkspaceSession.RunActivityText.testCompleted ? WorkspaceSession.RunActivityText.testCompleted
                : WorkspaceSession.RunActivityText.testSucceeded
            return BuildNotice(title: t, symbolName: "checkmark.circle", outcome: .succeeded)
        case .testFails: return BuildNotice(title: WorkspaceSession.RunActivityText.testFailed, symbolName: "xmark.circle", outcome: .failed)
        default:
            var t = event.rawValue
            if t.hasPrefix("When ") { t.removeFirst(5) }
            t = t.prefix(1).uppercased() + t.dropFirst()
            return BuildNotice(title: t, symbolName: event.category == "Build" ? "hammer" : "play", outcome: .other)
        }
    }

    @MainActor
    public static func notices(for events: [Preferences.Event], activity: WorkspaceSession.Activity,
                               preferences: Preferences = .shared) -> [BuildNotice] {
        var text: String?
        if case .finished(let s) = activity { text = s }
        return events.filter { preferences.behavior($0).notify }.map { notice(for: $0, activity: text) }
    }

    public enum Route: Equatable, Sendable { case bezel, systemNotification }

    public struct WindowState: Equatable, Sendable {
        public var isVisible: Bool
        public var isMinimized: Bool
        public var isKey: Bool
        public var appIsActive: Bool
        public init(isVisible: Bool, isMinimized: Bool = false, isKey: Bool, appIsActive: Bool) {
            self.isVisible = isVisible
            self.isMinimized = isMinimized
            self.isKey = isKey
            self.appIsActive = appIsActive
        }
        public static let frontmost = WindowState(isVisible: true, isKey: true, appIsActive: true)
    }

    public static func route(_ w: WindowState) -> Route {
        w.isVisible && !w.isMinimized && w.isKey && w.appIsActive ? .bezel : .systemNotification
    }
}

public struct BezelTimeline: Equatable, Sendable {
    public static let visibleDuration: TimeInterval = 1.6
    public static let fadeDuration: TimeInterval = 0.35

    public enum Phase: Equatable, Sendable { case hidden, shown, fading }

    public private(set) var notice: BuildNotice?
    public private(set) var shownAt: Date?
    public private(set) var generation = 0
    public private(set) var reduceMotion = false
    public private(set) var showCount = 0

    public init() {}

    @discardableResult
    public mutating func show(_ n: BuildNotice, at now: Date, reduceMotion: Bool) -> Int {
        notice = n
        shownAt = now
        self.reduceMotion = reduceMotion
        generation += 1
        showCount += 1
        return generation
    }

    public var currentFadeDuration: TimeInterval { reduceMotion ? 0 : Self.fadeDuration }

    public var fadeStartsAfter: TimeInterval { Self.visibleDuration }
    public var removedAfter: TimeInterval { Self.visibleDuration + currentFadeDuration }

    public func phase(at t: Date) -> Phase {
        guard notice != nil, let s = shownAt else { return .hidden }
        let e = t.timeIntervalSince(s)
        if e < 0 { return .hidden }
        if e < fadeStartsAfter { return .shown }
        if e < removedAfter { return .fading }
        return .hidden
    }

    public func opacity(at t: Date) -> Double {
        switch phase(at: t) {
        case .hidden: return 0
        case .shown: return 1
        case .fading:
            guard let s = shownAt, currentFadeDuration > 0 else { return 0 }
            return max(0, 1 - (t.timeIntervalSince(s) - fadeStartsAfter) / currentFadeDuration)
        }
    }

    @discardableResult
    public mutating func expire(generation g: Int) -> Bool {
        guard g == generation, notice != nil else { return false }
        notice = nil
        shownAt = nil
        return true
    }
}
