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

    // Dynamic Scheme Discovery
    public var availableSchemes: [String] = []
    public var selectedScheme: String?

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

    // Dynamic Scheme & Target Discovery
    public func discoverSchemes(in projectURL: URL) async -> [String] {
        var schemes: Set<String> = []
        let fm = FileManager.default

        // 1. Filesystem Scan for .xcscheme files
        if let enumerator = fm.enumerator(at: projectURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension
                if ext == "xcodeproj" || ext == "xcworkspace" {
                    // Shared schemes
                    let sharedSchemesURL = fileURL.appendingPathComponent("xcshareddata/xcschemes")
                    if let files = try? fm.contentsOfDirectory(at: sharedSchemesURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                        for file in files where file.pathExtension == "xcscheme" {
                            schemes.insert(file.deletingPathExtension().lastPathComponent)
                        }
                    }
                    // User schemes
                    let xcuserDataURL = fileURL.appendingPathComponent("xcuserdata")
                    if let userContents = try? fm.contentsOfDirectory(at: xcuserDataURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
                        for userDir in userContents {
                            let userSchemesURL = userDir.appendingPathComponent("xcschemes")
                            if let files = try? fm.contentsOfDirectory(at: userSchemesURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                                for file in files where file.pathExtension == "xcscheme" {
                                    schemes.insert(file.deletingPathExtension().lastPathComponent)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Fallback: Parse target names from cached XcodeProjModel
        let cachedModels = await ProjectResolutionService.shared.parsedProjects
        for model in cachedModels.values {
            for target in model.targets {
                schemes.insert(target.name)
            }
        }

        // 3. Fallback: Run xcodebuild -list
        let xcodebuildPath = getXcodeBuildPath()
        if validatePath(xcodebuildPath) {
            do {
                let listResult = try await ProcessRunnerTool.shared.run(
                    executableURL: URL(fileURLWithPath: xcodebuildPath),
                    arguments: ["-list"],
                    workingDirectory: projectURL
                )
                if listResult.exitCode == 0 {
                    let lines = listResult.stdout.components(separatedBy: .newlines)
                    var isParsingSchemes = false
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasSuffix("Schemes:") {
                            isParsingSchemes = true
                            continue
                        } else if trimmed.isEmpty && isParsingSchemes {
                            // Empty line after schemes start
                        }
                        if isParsingSchemes {
                            if trimmed.hasSuffix("Targets:") || trimmed.hasSuffix("Build Configurations:") {
                                isParsingSchemes = false
                            } else if !trimmed.isEmpty {
                                schemes.insert(trimmed)
                            }
                        }
                    }
                }
            } catch {
                logger.error("xcodebuild -list failed: \(error.localizedDescription)")
            }
        }

        // 4. Default Fallback
        if schemes.isEmpty {
            schemes.insert("App")
        }

        let sortedSchemes = schemes.sorted()
        self.availableSchemes = sortedSchemes
        if self.selectedScheme == nil || !sortedSchemes.contains(self.selectedScheme ?? "") {
            self.selectedScheme = sortedSchemes.first
        }

        logger.info("Discovered schemes in \(projectURL.path): \(sortedSchemes)")
        return sortedSchemes
    }

    public func runBuild(projectURL: URL, scheme: String?, configuration: String = "Debug", destination: String? = nil) async {
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

        // Auto-discover schemes if none exist
        if availableSchemes.isEmpty {
            _ = await discoverSchemes(in: projectURL)
        }

        let activeScheme = scheme ?? selectedScheme ?? availableSchemes.first ?? "App"

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
        appendLog("[SYSTEM] Active build scheme: \(activeScheme)")
        appendLog("[SYSTEM] Active build configuration: \(configuration)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: buildPath)

        // Dynamically find workspace or xcodeproj
        var arguments: [String] = []
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            if let workspace = contents.first(where: { $0.pathExtension == "xcworkspace" }) {
                arguments.append(contentsOf: ["-workspace", workspace.lastPathComponent])
            } else if let project = contents.first(where: { $0.pathExtension == "xcodeproj" }) {
                arguments.append(contentsOf: ["-project", project.lastPathComponent])
            }
        }

        arguments.append(contentsOf: ["-scheme", activeScheme])
        arguments.append(contentsOf: ["-configuration", configuration])

        if let destination = destination, !destination.isEmpty {
            arguments.append(contentsOf: ["-destination", destination])
        } else {
            // Automatic destination resolution: build for macOS if target supports it, fallback to generic simulator
            arguments.append(contentsOf: ["-destination", "generic/platform=iOS Simulator"])
        }

        process.arguments = arguments
        process.currentDirectoryURL = projectURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        activeProcess = process

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
