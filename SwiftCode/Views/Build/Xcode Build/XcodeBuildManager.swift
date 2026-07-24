import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "XcodeBuild")

public struct DetectedSDK: Sendable, Identifiable, Codable, Hashable {
    public var id: String { identifier }
    public let identifier: String
    public let platform: String
    public let displayName: String
    public let version: String

    public init(identifier: String, platform: String, displayName: String, version: String) {
        self.identifier = identifier
        self.platform = platform
        self.displayName = displayName
        self.version = version
    }
}

public enum SDKDetectionState: Sendable, Codable, Equatable {
    case idle
    case detecting
    case success
    case failure
}

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
    public var selectedDestination: String = "generic/platform=iOS Simulator"

    public var selectedSDKType: String = "Default" {
        didSet {
            // Automatically reset the selected version to "Default" when the platform changes
            if selectedSDKType != oldValue {
                selectedSDKVersion = "Default"
            }
        }
    }
    public var selectedSDKVersion: String = "Default"

    public let availableConfigurations = ["Debug", "Release"]
    public let availableDestinations = [
        "generic/platform=iOS Simulator",
        "generic/platform=iOS",
        "generic/platform=macOS"
    ]

    // Dynamic SDK detection properties
    public var detectedSDKs: [DetectedSDK] = []
    public var sdkDetectionState: SDKDetectionState = .idle
    public var sdkDetectionError: String? = nil
    public var sdkDetectionStdout: String = ""
    public var sdkDetectionStderr: String = ""
    public var sdkDetectionExitCode: Int32? = nil
    public var activeXcodePath: String = ""

    public var availableSDKTypes: [String] {
        if detectedSDKs.isEmpty {
            return ["Default"]
        }
        return ["Default"] + Array(Set(detectedSDKs.map { $0.platform })).sorted()
    }

    public var availableSDKVersions: [String] {
        if selectedSDKType == "Default" {
            return ["Default"]
        }
        let versions = detectedSDKs
            .filter { $0.platform == selectedSDKType }
            .map { $0.version }
        return ["Default"] + Array(Set(versions)).sorted()
    }

    public var currentSDKArgument: String? {
        guard selectedSDKType != "Default" else { return nil }

        let platformSDKs = detectedSDKs.filter { $0.platform == selectedSDKType }
        guard !platformSDKs.isEmpty else { return nil }

        if selectedSDKVersion != "Default" && !selectedSDKVersion.isEmpty {
            if let matched = platformSDKs.first(where: { $0.version == selectedSDKVersion }) {
                return matched.identifier
            }
            // Fallback: construct it from first SDK's prefix
            if let firstSDK = platformSDKs.first {
                let prefix = String(firstSDK.identifier.prefix { $0.isLetter })
                return "\(prefix)\(selectedSDKVersion)"
            }
        } else {
            // Version is "Default", we want to pass the generic platform prefix (e.g. "macosx", "iphoneos")
            if let firstSDK = platformSDKs.first {
                return String(firstSDK.identifier.prefix { $0.isLetter })
            }
        }
        return nil
    }

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

    // Dynamic SDK detection logic
    public func detectAvailableSDKs(forceRefresh: Bool = false) async {
        guard sdkDetectionState != .detecting else { return }

        sdkDetectionState = .detecting
        sdkDetectionError = nil
        sdkDetectionStdout = ""
        sdkDetectionStderr = ""
        sdkDetectionExitCode = nil

        do {
            let xcodeSelectURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            guard FileManager.default.fileExists(atPath: xcodeSelectURL.path) else {
                throw NSError(domain: "XcodeBuildManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "xcode-select tool not found at /usr/bin/xcode-select"])
            }

            if Task.isCancelled { return }

            let xcodeSelectResult = try await ProcessRunnerTool.shared.run(
                executableURL: xcodeSelectURL,
                arguments: ["-p"]
            )

            if xcodeSelectResult.exitCode != 0 {
                sdkDetectionExitCode = xcodeSelectResult.exitCode
                sdkDetectionStdout = xcodeSelectResult.stdout
                sdkDetectionStderr = xcodeSelectResult.stderr
                throw NSError(domain: "XcodeBuildManager", code: Int(xcodeSelectResult.exitCode), userInfo: [NSLocalizedDescriptionKey: "xcode-select -p failed: \(xcodeSelectResult.stderr)"])
            }

            let newXcodePath = xcodeSelectResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            // If active path is unchanged and we already have parsed SDKs, use cached results
            if !forceRefresh && newXcodePath == activeXcodePath && !detectedSDKs.isEmpty {
                sdkDetectionState = .success
                return
            }

            activeXcodePath = newXcodePath

            let buildPath = getXcodeBuildPath()
            let xcodebuildURL = URL(fileURLWithPath: buildPath)
            guard FileManager.default.fileExists(atPath: buildPath) else {
                throw NSError(domain: "XcodeBuildManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "xcodebuild not found at \(buildPath)"])
            }

            if Task.isCancelled { return }

            let showSDKsResult = try await ProcessRunnerTool.shared.run(
                executableURL: xcodebuildURL,
                arguments: ["-showsdks"]
            )

            sdkDetectionStdout = showSDKsResult.stdout
            sdkDetectionStderr = showSDKsResult.stderr
            sdkDetectionExitCode = showSDKsResult.exitCode

            if showSDKsResult.exitCode != 0 {
                throw NSError(domain: "XcodeBuildManager", code: Int(showSDKsResult.exitCode), userInfo: [NSLocalizedDescriptionKey: "xcodebuild -showsdks failed with exit code \(showSDKsResult.exitCode):\n\(showSDKsResult.stderr)"])
            }

            if Task.isCancelled { return }

            let sdkList = parseShowSDKsOutput(showSDKsResult.stdout)
            if sdkList.isEmpty {
                throw NSError(domain: "XcodeBuildManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "No SDKs were found in xcodebuild output."])
            }

            self.detectedSDKs = sdkList
            self.sdkDetectionState = .success

            // Validate selections
            if !availableSDKTypes.contains(selectedSDKType) {
                selectedSDKType = "Default"
            }
            if !availableSDKVersions.contains(selectedSDKVersion) {
                selectedSDKVersion = "Default"
            }

        } catch {
            self.sdkDetectionError = error.localizedDescription
            self.sdkDetectionState = .failure
        }
    }

    public func parseShowSDKsOutput(_ output: String) -> [DetectedSDK] {
        var sdks: [DetectedSDK] = []
        let lines = output.components(separatedBy: .newlines)

        var currentPlatformGroup: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.hasSuffix(" SDKs:") {
                currentPlatformGroup = trimmed.replacingOccurrences(of: " SDKs:", with: "")
                continue
            }

            if trimmed.contains("-sdk") {
                let components = trimmed.components(separatedBy: "-sdk")
                guard components.count >= 2 else { continue }

                let displayName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let identifier = components[1].trimmingCharacters(in: .whitespacesAndNewlines)

                // Extract version: drop alphabetic prefix of identifier
                var version = String(identifier.drop { !$0.isNumber })

                if version.isEmpty {
                    let words = displayName.components(separatedBy: .whitespaces)
                    if let versionWord = words.last(where: { word in
                        word.contains(where: { $0.isNumber })
                    }) {
                        version = versionWord
                    } else {
                        version = "Unknown"
                    }
                }

                var platform = currentPlatformGroup ?? ""

                if platform.isEmpty {
                    let identifierLower = identifier.lowercased()
                    if identifierLower.hasPrefix("macosx") {
                        platform = "macOS"
                    } else if identifierLower.hasPrefix("iphonesimulator") {
                        platform = "iOS Simulator"
                    } else if identifierLower.hasPrefix("iphoneos") {
                        platform = "iOS"
                    } else if identifierLower.hasPrefix("watchsimulator") {
                        platform = "watchOS Simulator"
                    } else if identifierLower.hasPrefix("watchos") {
                        platform = "watchOS"
                    } else if identifierLower.hasPrefix("appletvsimulator") {
                        platform = "tvOS Simulator"
                    } else if identifierLower.hasPrefix("appletvos") {
                        platform = "tvOS"
                    } else if identifierLower.hasPrefix("driverkit") {
                        platform = "DriverKit"
                    } else if identifierLower.hasPrefix("xrsimulator") || identifierLower.hasPrefix("visionosssimulator") || identifierLower.hasPrefix("visonosssimulator") {
                        platform = "visionOS Simulator"
                    } else if identifierLower.hasPrefix("xros") || identifierLower.hasPrefix("visionos") {
                        platform = "visionOS"
                    } else {
                        let letters = String(identifier.prefix { $0.isLetter })
                        platform = letters.isEmpty ? "Unknown" : letters
                    }
                }

                let sdk = DetectedSDK(
                    identifier: identifier,
                    platform: platform,
                    displayName: displayName,
                    version: version
                )
                sdks.append(sdk)
            }
        }

        return sdks
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

        let finalScheme = scheme ?? selectedScheme ?? projectURL.deletingPathExtension().lastPathComponent
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

        appendLog("[SYSTEM] Starting production xcodebuild in directory: \(projectURL.path)")
        appendLog("[SYSTEM] Using toolchain path: \(buildPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: buildPath)

        let localizedDerivedDataURL = projectURL.appendingPathComponent("build/DerivedData")

        var arguments = [
            "-configuration", finalConfig,
            "-derivedDataPath", localizedDerivedDataURL.path
        ]

        if !finalScheme.isEmpty {
            arguments.append(contentsOf: ["-scheme", finalScheme])
        }
        if !finalDest.isEmpty {
            arguments.append(contentsOf: ["-destination", finalDest])
        }

        // Add dynamically selected SDK identifier if resolved
        if let sdkArg = currentSDKArgument {
            arguments.append(contentsOf: ["-sdk", sdkArg])
            appendLog("[SYSTEM] Forcing dynamic target SDK: \(sdkArg)")
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

                await copyGeneratedAppToManagedDirectory(projectURL: projectURL, scheme: finalScheme, configuration: finalConfig, destination: finalDest)
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

    private func copyGeneratedAppToManagedDirectory(projectURL: URL, scheme: String, configuration: String, destination: String) async {
        appendLog("[SYSTEM] Initiating .app packaging alignment pass...")

        let fm = FileManager.default
        let productsURL = projectURL.appendingPathComponent("build/DerivedData/Build/Products")

        guard fm.fileExists(atPath: productsURL.path) else {
            appendLog("[WARNING] Localized build products directory not found: \(productsURL.path)")
            return
        }

        do {
            let folders = try fm.contentsOfDirectory(at: productsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

            var foundAppURL: URL? = nil
            for folder in folders {
                let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                if let appFile = items.first(where: { $0.pathExtension == "app" }) {
                    foundAppURL = appFile
                    break
                }
            }

            guard let appURL = foundAppURL else {
                appendLog("[WARNING] Failed to locate generated .app bundle inside \(productsURL.path).")
                return
            }

            appendLog("[SYSTEM] Located compiled application package: \(appURL.path)")

            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let buildsDir = appSupport.appendingPathComponent("SwiftCode/Builds/\(projectURL.lastPathComponent)")

            if fm.fileExists(atPath: buildsDir.path) {
                try fm.removeItem(at: buildsDir)
            }
            try fm.createDirectory(at: buildsDir, withIntermediateDirectories: true, attributes: nil)

            let destURL = buildsDir.appendingPathComponent(appURL.lastPathComponent)
            try fm.copyItem(at: appURL, to: destURL)

            appendLog("[SYSTEM] Copied .app to managed packaging workspace successfully!")
            appendLog("[SYSTEM] Path: \(destURL.path)")

        } catch {
            appendLog("[ERROR] Failed to align .app packaging bundle: \(error.localizedDescription)")
        }
    }
}
