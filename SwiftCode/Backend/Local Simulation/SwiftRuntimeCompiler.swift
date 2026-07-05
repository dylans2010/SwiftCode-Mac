import Foundation

#if os(macOS)
import class Foundation.Process
#endif

final class SwiftRuntimeCompiler {
    private var cachedSignatures: [URL: Date] = [:]

    func compile(projectStructure: ProjectStructure, entry: SimulationEntry, sandboxPolicy: SimulationSandboxPolicy) async throws -> CompiledSimulationModule {
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swiftcode-simulation", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let bootstrapFile = temporaryRoot.appendingPathComponent("SimulationBootstrap.swift")
        let bootstrapSource = makeBootstrapSource(viewTypes: projectStructure.swiftUIViewTypes, defaultRoot: entry.rootViewType)
        try bootstrapSource.write(to: bootstrapFile, atomically: true, encoding: .utf8)

        let outputLibrary = temporaryRoot.appendingPathComponent("libSimulationApp.dylib")

        let changedFiles = changedSwiftFiles(in: projectStructure.swiftFiles)
        let allInputs = projectStructure.swiftFiles + [bootstrapFile]

#if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.currentDirectoryURL = sandboxPolicy.projectDirectory
        process.arguments = [
            "swiftc",
            "-swift-version", "6",
            "-emit-library",
            "-module-name", "SimulationApp",
            "-o", outputLibrary.path
        ] + allInputs.map(\.path)

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Unknown compiler error"
            throw parseCompilerError(message)
        }
#else
        throw SimulationError(
            type: .compile,
            message: "Dynamic compilation is not supported on iOS.",
            file: nil,
            line: nil,
            stackTrace: nil
        )
#endif

        var metadata: [String: String] = [
            "inputs": "\(allInputs.count)",
            "incrementalChangedFiles": "\(changedFiles.count)",
            "rootView": entry.rootViewType
        ]
        metadata["sandboxNetwork"] = sandboxPolicy.allowNetwork ? "enabled" : "disabled"

        return CompiledSimulationModule(libraryURL: outputLibrary, diagnostics: [], metadata: metadata)
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

    private func parseCompilerError(_ message: String) -> SimulationError {
        let parts = message.components(separatedBy: ":")
        if parts.count > 3 {
            let file = parts[0]
            let line = Int(parts[1])
            let body = parts.dropFirst(3).joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return SimulationError(type: .compile, message: body.isEmpty ? message : body, file: file, line: line, stackTrace: nil)
        }
        return SimulationError(type: .compile, message: message, file: nil, line: nil, stackTrace: nil)
    }

    private func makeBootstrapSource(viewTypes: [String], defaultRoot: String) -> String {
        let cases = viewTypes.map { viewType in
            "case \"\(viewType)\": resolved = \"\(viewType)\""
        }.joined(separator: "\n            ")

        return """
        import SwiftUI
        import Foundation

        @_cdecl("__swiftcode_make_root_view")
        public func __swiftcode_make_root_view(_ viewNamePtr: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
            let requested = viewNamePtr.map { String(cString: $0) } ?? "\(defaultRoot)"
            let resolved: String
            switch requested {
            \(cases)
            default:
                resolved = "\(defaultRoot)"
            }
            return strdup(resolved)
        }
        """
    }
}
