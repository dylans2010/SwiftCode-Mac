import Foundation

// MARK: - Meta Assist lifecycle manager (Wave 16, Slice B)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaAssistLifecycleManager.swift`
//     — background lifecycle: start/stop/restart the Muse Code
//     engine, health-check it, restart it when it exits
//     unexpectedly.
//
// What is deliberately different from Legacy:
//   * No `ObservableObject` / `@Published` / Combine, no
//     `AppSettings` observation, no `ProjectSessionStore`, no
//     `os.Logger`: this is an actor. The host tells it when Meta
//     is the active system (`isMetaActive`) and where the
//     workspace is (`workspaceRoot`); the manager never reads
//     app settings or the project store itself. State is read
//     through `isMonitoring` / `restartCount` instead of
//     published properties.
//   * Legacy's numbers are kept verbatim: health check every
//     5 seconds, at most one auto-restart per 4 seconds.
//   * Legacy restarted the engine whenever it was not running
//     and Meta was active, including right after `startEngine`.
//     The same rule applies here, guarded by `isIntentionalStop`
//     (set by `stopEngine`, cleared by `startEngine` /
//     `restartEngine` / an explicit `setIntentionalStop(false)`).

/// Owns the Muse Code engine's lifetime for "Assist with Meta".
/// The host starts monitoring when Meta becomes the active
/// system and stops it when it leaves; in between, the manager
/// keeps the `muse serve` host running and restarts it when it
/// exits unexpectedly.
public actor MetaAssistLifecycleManager {
    public static let shared = MetaAssistLifecycleManager()

    /// Health-check interval (Legacy: 5 seconds).
    public static let healthCheckInterval: TimeInterval = 5
    /// Minimum gap between auto-restarts (Legacy: 4 seconds).
    public static let restartThrottle: TimeInterval = 4

    public private(set) var isMonitoring: Bool = false
    public private(set) var restartCount: Int = 0

    private var isIntentionalStop: Bool = false
    private var lastRestartAttempt: Date = .distantPast
    private var healthCheckTask: Task<Void, Never>?
    private let bridge: MuseCodeMSPBridge
    private var workspaceRoot: (@Sendable () -> String)?
    private var executable: (@Sendable () -> URL?)?
    private var isMetaActive: (@Sendable () -> Bool)?

    public init(
        bridge: MuseCodeMSPBridge = .shared,
        workspaceRoot: (@Sendable () -> String)? = nil,
        executable: (@Sendable () -> URL?)? = nil,
        isMetaActive: (@Sendable () -> Bool)? = nil
    ) {
        self.bridge = bridge
        self.workspaceRoot = workspaceRoot
        self.executable = executable
        self.isMetaActive = isMetaActive
    }

    /// Starts background monitoring. Called at application launch
    /// (Legacy `startMonitoring`) or when Meta is selected; a
    /// second call is a no-op. Prewarms the engine once, then
    /// health-checks it on a loop.
    public func startMonitoring(
        workspaceRoot: (@Sendable () -> String)? = nil,
        executable: (@Sendable () -> URL?)? = nil,
        isMetaActive: (@Sendable () -> Bool)? = nil
    ) {
        guard !isMonitoring else { return }
        isMonitoring = true
        if let workspaceRoot { self.workspaceRoot = workspaceRoot }
        if let executable { self.executable = executable }
        if let isMetaActive { self.isMetaActive = isMetaActive }
        Task { await self.ensureRunning() }
        startHealthCheckLoop()
    }

    public func stopMonitoring() {
        isMonitoring = false
        healthCheckTask?.cancel()
        healthCheckTask = nil
        workspaceRoot = nil
        executable = nil
        isMetaActive = nil
    }

    /// Whether the engine was stopped on purpose (an intentional
    /// stop suppresses the health-check restart).
    public var stoppedIntentionally: Bool { isIntentionalStop }

    /// Explicit request to start the engine and keep it running
    /// (Legacy `startEngine`). A missing `muse` binary leaves the
    /// engine idle instead of throwing: Legacy logged the same
    /// and returned.
    public func startEngine(workspaceRoot: String, executable: URL?) async throws {
        isIntentionalStop = false
        guard let executable else { return }
        try await bridge.startHost(executable: executable, workspaceRoot: workspaceRoot)
    }

    /// Stops the engine on purpose (Legacy `stopEngine`).
    public func stopEngine() async {
        isIntentionalStop = true
        await bridge.stopHost()
    }

    /// Stops, then starts the engine (Legacy `restartEngine`).
    /// Note Legacy's quirk, kept here: `stopEngine` sets the
    /// intentional-stop flag and `startEngine` clears it again,
    /// so a restart never suppresses the health check.
    public func restartEngine(workspaceRoot: String, executable: URL?) async throws {
        isIntentionalStop = false
        await stopEngine()
        try await startEngine(workspaceRoot: workspaceRoot, executable: executable)
    }

    /// Starts the engine when it is not running and Meta is the
    /// active system (Legacy `ensureRunning`). Never throws: a
    /// failed start is left for the health-check loop to retry.
    public func ensureRunning() async {
        guard !isIntentionalStop else { return }
        guard let executable = executable?(), let root = workspaceRoot?() else { return }
        guard !(await bridge.isRunning) else { return }
        try? await bridge.startHost(executable: executable, workspaceRoot: root)
    }

    /// The health check, as a pure step the loop calls (Legacy
    /// `startHealthCheckLoop` body): restarts the engine when it
    /// exited unexpectedly, at most once per throttle window.
    /// Returns true when it restarted the engine.
    @discardableResult
    public func healthCheckOnce(now: Date = Date()) async -> Bool {
        guard isMonitoring else { return false }
        guard isMetaActive?() ?? false else { return false }
        guard !isIntentionalStop else { return false }
        guard let executable = executable?(), let root = workspaceRoot?() else { return false }
        guard !(await bridge.isRunning) else { return false }
        guard now.timeIntervalSince(lastRestartAttempt) > Self.restartThrottle else { return false }
        lastRestartAttempt = now
        restartCount += 1
        do {
            try await bridge.startHost(executable: executable, workspaceRoot: root)
        } catch {
            return false
        }
        return true
    }

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.healthCheckInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { break }
                await self.healthCheckOnce()
            }
        }
    }
}
