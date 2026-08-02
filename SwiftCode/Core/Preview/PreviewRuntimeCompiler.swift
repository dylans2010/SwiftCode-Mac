import Foundation

#if os(macOS)
import class Foundation.Process
#endif

public struct CompiledPreviewModule: Sendable {
    public let libraryURL: URL
    public let diagnostics: [PreviewCompilationDiagnostic]
    public let metadata: [String: String]
}

public struct PreviewCompilationDiagnostic: Sendable, Identifiable {
    public let id = UUID()
    public let message: String
    public let file: String?
    public let line: Int?
}

/// Actor-isolated compiler coordinates native swiftc live SwiftUI library generation.
public actor PreviewRuntimeCompiler {
    private var cachedSignatures: [URL: Date] = [:]

    public init() {}

    public func compile(
        projectStructure: PreviewProjectStructure,
        entry: PreviewSimulationEntry,
        sandboxPolicy: PreviewSandboxPolicy
    ) async throws -> CompiledPreviewModule {
        let uniqueID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let uniqueModuleName = "SimulationApp_\(uniqueID)"

        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swiftcode-simulation", isDirectory: true)
            .appendingPathComponent(uniqueID, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        // Read active files to parse previews
        var parsedPreviews: [ParsedPreview] = []
        for file in projectStructure.swiftFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                let parsed = PreviewBlockParser.parsePreviews(in: content)
                parsedPreviews.append(contentsOf: parsed)
            }
        }

        let bootstrapFile = temporaryRoot.appendingPathComponent("SimulationBootstrap.swift")
        let bootstrapSource = makeBootstrapSource(viewTypes: projectStructure.swiftUIViewTypes, defaultRoot: entry.rootViewType, parsedPreviews: parsedPreviews)
        try bootstrapSource.write(to: bootstrapFile, atomically: true, encoding: .utf8)

        let outputLibrary = temporaryRoot.appendingPathComponent("lib\(uniqueModuleName).dylib")

        // Isolate files into temporary folder with unique names to completely avoid duplicate filename conflicts
        var isolatedFiles: [URL] = []
        var seenFilenames: [String: Int] = [:]

        for file in projectStructure.swiftFiles {
            let originalName = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension

            var uniqueName = originalName
            if let count = seenFilenames[originalName.lowercased()] {
                seenFilenames[originalName.lowercased()] = count + 1
                uniqueName = "\(originalName)_\(count + 1)"
            } else {
                seenFilenames[originalName.lowercased()] = 1
            }

            let targetFileURL = temporaryRoot.appendingPathComponent("\(uniqueName).\(ext)")
            try? FileManager.default.copyItem(at: file, to: targetFileURL)
            isolatedFiles.append(targetFileURL)
        }

        let changedFiles = changedSwiftFiles(in: isolatedFiles)
        let allInputs = isolatedFiles + [bootstrapFile]

#if os(macOS)
        let process = Process()

        // Use a direct path to swiftc if possible to avoid xcrun sandbox issues
        let swiftcPaths = [
            "/usr/bin/swiftc",
            "/usr/local/bin/swiftc",
            "/opt/homebrew/bin/swiftc"
        ]

        var resolvedSwiftc = URL(fileURLWithPath: "/usr/bin/swiftc")
        for path in swiftcPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                resolvedSwiftc = URL(fileURLWithPath: path)
                break
            }
        }

        process.executableURL = resolvedSwiftc
        process.currentDirectoryURL = sandboxPolicy.projectDirectory
        process.arguments = [
            "-swift-version", "6",
            "-emit-library",
            "-module-name", uniqueModuleName,
            "-o", outputLibrary.path
        ] + allInputs.map(\.path)

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()

        // Implement compile process timeout handling to prevent indefinite compile blocks
        let timeout: TimeInterval = 20.0
        let startTime = Date()

        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                throw PreviewError.compilationError(details: "Compiler timed out after \(timeout) seconds.")
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Unknown compiler error"
            throw parseCompilerError(message)
        }
#else
        throw PreviewError.compilationError(details: "Dynamic compilation is not supported on iOS.")
#endif

        var metadata: [String: String] = [
            "inputs": "\(allInputs.count)",
            "incrementalChangedFiles": "\(changedFiles.count)",
            "rootView": entry.rootViewType
        ]
        metadata["sandboxNetwork"] = sandboxPolicy.allowNetwork ? "enabled" : "disabled"

        return CompiledPreviewModule(libraryURL: outputLibrary, diagnostics: [], metadata: metadata)
    }

    private func changedSwiftFiles(in files: [URL]) -> [URL] {
        var changed: [URL] = []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if cachedSignatures[file] != modified {
                cachedSignatures[file] = modified
                changed.append(file)
            }
        }
        return changed
    }

    private func parseCompilerError(_ message: String) -> PreviewError {
        let parts = message.components(separatedBy: ":")
        if parts.count > 3 {
            let body = parts.dropFirst(3).joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return PreviewError.compilationError(details: body.isEmpty ? message : body)
        }
        return PreviewError.compilationError(details: message)
    }

    private func makeBootstrapSource(viewTypes: [String], defaultRoot: String, parsedPreviews: [ParsedPreview]) -> String {
        var cases: [String] = []

        // Add cases for parsed #Previews
        for preview in parsedPreviews {
            cases.append("case \"\(preview.title)\": root = AnyView({\n            \(preview.body)\n        }())")
        }

        // Add default cases for bare views
        for viewType in viewTypes {
            if !parsedPreviews.contains(where: { $0.title == viewType }) {
                cases.append("case \"\(viewType)\": root = AnyView(\(viewType)())")
            }
        }

        // Add case for default root
        if !parsedPreviews.contains(where: { $0.title == defaultRoot }) && !viewTypes.contains(defaultRoot) {
            cases.append("case \"\(defaultRoot)\": root = AnyView(\(defaultRoot)())")
        }

        let casesString = cases.joined(separator: "\n        ")

        return """
        import SwiftUI
        import AppKit

        @_cdecl("__swiftcode_make_hosting_view")
        public func __swiftcode_make_hosting_view(_ viewNamePtr: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
            let requested = viewNamePtr.map { String(cString: $0) } ?? "\(defaultRoot)"
            var root = AnyView(Text("Unknown Target View"))

            switch requested {
            \(casesString)
            default:
                break
            }

            let hostingView = NSHostingView(rootView: root)
            hostingView.frame = NSRect(x: 0, y: 0, width: 393, height: 852)
            return Unmanaged.passRetained(hostingView).toOpaque()
        }
        """
    }
}
