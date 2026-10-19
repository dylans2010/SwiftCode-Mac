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
    public var selectedScheme: String? = nil {
        didSet {
            UserDefaults.standard.set(selectedScheme, forKey: "com.swiftcode.build.selectedScheme")
        }
    }
    public var selectedConfiguration: String = "Debug" {
        didSet {
            UserDefaults.standard.set(selectedConfiguration, forKey: "com.swiftcode.build.selectedConfiguration")
        }
    }
    public var selectedDestination: String = "platform=macOS" {
        didSet {
            UserDefaults.standard.set(selectedDestination, forKey: "com.swiftcode.build.selectedDestination")
        }
    }

    public var selectedSDKType: String = "Default" {
        didSet {
            UserDefaults.standard.set(selectedSDKType, forKey: "com.swiftcode.build.selectedSDKType")
            // Automatically reset the selected version to "Default" when the platform changes
            if selectedSDKType != oldValue {
                selectedSDKVersion = "Default"
            }
        }
    }
    public var selectedSDKVersion: String = "Default" {
        didSet {
            UserDefaults.standard.set(selectedSDKVersion, forKey: "com.swiftcode.build.selectedSDKVersion")
        }
    }

    public let availableConfigurations = ["Debug", "Release"]
    public let availableDestinations = [
        "platform=macOS",
        "platform=iOS Simulator",
        "platform=visionOS Simulator",
        "platform=watchOS Simulator",
        "platform=tvOS Simulator"
    ]

    // Dynamic SDK detection properties
    public var detectedSDKs: [DetectedSDK] = []
    public var sdkDetectionState: SDKDetectionState = .idle
    public var sdkDetectionError: String? = nil
    public var sdkDetectionStdout: String = ""
    public var sdkDetectionStderr: String = ""
    public var sdkDetectionExitCode: Int32? = nil
    public var activeXcodePath: String = ""

    // MARK: - Fix Build with Assist loop state

    /// Last xcodebuild termination status (nil if the build never launched).
    public var lastExitCode: Int32? = nil
    public var isAssistFixRunning = false
    public var assistFixAttempt = 0
    public let maxAssistFixAttempts = 5
    public var assistFixStatus = ""

    public var availableSDKTypes: [String] {
        if detectedSDKs.isEmpty {
            return ["Default"]
        }
        let platforms = detectedSDKs.map { $0.platform }
        let uniquePlatforms = Set(platforms)
        let sortedPlatforms = Array(uniquePlatforms).sorted()
        return ["Default"] + sortedPlatforms
    }

    public var availableSDKVersions: [String] {
        if selectedSDKType == "Default" {
            return ["Default"]
        }
        let platformFiltered = detectedSDKs.filter { $0.platform == selectedSDKType }
        let versions = platformFiltered.map { $0.version }
        let uniqueVersions = Set(versions)
        let sortedVersions = Array(uniqueVersions).sorted()
        return ["Default"] + sortedVersions
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

    private init() {
        self.selectedScheme = UserDefaults.standard.string(forKey: "com.swiftcode.build.selectedScheme")
        self.selectedConfiguration = UserDefaults.standard.string(forKey: "com.swiftcode.build.selectedConfiguration") ?? "Debug"
        self.selectedDestination = UserDefaults.standard.string(forKey: "com.swiftcode.build.selectedDestination") ?? "platform=macOS"
        self.selectedSDKType = UserDefaults.standard.string(forKey: "com.swiftcode.build.selectedSDKType") ?? "Default"
        self.selectedSDKVersion = UserDefaults.standard.string(forKey: "com.swiftcode.build.selectedSDKVersion") ?? "Default"
    }

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
        if let selected = self.selectedScheme {
            if !self.discoveredSchemes.contains(selected) {
                self.selectedScheme = self.discoveredSchemes.first
            }
        } else {
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

    public func runBuild(projectURL: URL? = nil, scheme: String? = nil, configuration: String? = nil, destination: String? = nil, sdk: String? = nil) async {
        guard !isBuilding else {
            appendLog("[SYSTEM] Warning: A build is already in progress.")
            return
        }

        let effectiveURL = projectURL ?? DocumentCoordinator.shared.projectURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let buildPath = getXcodeBuildPath()
        guard validatePath(buildPath) else {
            currentStatus = .toolNotFound
            appendLog("[ERROR] xcodebuild tool not found at path: \(buildPath). Please configure the correct path in Settings.")
            return
        }

        let finalScheme = scheme ?? selectedScheme ?? effectiveURL.deletingPathExtension().lastPathComponent
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

        appendLog("[SYSTEM] Starting production xcodebuild in directory: \(effectiveURL.path)")
        appendLog("[SYSTEM] Using toolchain path: \(buildPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: buildPath)
        process.currentDirectoryURL = effectiveURL

        let localizedDerivedDataURL = effectiveURL.appendingPathComponent("build/DerivedData")

        var arguments = [
            "-configuration", finalConfig,
            "-derivedDataPath", localizedDerivedDataURL.path
        ]

        if !finalScheme.isEmpty {
            arguments.append(contentsOf: ["-scheme", finalScheme])
        }
        // Add dynamically selected SDK identifier if resolved
        var finalSDK = sdk
        if finalSDK == nil {
            if let activeProj = ProjectSessionStore.shared.activeProject,
               let savedDests = activeProj.destinations,
               let firstSDK = savedDests.first {
                finalSDK = firstSDK
            }
        }
        if finalSDK == nil {
            finalSDK = currentSDKArgument
        }

        var effectiveDest = finalDest
        let isSimulatorTarget = (finalSDK?.lowercased().contains("simulator") == true) || (finalSDK?.lowercased().contains("iphone") == true)
        if isSimulatorTarget && (effectiveDest.lowercased().contains("macos") || effectiveDest.isEmpty || effectiveDest.contains("placeholder")) {
            let sims = await BuildDestinationResolver.shared.fetchAvailableSimulators()
            if let booted = sims.first(where: { $0.variant == "Booted" && !$0.idString.isEmpty }) {
                effectiveDest = booted.id
            } else if let firstSim = sims.first(where: { !$0.idString.isEmpty }) {
                effectiveDest = firstSim.id
            } else {
                effectiveDest = "generic/platform=iOS Simulator"
            }
        }

        if !effectiveDest.isEmpty {
            arguments.append(contentsOf: ["-destination", effectiveDest])
        }

        if let sdkArg = finalSDK {
            arguments.append(contentsOf: ["-sdk", sdkArg])
            appendLog("[SYSTEM] Forcing dynamic target SDK: \(sdkArg)")
        }

        // Add explicit build action and relax code signing for simulator builds
        arguments.append("build")
        if isSimulatorTarget || effectiveDest.lowercased().contains("simulator") {
            arguments.append(contentsOf: [
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO"
            ])
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
            lastExitCode = status

            if currentStatus == .cancelled {
                return
            }

            if buildDidFail(exitCode: status) {
                currentStatus = .failed
                appendLog("[SYSTEM] Build Failed with exit code \(status).")
            } else {
                currentStatus = .succeeded
                appendLog("[SYSTEM] Build Succeeded.")

                await copyGeneratedAppToManagedDirectory(projectURL: effectiveURL, scheme: finalScheme, configuration: finalConfig, destination: finalDest)

                // "Always Build Archive": turn the freshest .app into an .ipa.
                if IPABuildService.shared.alwaysBuildArchive {
                    appendLog("[SYSTEM] Always Build Archive is on — packaging the most up-to-date .app…")
                    let outDir = ((UserDefaults.standard.string(forKey: "com.swiftcode.ipa.outputDirectory") ?? "~/Desktop") as NSString).expandingTildeInPath
                    let archiveResult = await IPABuildService.shared.packageLatestApp(
                        projectName: effectiveURL.deletingPathExtension().lastPathComponent,
                        outputDirectory: outDir
                    )
                    if archiveResult.success {
                        appendLog("[SYSTEM] Latest Archive updated: \(archiveResult.ipaPath ?? "")")
                    } else {
                        appendLog("[ERROR] Archive packaging failed: \(archiveResult.errorMessage ?? "unknown error")")
                    }
                }
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

    // MARK: - Fix Build with Assist

    /// A build counts as failed when xcodebuild exits non-zero OR the log
    /// explicitly reports "BUILD FAILED".
    public func buildDidFail(exitCode: Int32) -> Bool {
        if exitCode != 0 { return true }
        return buildLogs.joined(separator: "\n").localizedCaseInsensitiveContains("BUILD FAILED")
    }

    /// Starts the iterative Assist repair loop. Captures all logs plus project
    /// context, opens Assist in a new session with the diagnostic bundle, then
    /// rebuilds to verify. The loop ONLY finishes when xcodebuild reports
    /// "BUILD SUCCEEDED" (exit code 0); it stops after `maxAssistFixAttempts`
    /// attempts and surfaces the failure to the user.
    public func startAssistFixLoop() {
        guard !isAssistFixRunning, !isBuilding else { return }
        guard currentStatus == .failed || errorsCount > 0 || buildDidFail(exitCode: lastExitCode ?? -1) else {
            appendLog("[SYSTEM] Fix Build with Assist: nothing to fix — the last build did not fail.")
            return
        }
        isAssistFixRunning = true
        assistFixAttempt = 0
        assistFixStatus = "Starting Assist repair…"
        appendLog("[SYSTEM] Fix Build with Assist started (up to \(maxAssistFixAttempts) attempts).")
        Task { await runAssistFixLoop() }
    }

    public func stopAssistFixLoop() {
        guard isAssistFixRunning else { return }
        isAssistFixRunning = false
        assistFixStatus = "Stopped by user."
        appendLog("[SYSTEM] Fix Build with Assist stopped by user.")
    }

    private func runAssistFixLoop() async {
        while isAssistFixRunning && assistFixAttempt < maxAssistFixAttempts {
            assistFixAttempt += 1
            let attempt = assistFixAttempt
            assistFixStatus = "Attempt \(attempt) of \(maxAssistFixAttempts): Assist is fixing…"
            appendLog("[SYSTEM] Fix attempt \(attempt)/\(maxAssistFixAttempts): sending diagnostics to Assist…")

            let bundle = buildDiagnosticBundle()
            let prompt = """
            The Xcode build failed and needs fixing. This is repair attempt \(attempt) of \(maxAssistFixAttempts).

            Diagnose the errors in the bundle below and apply real fixes to the project code (edit files, adjust build settings, fix imports — whatever the errors require). When you finish fixing, reply with a short summary of what you changed. I will rebuild automatically to verify.

            \(bundle)
            """

            if attempt == 1 {
                await MainActor.run {
                    AssistNavigationRouter.revealAssistPanel()
                    AssistManager.shared.clearSession()
                }
            } else {
                await MainActor.run { AssistNavigationRouter.revealAssistPanel() }
            }

            // sendMessage awaits the full Assist turn, so when it returns the
            // fixes (if any) are in place and we can rebuild to verify.
            await AssistManager.shared.sendMessage(prompt)

            guard isAssistFixRunning else { break }

            assistFixStatus = "Attempt \(attempt) of \(maxAssistFixAttempts): rebuilding to verify…"
            appendLog("[SYSTEM] Fix attempt \(attempt): rebuilding to verify…")
            await runBuild()

            let logText = buildLogs.joined(separator: "\n")
            let succeeded = currentStatus == .succeeded
                || (lastExitCode == 0 && !buildDidFail(exitCode: lastExitCode ?? -1))
                || logText.localizedCaseInsensitiveContains("BUILD SUCCEEDED")

            if succeeded {
                assistFixStatus = "Build succeeded after \(attempt) attempt(s)."
                appendLog("[SYSTEM] Fix Build with Assist: BUILD SUCCEEDED on attempt \(attempt).")
                isAssistFixRunning = false
                return
            }

            appendLog("[ERROR] Fix attempt \(attempt) still failing — preparing next attempt.", isError: true)
        }

        if isAssistFixRunning {
            isAssistFixRunning = false
            assistFixStatus = "All \(maxAssistFixAttempts) attempts exhausted — manual review needed."
            appendLog("[ERROR] Fix Build with Assist: exhausted \(maxAssistFixAttempts) attempts without BUILD SUCCEEDED. The full logs above are available for manual review.", isError: true)
        }
    }

    /// Full diagnostic bundle: project context, failed command, error lines, log tail.
    private func buildDiagnosticBundle() -> String {
        let errorLines = buildLogs.filter { $0.lowercased().contains("error") }.suffix(40)
        let tail = buildLogs.suffix(60)
        let failedCommand = buildCommandDescription()
        return """
        ## Build context
        - Project: \(DocumentCoordinator.shared.projectURL?.path ?? "unknown")
        - Scheme: \(selectedScheme ?? "Automatic")
        - Configuration: \(selectedConfiguration)
        - Destination: \(selectedDestination)
        - SDK argument: \(currentSDKArgument ?? "default")
        - xcodebuild path: \(getXcodeBuildPath())
        - Failed command: \(failedCommand)
        - Exit code: \(lastExitCode.map(String.init) ?? "unknown")
        - Errors: \(errorsCount), Warnings: \(warningsCount)

        ## Error lines (\(errorLines.count))
        \(errorLines.joined(separator: "\n"))

        ## Log tail
        \(tail.joined(separator: "\n"))
        """
    }

    private func buildCommandDescription() -> String {
        let path = getXcodeBuildPath()
        let scheme = selectedScheme ?? "Automatic"
        return "\(path) -scheme \(scheme) -configuration \(selectedConfiguration) -destination \"\(selectedDestination)\" build"
    }

    public func cleanBuild(projectURL: URL? = nil) {
        if let url = projectURL ?? ProjectSessionStore.shared.activeProject?.directoryURL {
            let derivedData = url.appendingPathComponent("build/DerivedData")
            try? FileManager.default.removeItem(at: derivedData)
        }
        buildLogs.removeAll()
        warningsCount = 0
        errorsCount = 0
        appendLog("[SYSTEM] Cleaned localized build folder.")
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
