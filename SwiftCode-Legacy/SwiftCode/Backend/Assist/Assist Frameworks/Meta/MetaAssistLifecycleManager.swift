//
//  MetaAssistLifecycleManager.swift
//  SwiftCode
//
//  Background lifecycle manager that ensures the Meta Muse Code SDK engine (TypeScript/Node)
//  starts up at application launch and runs continuously when 'Assist on Meta' is active.
//

import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.swiftcode.MetaAssist", category: "MetaAssistLifecycleManager")

@MainActor
public final class MetaAssistLifecycleManager: ObservableObject {
    public static let shared = MetaAssistLifecycleManager()

    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var restartCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var healthCheckTask: Task<Void, Never>?
    private var isIntentionalStop: Bool = false
    private var lastRestartAttempt: Date = .distantPast

    private init() {}

    /// Activates background manager. Called at application launch.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Starting Meta Assist background lifecycle manager...")

        // Observe AppSettings.shared.assistSystemID changes
        AppSettings.shared.$assistSystemID
            .removeDuplicates()
            .sink { [weak self] systemID in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.handleAssistSystemChange(systemID: systemID)
                }
            }
            .store(in: &cancellables)

        // Prewarm and start engine automatically on launch so it is available right away
        Task { @MainActor in
            await self.ensureRunning()
        }

        startHealthCheckLoop()
    }

    public func stopMonitoring() {
        isMonitoring = false
        healthCheckTask?.cancel()
        healthCheckTask = nil
        cancellables.removeAll()
    }

    /// Explicit request to start the engine and keep it running.
    public func startEngine() async throws {
        isIntentionalStop = false
        guard MuseCodeCLIHelper.shared.isInstalled() else {
            logger.info("Meta Muse Code CLI is not installed; engine idle.")
            return
        }
        let workspaceRoot = ProjectSessionStore.shared.activeProject?.directoryURL.path ?? NSHomeDirectory()
        try await MuseCodeMSPBridge.shared.startHost(workspaceRoot: workspaceRoot)
        logger.info("Meta Assist engine started by lifecycle manager.")
    }

    public func stopEngine() async {
        isIntentionalStop = true
        MuseCodeMSPBridge.shared.stopHost()
        logger.info("Meta Assist engine stopped intentionally.")
    }

    public func restartEngine() async throws {
        isIntentionalStop = false
        await stopEngine()
        try await startEngine()
        logger.info("Meta Assist engine restarted by lifecycle manager.")
    }

    private func handleAssistSystemChange(systemID: String) async {
        if systemID == AppSettings.metaAssistSystemID {
            isIntentionalStop = false
            logger.info("Assist system switched to Meta. Ensuring engine is active...")
            await ensureRunning()
        } else {
            logger.info("Assist system switched to \(systemID). Meta engine remains in standby.")
        }
    }

    private func ensureRunning() async {
        guard !isIntentionalStop else { return }
        guard MuseCodeCLIHelper.shared.isInstalled() else { return }

        let bridge = MuseCodeMSPBridge.shared
        if !bridge.isRunning {
            do {
                logger.info("Ensuring Meta Assist engine is running...")
                let workspaceRoot = ProjectSessionStore.shared.activeProject?.directoryURL.path ?? NSHomeDirectory()
                try await bridge.startHost(workspaceRoot: workspaceRoot)
            } catch {
                logger.error("Failed to start Meta Assist engine: \(error.localizedDescription)")
            }
        }
    }

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
                guard let self = self, !Task.isCancelled else { break }

                guard AppSettings.shared.isMetaAssist else { continue }
                guard !self.isIntentionalStop else { continue }
                guard MuseCodeCLIHelper.shared.isInstalled() else { continue }

                let bridge = MuseCodeMSPBridge.shared
                if !bridge.isRunning {
                    let now = Date()
                    if now.timeIntervalSince(self.lastRestartAttempt) > 4.0 {
                        self.lastRestartAttempt = now
                        self.restartCount += 1
                        logger.warning("Meta Assist engine exited unexpectedly. Automatically restarting (attempt \(self.restartCount))...")
                        do {
                            let workspaceRoot = ProjectSessionStore.shared.activeProject?.directoryURL.path ?? NSHomeDirectory()
                            try await bridge.startHost(workspaceRoot: workspaceRoot)
                        } catch {
                            logger.error("Meta Assist auto-restart failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}
