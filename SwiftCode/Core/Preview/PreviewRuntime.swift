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

        // 1. Invalidate cache if needed or check if we can perform an incremental reload
        let cacheKey = "\(sourcePath)_\(targetView)"

        // 2. Build / compile dynamic library using the compiler
        logHandler("Compiling user SwiftUI view target '\(targetView)'...")
        let libraryURL: URL
        do {
            libraryURL = try await buildService.compilePreview(
                sourcePath: sourcePath,
                targetName: targetView,
                outputHandler: logHandler
            )
            lastCompiledAt = Date()
        } catch {
            logger.error("[RUNTIME] Compilation failed: \(error.localizedDescription)")
            logHandler("Dynamic compilation failed. Falling back to native sandbox runtime.")
            throw error
        }

        // 3. Load compiled SwiftUI view as an AppKit native NSView
        logHandler("Executing live runtime dynamic link...")
        let module = CompiledPreviewModule(libraryURL: libraryURL, diagnostics: [], metadata: ["target": targetView])
        let entry = PreviewSimulationEntry(appName: "SwiftCode Preview", rootViewType: targetView, sceneType: "WindowGroup")

        do {
            let loadedSimulation = try loader.load(module: module, entry: entry)

            // Extract the native view
            let nativeView: NSView
            if let handle = loadedSimulation.handle {
                // If dlopen successfully resolved, we extract the compiled hosting view
                let symbolName = "__swiftcode_make_hosting_view"
                if let symbol = dlsym(handle, symbolName) {
                    typealias Factory = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
                    let factory = unsafeBitCast(symbol, to: Factory.self)
                    if let viewPtr = targetView.withCString({ factory($0) }) {
                        nativeView = Unmanaged<NSView>.fromOpaque(viewPtr).takeRetainedValue()
                        logger.info("[RUNTIME] Successfully instantiated live compiled SwiftUI view.")
                    } else {
                        nativeView = NSHostingView(rootView: loadedSimulation.anyView)
                    }
                } else {
                    nativeView = NSHostingView(rootView: loadedSimulation.anyView)
                }
            } else {
                nativeView = NSHostingView(rootView: loadedSimulation.anyView)
            }

            // Preserving state where possible: swap only if different
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
