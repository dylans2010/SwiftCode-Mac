import SwiftUI
import AppKit
import Observation
import os
import YcodePreviews

@Observable
@MainActor
public final class PreviewRuntime {
    public static let shared = PreviewRuntime()

    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "PreviewRuntime")
    private let loader = PreviewDynamicLoader()

    public private(set) var activeViewInstances: [String: NSView] = [:]
    public private(set) var activeSessionID: String?
    public private(set) var lastCompiledAt: Date?
    public private(set) var isRunning = false

    private init() {}

    public func updateRuntimeSession(
        sourcePath: String,
        sourceCode: String,
        targetView: String,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> NSView {
        logger.info("[RUNTIME] Processing runtime request for '\(targetView)'")
        isRunning = true
        let startTime = Date()

        let codeHash = String(sourceCode.hashValue)
        let cacheKey = "\(sourcePath)_\(targetView)_\(codeHash)"

        if let cachedView = activeViewInstances[cacheKey] {
            logHandler("Reusing cached preview render.")
            PreviewDiagnostics.shared.addLog(category: "cache", message: "Cache hit for '\(targetView)' (hash: \(codeHash))")
            isRunning = false
            return cachedView
        }

        logHandler("Checking compilation cache...")
        let libraryURL: URL
        let previewIndex: Int
        if let cachedDylibURL = await PreviewCache.shared.getBinary(forHash: codeHash) {
            logHandler("Reusing compiled binary from cache.")
            PreviewDiagnostics.shared.addLog(category: "cache", message: "Cache hit: Compiled binary found for hash \(codeHash)")
            libraryURL = cachedDylibURL
            previewIndex = Self.previewIndex(for: targetView, in: sourceCode)
        } else {
            logHandler("Compiling user SwiftUI view target '\(targetView)'...")
            do {
                let compiled = try await compilePreview(
                    sourcePath: sourcePath,
                    sourceCode: sourceCode,
                    targetName: targetView,
                    logHandler: logHandler
                )
                libraryURL = compiled.libraryURL
                previewIndex = compiled.previewIndex
                lastCompiledAt = Date()

                await PreviewCache.shared.setBinary(libraryURL, forHash: codeHash)
            } catch {
                isRunning = false
                logger.error("[RUNTIME] Compilation failed: \(error.localizedDescription)")
                logHandler("Dynamic compilation failed. Falling back to native sandbox runtime.")
                throw error
            }
        }

        logHandler("Executing live runtime dynamic link...")
        let module = CompiledPreviewModule(libraryURL: libraryURL, diagnostics: [], metadata: ["target": targetView])
        let entry = PreviewSimulationEntry(appName: "SwiftCode Preview", rootViewType: targetView, sceneType: "WindowGroup")

        do {
            let loadedSimulation = try loader.load(module: module, entry: entry, previewIndex: previewIndex)

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

    private func compilePreview(
        sourcePath: String,
        sourceCode: String,
        targetName: String,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> (libraryURL: URL, previewIndex: Int) {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let payloadDir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-preview-\(UUID().uuidString)")
        let previews = PreviewDiscovery.previews(in: sourceCode)
        let previewed = PreviewedFile(url: sourceURL, previews: previews.isEmpty ? [] : previews)
        let sources = try PreviewPayloadGenerator.generate(
            moduleFiles: [sourceURL], previewed: [previewed], platform: .macOS,
            into: payloadDir, texts: [sourceURL: sourceCode])
        let output = payloadDir.appendingPathComponent("Preview.dylib")
        let target = PreviewMacHost.deploymentTarget(sdkVersion: Self.macSDKVersion())
        let compiler = PreviewCompiler(platform: .macOS, deploymentTarget: target, moduleName: "Preview", moduleCache: payloadDir)
        do {
            try compiler.compilePayload(sources, output: output)
        } catch let failure as PreviewFailure {
            logHandler("Compilation failed: \(failure.description)")
            throw failure
        }
        return (output, Self.previewIndex(for: targetName, in: sourceCode))
    }

    private static func previewIndex(for targetName: String, in sourceCode: String) -> Int {
        let previews = PreviewDiscovery.previews(in: sourceCode)
        return previews.firstIndex(where: { $0.name == targetName }) ?? 0
    }

    private static func macSDKVersion() -> String {
        let version = (try? Subprocess.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"]))?.stdoutText
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return version.isEmpty ? "15.0" : version
    }

    public func stopRuntime() {
        logger.info("[RUNTIME] Terminating persistent sessions and cleaning resources.")
        loader.unloadCurrentModule()
        activeViewInstances.removeAll()
        activeSessionID = nil
        lastCompiledAt = nil
        isRunning = false
    }
}
