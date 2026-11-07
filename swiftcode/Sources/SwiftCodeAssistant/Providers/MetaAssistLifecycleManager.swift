import Foundation

public actor MetaAssistLifecycleManager {
    public static let shared = MetaAssistLifecycleManager()

    public static let healthCheckInterval: TimeInterval = 5
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

    public var stoppedIntentionally: Bool { isIntentionalStop }

    public func startEngine(workspaceRoot: String, executable: URL?) async throws {
        isIntentionalStop = false
        guard let executable else { return }
        try await bridge.startHost(executable: executable, workspaceRoot: workspaceRoot)
    }

    public func stopEngine() async {
        isIntentionalStop = true
        await bridge.stopHost()
    }

    public func restartEngine(workspaceRoot: String, executable: URL?) async throws {
        isIntentionalStop = false
        await stopEngine()
        try await startEngine(workspaceRoot: workspaceRoot, executable: executable)
    }

    public func ensureRunning() async {
        guard !isIntentionalStop else { return }
        guard let executable = executable?(), let root = workspaceRoot?() else { return }
        guard !(await bridge.isRunning) else { return }
        try? await bridge.startHost(executable: executable, workspaceRoot: root)
    }

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
