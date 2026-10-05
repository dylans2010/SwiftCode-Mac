//
//  GoogleCloudSDKLifecycleManager.swift
//  SwiftCode
//
//  Background lifecycle manager that ensures the Google Cloud SDK engine
//  runs continuously whenever 'Assist on Google Cloud' is active, auto-restarting
//  on unexpected exits, and shutting down cleanly only when the app terminates.
//

import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKLifecycleManager")

@MainActor
public final class GoogleCloudSDKLifecycleManager: ObservableObject {
    public static let shared = GoogleCloudSDKLifecycleManager()

    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var restartCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var healthCheckTask: Task<Void, Never>?
    private var isIntentionalStop: Bool = false
    private var lastRestartAttempt: Date = .distantPast

    private init() {}

    /// Activates the background manager. Called at application launch.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Starting Google Cloud SDK background lifecycle manager...")

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

        // If 'Assist on Google Cloud' is already active on launch, start immediately
        if AppSettings.shared.isGoogleCloudAssist {
            Task { @MainActor in
                await self.ensureRunning()
            }
        }

        // Start periodic health monitor loop
        startHealthCheckLoop()
    }

    /// Stops monitoring and sets intentional stop flag.
    public func stopMonitoring() {
        isMonitoring = false
        healthCheckTask?.cancel()
        healthCheckTask = nil
        cancellables.removeAll()
    }

    /// Explicit request to start the engine and keep it running.
    public func startEngine() async throws {
        isIntentionalStop = false
        let runtime = GoogleCloudSDKRuntime.shared
        guard !runtime.isRunning else { return }
        try await runtime.start()
        logger.info("Google Cloud SDK engine started by lifecycle manager.")
    }

    /// Explicit user stop request.
    public func stopEngine() async {
        isIntentionalStop = true
        let runtime = GoogleCloudSDKRuntime.shared
        await runtime.stop()
        logger.info("Google Cloud SDK engine stopped intentionally.")
    }

    /// Restarts the engine.
    public func restartEngine() async throws {
        isIntentionalStop = false
        try await GoogleCloudSDKRuntime.shared.restart()
        logger.info("Google Cloud SDK engine restarted by lifecycle manager.")
    }

    private func handleAssistSystemChange(systemID: String) async {
        if systemID == AppSettings.googleCloudAssistSystemID {
            isIntentionalStop = false
            logger.info("Assist system switched to Google Cloud. Ensuring engine is active...")
            await ensureRunning()
        } else {
            logger.info("Assist system switched to native (\(systemID)). Engine remains idle if stopped.")
        }
    }

    private func ensureRunning() async {
        guard AppSettings.shared.isGoogleCloudAssist else { return }
        guard !isIntentionalStop else { return }

        let runtime = GoogleCloudSDKRuntime.shared
        if !runtime.isRunning && !runtime.isStarting {
            do {
                logger.info("Ensuring Google Cloud SDK engine is running...")
                try await runtime.start()
            } catch {
                logger.error("Failed to start Google Cloud SDK engine: \(error.localizedDescription)")
            }
        }
    }

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
                guard let self = self, !Task.isCancelled else { break }

                guard AppSettings.shared.isGoogleCloudAssist else { continue }
                guard !self.isIntentionalStop else { continue }

                let runtime = GoogleCloudSDKRuntime.shared
                if !runtime.isRunning && !runtime.isStarting {
                    // Check rate-limiting on restarts to avoid fast crash loops
                    let now = Date()
                    if now.timeIntervalSince(self.lastRestartAttempt) > 4.0 {
                        self.lastRestartAttempt = now
                        self.restartCount += 1
                        logger.warning("Google Cloud SDK engine exited unexpectedly. Automatically restarting (attempt \(self.restartCount))...")
                        do {
                            try await runtime.start()
                        } catch {
                            logger.error("Auto-restart failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}
