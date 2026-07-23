import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "IPABuildService")

public enum IPABuildState: String, Sendable, Codable {
    case idle = "Idle"
    case packaging = "Packaging IPA..."
    case succeeded = "Succeeded"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

public struct IPABuildLogEntry: Identifiable, Sendable, Codable {
    public let id = UUID()
    public let timestamp = Date()
    public let message: String
    public let isError: Bool
}

public struct IPABuildResult: Sendable, Codable {
    public let success: Bool
    public let ipaPath: String?
    public let errorMessage: String?
}

public struct SelectedApp: Identifiable, Sendable, Codable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bundleID: String
    public let version: String
    public let build: String
    public let minOS: String
    public let fileSize: String
    public let buildConfiguration: String
    public let lastModified: String
    public let signingStatus: String
}

@Observable
@MainActor
public final class IPABuildService: Sendable {
    public static let shared = IPABuildService()

    public var buildState: IPABuildState = .idle
    public var logs: [IPABuildLogEntry] = []
    public var currentProgress: Double = 0.0
    public var progressDescription = "Waiting to begin..."

    @ObservationIgnored
    private var activeProcess: Process?
    @ObservationIgnored
    private var startTime: Date?

    private init() {}

    public func getShellScriptPath() -> String {
        return Bundle.main.path(forResource: "build_ipa", ofType: "sh") ?? "SwiftCode/Resources/build_ipa.sh"
    }

    public func cancelPackaging() {
        guard buildState == .packaging, let process = activeProcess else { return }
        process.terminate()
        buildState = .cancelled
        appendLog("[SYSTEM] Packaging aborted by user.", isError: true)
    }

    public func packageAppIntoIPA(appPath: String, outputDirectory: String, customIPAName: String? = nil) async -> IPABuildResult {
        guard buildState != .packaging else {
            return IPABuildResult(success: false, ipaPath: nil, errorMessage: "Packaging in progress.")
        }

        buildState = .packaging
        logs.removeAll()
        currentProgress = 0.1
        progressDescription = "Validating app bundle structures..."
        startTime = Date()

        appendLog("[SYSTEM] Launching IPA build pipeline process...", isError: false)

        let scriptPath = getShellScriptPath()
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptPath) else {
            buildState = .failed
            let errMsg = "Shell script not found at path: \(scriptPath)"
            appendLog("[ERROR] \(errMsg)", isError: true)
            return IPABuildResult(success: false, ipaPath: nil, errorMessage: errMsg)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        var arguments = [scriptPath, appPath, outputDirectory]
        if let customName = customIPAName, !customName.isEmpty {
            arguments.append(customName)
        }
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        activeProcess = process

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        Task.detached {
            for try await line in outputHandle.bytes.lines {
                await self.parseAndLogShellLine(line, isError: false)
            }
        }

        Task.detached {
            for try await line in errorHandle.bytes.lines {
                await self.parseAndLogShellLine(line, isError: true)
            }
        }

        let terminationStatusTask = Task<Int32, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { p in
                    continuation.resume(returning: p.terminationStatus)
                }
            }
        }

        do {
            try process.run()

            let status = try await terminationStatusTask.value

            activeProcess = nil

            if buildState == .cancelled {
                return IPABuildResult(success: false, ipaPath: nil, errorMessage: "Cancelled by user.")
            }

            if status == 0 {
                buildState = .succeeded
                currentProgress = 1.0
                progressDescription = "Packaging succeeded!"

                // Locate the IPA file
                let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                let finalName = customIPAName ?? "\(appName.replacingOccurrences(of: " ", with: "_")).ipa"
                let ipaPath = (outputDirectory as NSString).appendingPathComponent(finalName)

                appendLog("[SYSTEM] IPA Build completed successfully: \(ipaPath)", isError: false)
                return IPABuildResult(success: true, ipaPath: ipaPath, errorMessage: nil)
            } else {
                buildState = .failed
                currentProgress = 0.0
                progressDescription = "Packaging failed."
                let errMsg = "Process exited with code \(status)."
                appendLog("[ERROR] \(errMsg)", isError: true)
                return IPABuildResult(success: false, ipaPath: nil, errorMessage: errMsg)
            }
        } catch {
            activeProcess = nil
            buildState = .failed
            currentProgress = 0.0
            progressDescription = "Failed to launch pipeline."
            let errMsg = error.localizedDescription
            appendLog("[ERROR] Failed to run process: \(errMsg)", isError: true)
            return IPABuildResult(success: false, ipaPath: nil, errorMessage: errMsg)
        }
    }

    private func parseAndLogShellLine(_ line: String, isError: Bool) {
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if clean.hasPrefix("[SHELL]") {
            progressDescription = clean.replacingOccurrences(of: "[SHELL] ", with: "")
            currentProgress += 0.1
            if currentProgress > 0.9 { currentProgress = 0.9 }
        } else if clean.hasPrefix("[SUCCESS]") {
            progressDescription = "Packaging container successful!"
            currentProgress = 1.0
        }

        appendLog(clean, isError: isError)
    }

    private func appendLog(_ message: String, isError: Bool) {
        logs.append(IPABuildLogEntry(message: message, isError: isError))
    }
}
