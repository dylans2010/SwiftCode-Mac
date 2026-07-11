import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "XcodeBuild")

@Observable
@MainActor
public final class XcodeBuildManager: Sendable {
    public static let shared = XcodeBuildManager()

    public var isBuilding = false
    public var buildLogs: [String] = []
    public var currentStatus: BuildStatus = .idle
    public var buildDuration: TimeInterval = 0
    public var warningsCount = 0
    public var errorsCount = 0

    public var discoveredSchemes: [String] = []
    public var selectedScheme: String? = nil
    public var selectedConfiguration: String = "Debug"
    public var selectedDestination: String = "generic/platform=macOS"

    public let availableConfigurations = ["Debug", "Release"]
    public let availableDestinations = [
        "generic/platform=macOS",
        "generic/platform=iOS Simulator",
        "generic/platform=iOS"
    ]

    @ObservationIgnored
    private var activeProcess: Process?
    @ObservationIgnored
    private var startTime: Date?
    @ObservationIgnored
    private var durationTimer: Timer?

    public enum BuildStatus: String, Sendable, Codable {
        case idle = "Idle"
        case building = "Building..."
        case succeeded = "Succeeded"
        case failed = "Failed"
        case cancelled = "Cancelled"
        case toolNotFound = "Tool Not Found"
        case permissionFailure = "Permission Failure"
        case invalidProject = "Invalid Project"
    }

    private init() {}

    public func getXcodeBuildPath() -> String {
        UserDefaults.standard.string(forKey: "xcodebuild_executable_path") ?? "/usr/bin/xcodebuild"
    }

    public func setXcodeBuildPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: "xcodebuild_executable_path")
    }

    public func validatePath(_ path: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path)
    }

    public func discoverSchemes(at url: URL) {
        let fm = FileManager.default
        var schemes = Set<String>()

        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                let path = fileURL.path
                if path.contains(".build") || path.contains(".git") || path.contains("DerivedData") || path.contains("node_modules") || path.contains("Pods") || path.contains("build") {
                    enumerator.skipDescendants()
                    continue
                }

                if fileURL.pathExtension == "xcscheme" {
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    schemes.insert(name)
                }
            }
        }

        if schemes.isEmpty {
            for (_, model) in ProjectResolutionService.shared.parsedProjects {
                for target in model.targets {
                    schemes.insert(target.name)
                }
            }
        }

        if schemes.isEmpty {
            schemes.insert(url.lastPathComponent)
        }

        self.discoveredSchemes = Array(schemes).sorted()
        if self.selectedScheme == nil || !self.discoveredSchemes.contains(self.selectedScheme!) {
            self.selectedScheme = self.discoveredSchemes.first
        }
    }

    public func getActiveToolchain() async -> String {
        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcode-select"),
                arguments: ["-p"]
            )
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Unknown (Failed to run xcode-select)"
        }
    }

    public func cancelBuild() {
        guard isBuilding, let process = activeProcess else { return }
        process.terminate()
        currentStatus = .cancelled
        isBuilding = false
        stopTimer()
        appendLog("[SYSTEM] Build cancelled by user.")
    }

    public func runBuild(projectURL: URL, scheme: String? = nil, configuration: String? = nil, destination: String? = nil) async {
        guard !isBuilding else {
            appendLog("[SYSTEM] Warning: A build is already in progress.")
            return
        }

        let buildPath = getXcodeBuildPath()
        guard validatePath(buildPath) else {
            currentStatus = .toolNotFound
            appendLog("[ERROR] xcodebuild tool not found at path: \(buildPath). Please configure the correct path in Settings.")
            return
        }

        let finalScheme = scheme ?? selectedScheme
        let finalConfig = configuration ?? selectedConfiguration
        let finalDest = destination ?? selectedDestination

        isBuilding = true
        currentStatus = .building
        buildLogs.removeAll()
        warningsCount = 0
        errorsCount = 0
        buildDuration = 0
        startTime = Date()
        startTimer()

        appendLog("[SYSTEM] Starting xcodebuild in directory: \(projectURL.path)")
        appendLog("[SYSTEM] Using toolchain path: \(buildPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: buildPath)

        var arguments = ["-configuration", finalConfig]
        if let actualScheme = finalScheme, !actualScheme.isEmpty {
            arguments.append(contentsOf: ["-scheme", actualScheme])
        }
        if let actualDest = finalDest, !actualDest.isEmpty {
            arguments.append(contentsOf: ["-destination", actualDest])
        }

        // Avoid shell interpolation by passing pure argument arrays
        process.arguments = arguments
        process.currentDirectoryURL = projectURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        activeProcess = process

        // Async read from standard output & error
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        Task.detached {
            for try await line in outputHandle.bytes.lines {
                await self.processLogLine(line, isError: false)
            }
        }

        Task.detached {
            for try await line in errorHandle.bytes.lines {
                await self.processLogLine(line, isError: true)
            }
        }

        // Configure termination handler prior to running the process to handle instantaneous terminations safely
        let terminationStatusTask = Task<Int32, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { p in
                    continuation.resume(returning: p.terminationStatus)
                }
            }
        }

        do {
            try process.run()

            // Wait for process completion asynchronously without blocking
            let status = try await terminationStatusTask.value

            stopTimer()
            isBuilding = false
            activeProcess = nil

            if currentStatus == .cancelled {
                return
            }

            if status == 0 {
                currentStatus = .succeeded
                appendLog("[SYSTEM] Build Succeeded.")
            } else {
                currentStatus = .failed
                appendLog("[SYSTEM] Build Failed with exit code \(status).")
            }
        } catch {
            stopTimer()
            isBuilding = false
            activeProcess = nil
            currentStatus = .failed
            appendLog("[ERROR] Failed to launch build process: \(error.localizedDescription)")
            logger.error("Failed to run build: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processLogLine(_ line: String, isError: Bool) {
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLine.isEmpty else { return }

        if cleanLine.lowercased().contains("error:") {
            errorsCount += 1
        } else if cleanLine.lowercased().contains("warning:") {
            warningsCount += 1
        }

        appendLog(cleanLine)
    }

    private func appendLog(_ log: String) {
        buildLogs.append(log)
    }

    // MARK: - Timer Helper

    private func startTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.buildDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
