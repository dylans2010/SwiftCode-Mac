import SwiftUI
import AppKit
import Observation
import os

/// Thread-safe, MainActor-isolated persistent preview execution runtime.
/// Manages live SwiftUI instances, handles incremental loading, and preserves application state.
@Observable
@MainActor
public final class PreviewRuntime {
    public static let shared = PreviewRuntime()

    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "PreviewRuntime")
    private let loader = PreviewDynamicLoader()
    private let buildService = PreviewBuildService()

    // Persistent runtime state
    public private(set) var activeViewInstances: [String: NSView] = [:]
    public private(set) var activeSessionID: String?
    public private(set) var lastCompiledAt: Date?
    public private(set) var isRunning = false

    private init() {}

    /// Starts or updates a persistent runtime session for a specific SwiftUI view.
    public func updateRuntimeSession(
        sourcePath: String,
        sourceCode: String,
        targetView: String,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> NSView {
        logger.info("[RUNTIME] Processing runtime request for '\(targetView)'")
        isRunning = true
        let startTime = Date()

        // Generate content hash for caching (ensuring whitespaces/comments are evaluated correctly)
        let codeHash = String(sourceCode.hashValue)
        let cacheKey = "\(sourcePath)_\(targetView)_\(codeHash)"

        if let cachedView = activeViewInstances[cacheKey] {
            logHandler("Reusing cached preview render.")
            PreviewDiagnostics.shared.addLog(category: "cache", message: "Cache hit for '\(targetView)' (hash: \(codeHash))")
            isRunning = false
            return cachedView
        }

        // 2. Build / compile dynamic library using the compiler or query cache
        logHandler("Checking compilation cache...")
        let libraryURL: URL
        if let cachedDylibURL = await PreviewCache.shared.getBinary(forHash: codeHash) {
            logHandler("Reusing compiled binary from cache.")
            PreviewDiagnostics.shared.addLog(category: "cache", message: "Cache hit: Compiled binary found for hash \(codeHash)")
            libraryURL = cachedDylibURL
        } else {
            logHandler("Compiling user SwiftUI view target '\(targetView)'...")
            do {
                libraryURL = try await buildService.compilePreview(
                    sourcePath: sourcePath,
                    targetName: targetView,
                    outputHandler: logHandler
                )
                lastCompiledAt = Date()

                // Cache ONLY on successful builds to prevent poisoning the cache
                await PreviewCache.shared.setBinary(libraryURL, forHash: codeHash)
            } catch {
                isRunning = false
                logger.error("[RUNTIME] Compilation failed: \(error.localizedDescription)")
                logHandler("Dynamic compilation failed. Falling back to native sandbox runtime.")
                throw error
            }
        }

        // 3. Load compiled SwiftUI view as an AppKit native NSView
        logHandler("Executing live runtime dynamic link...")
        let module = CompiledPreviewModule(libraryURL: libraryURL, diagnostics: [], metadata: ["target": targetView])
        let entry = PreviewSimulationEntry(appName: "SwiftCode Preview", rootViewType: targetView, sceneType: "WindowGroup")

        do {
            let loadedSimulation = try loader.load(module: module, entry: entry)

            let nativeView = loadedSimulation.nativeView
            nativeView.translatesAutoresizingMaskIntoConstraints = false
            nativeView.autoresizingMask = [.width, .height]

            activeViewInstances[cacheKey] = nativeView
            activeSessionID = UUID().uuidString
            isRunning = false

            let duration = Date().timeIntervalSince(startTime)
            PreviewPerformanceMonitor.shared.recordRenderTime(duration)
            PreviewDiagnostics.shared.addLog(category: "render", message: "Rendered \(targetView) in \(String(format: "%.2f", duration))s")

            return nativeView
        } catch {
            isRunning = false
            logger.error("[RUNTIME] Loader failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Explicitly stops the active runtime and unloads dynamic binaries.
    public func stopRuntime() {
        logger.info("[RUNTIME] Terminating persistent sessions and cleaning resources.")
        loader.unloadCurrentModule()
        activeViewInstances.removeAll()
        activeSessionID = nil
        lastCompiledAt = nil
        isRunning = false
    }
}
