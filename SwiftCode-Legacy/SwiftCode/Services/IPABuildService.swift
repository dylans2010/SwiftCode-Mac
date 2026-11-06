import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "IPABuildService")

public enum IPABuildState: String, Sendable, Codable {
    case idle = "Idle"
    case compiling = "Compiling with xcodebuild..."
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

    /// When on, every successful xcodebuild automatically packages the freshest
    /// .app into an .ipa and refreshes the Latest Archive card.
    public var alwaysBuildArchive: Bool {
        didSet { UserDefaults.standard.set(alwaysBuildArchive, forKey: "com.swiftcode.ipa.alwaysBuildArchive") }
    }

    /// Most recently produced .ipa — shown in the "Latest Archive:" card.
    public var latestArchivePath: String?
    public var latestArchiveDate: Date?

    public var isBusy: Bool { buildState == .packaging || buildState == .compiling }

    public var latestArchiveSize: String? {
        guard let path = latestArchivePath,
              let attr = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attr[.size] as? Int64 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    @ObservationIgnored
    private var activeProcess: Process?
    @ObservationIgnored
    private var startTime: Date?

    private init() {
        self.alwaysBuildArchive = UserDefaults.standard.bool(forKey: "com.swiftcode.ipa.alwaysBuildArchive")
        if let savedPath = UserDefaults.standard.string(forKey: "com.swiftcode.ipa.latestArchivePath"),
           FileManager.default.fileExists(atPath: savedPath) {
            self.latestArchivePath = savedPath
            self.latestArchiveDate = UserDefaults.standard.object(forKey: "com.swiftcode.ipa.latestArchiveDate") as? Date
        }
    }

    /// Drops the Latest Archive reference if the .ipa file no longer exists.
    public func validateLatestArchive() {
        if let path = latestArchivePath, !FileManager.default.fileExists(atPath: path) {
            latestArchivePath = nil
            latestArchiveDate = nil
            UserDefaults.standard.removeObject(forKey: "com.swiftcode.ipa.latestArchivePath")
            UserDefaults.standard.removeObject(forKey: "com.swiftcode.ipa.latestArchiveDate")
        }
    }

    private func recordLatestArchive(path: String) {
        latestArchivePath = path
        latestArchiveDate = Date()
        UserDefaults.standard.set(path, forKey: "com.swiftcode.ipa.latestArchivePath")
        UserDefaults.standard.set(Date(), forKey: "com.swiftcode.ipa.latestArchiveDate")
        appendLog("[SYSTEM] Latest Archive updated: \(path)", isError: false)
    }

    public func getShellScriptPath() -> String {
        let fm = FileManager.default

        // 1. Check main bundle resources
        if let bundlePath = Bundle.main.path(forResource: "build_ipa", ofType: "sh"), fm.fileExists(atPath: bundlePath) {
            chmodExecutable(at: bundlePath)
            return bundlePath
        }

        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("build_ipa.sh"), fm.fileExists(atPath: resourceURL.path) {
            chmodExecutable(at: resourceURL.path)
            return resourceURL.path
        }

        // 2. Check development source tree
        let sourcePath = "/Users/dylan/SwiftCode-Mac/SwiftCode/Resources/build_ipa.sh"
        if fm.fileExists(atPath: sourcePath) {
            chmodExecutable(at: sourcePath)
            return sourcePath
        }

        // 3. Check current working directory relative
        let cwdPath = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("SwiftCode/Resources/build_ipa.sh").path
        if fm.fileExists(atPath: cwdPath) {
            chmodExecutable(at: cwdPath)
            return cwdPath
        }

        let cwdShort = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/build_ipa.sh").path
        if fm.fileExists(atPath: cwdShort) {
            chmodExecutable(at: cwdShort)
            return cwdShort
        }

        // 4. Fallback: Write embedded script to Application Support
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let scriptDir = appSupport.appendingPathComponent("SwiftCode/Scripts", isDirectory: true)
        try? fm.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        let fallbackScriptURL = scriptDir.appendingPathComponent("build_ipa.sh")

        let embeddedScript = """
        #!/bin/bash
        set -e
        ERR_INVALID_APP=10
        ERR_MISSING_PLIST=11
        ERR_TEMP_FAILED=12
        ERR_PACKAGING_FAILED=13
        APP_PATH="$1"
        OUTPUT_DIR="$2"
        IPA_NAME="$3"
        echo "[SHELL] Initiating SwiftCode IPA Build Pipeline..."
        echo "[SHELL] Target App Bundle: $APP_PATH"
        echo "[SHELL] Output Directory: $OUTPUT_DIR"
        if [ ! -d "$APP_PATH" ]; then
            echo "[ERROR] The specified .app bundle is missing or invalid: $APP_PATH"
            exit $ERR_INVALID_APP
        fi
        if [[ "$APP_PATH" != *.app ]]; then
            echo "[ERROR] Invalid package extension. Must be a compiled '.app' bundle."
            exit $ERR_INVALID_APP
        fi
        PLIST_PATH="$APP_PATH/Info.plist"
        if [ ! -f "$PLIST_PATH" ]; then
            echo "[ERROR] Info.plist not found inside the app bundle."
            exit $ERR_MISSING_PLIST
        fi
        echo "[SHELL] Parsing application Info.plist specifications..."
        BUNDLE_ID=$(defaults read "$PLIST_PATH" CFBundleIdentifier 2>/dev/null || echo "Unknown")
        DISPLAY_NAME=$(defaults read "$PLIST_PATH" CFBundleDisplayName 2>/dev/null || defaults read "$PLIST_PATH" CFBundleName 2>/dev/null || echo "App")
        VERSION=$(defaults read "$PLIST_PATH" CFBundleShortVersionString 2>/dev/null || echo "1.0")
        BUILD=$(defaults read "$PLIST_PATH" CFBundleVersion 2>/dev/null || echo "1")
        echo "[SHELL] Display Name: $DISPLAY_NAME"
        echo "[SHELL] Bundle Identifier: $BUNDLE_ID"
        echo "[SHELL] Short Version: $VERSION"
        echo "[SHELL] Build Number: $BUILD"
        TEMP_DIR=$(mktemp -d -t swiftcode-ipa-build)
        echo "[SHELL] Created clean temporary packaging workspace: $TEMP_DIR"
        cleanup() {
            echo "[SHELL] Performing workspace cleanup..."
            rm -rf "$TEMP_DIR"
            echo "[SHELL] Cleanup completed cleanly."
        }
        trap cleanup EXIT
        PAYLOAD_DIR="$TEMP_DIR/Payload"
        mkdir -p "$PAYLOAD_DIR"
        echo "[SHELL] Aligning Payload structures..."
        cp -RP "$APP_PATH" "$PAYLOAD_DIR/"
        if [ -z "$IPA_NAME" ]; then
            IPA_NAME="${DISPLAY_NAME// /_}.ipa"
        fi
        mkdir -p "$OUTPUT_DIR"
        FINAL_IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
        echo "[SHELL] Compressing Payload container..."
        cd "$TEMP_DIR"
        zip -r -y "$FINAL_IPA_PATH" "Payload" > /dev/null
        echo "[SUCCESS] IPA container packaging completed successfully!"
        echo "[SUCCESS] Output File: $FINAL_IPA_PATH"
        ls -lh "$FINAL_IPA_PATH"
        exit 0
        """

        try? embeddedScript.write(to: fallbackScriptURL, atomically: true, encoding: .utf8)
        chmodExecutable(at: fallbackScriptURL.path)
        return fallbackScriptURL.path
    }

    private func chmodExecutable(at path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/chmod")
        p.arguments = ["+x", path]
        try? p.run()
        p.waitUntilExit()
    }

    /// Searches for a compiled .app bundle for the specified project name:
    /// 1. Local project build directory: <projectURL>/build/DerivedData/Build/Products/...
    /// 2. Managed builds directory: ~/Library/Application Support/SwiftCode/Builds/<projectName>/...
    /// 3. Xcode global DerivedData: ~/Library/Developer/Xcode/DerivedData/<projectName>-*/Build/Products/...
    public func findCompiledAppBundle(projectName: String, projectURL: URL?) -> URL? {
        let fm = FileManager.default
        var candidateURLs: [URL] = []

        // 1. Check local project build/DerivedData
        if let projectURL {
            let localProducts = projectURL.appendingPathComponent("build/DerivedData/Build/Products", isDirectory: true)
            if fm.fileExists(atPath: localProducts.path) {
                if let app = findAppBundle(named: projectName, in: localProducts) {
                    candidateURLs.append(app)
                }
            }
            let directBuild = projectURL.appendingPathComponent("build", isDirectory: true)
            if fm.fileExists(atPath: directBuild.path) {
                if let app = findAppBundle(named: projectName, in: directBuild) {
                    candidateURLs.append(app)
                }
            }
        }

        // 2. Check managed builds directory
        if let managedApp = newestManagedAppBundle(projectName: projectName) {
            candidateURLs.append(managedApp)
        }

        // 3. Check Xcode global DerivedData: ~/Library/Developer/Xcode/DerivedData
        let home = fm.homeDirectoryForCurrentUser
        let xcodeDerivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        if fm.fileExists(atPath: xcodeDerivedData.path) {
            if let entries = try? fm.contentsOfDirectory(at: xcodeDerivedData, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) {
                let matchingDirs = entries.filter { $0.lastPathComponent.hasPrefix(projectName + "-") || $0.lastPathComponent == projectName }
                for dir in matchingDirs {
                    let products = dir.appendingPathComponent("Build/Products", isDirectory: true)
                    if fm.fileExists(atPath: products.path), let app = findAppBundle(named: projectName, in: products) {
                        candidateURLs.append(app)
                    }
                }
            }
        }

        // Sort candidates by modification date (newest first)
        return candidateURLs.sorted { u1, u2 in
            let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 > d2
        }.first
    }

    private func findAppBundle(named projectName: String, in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var bestMatch: URL? = nil
        var bestDate = Date.distantPast
        let targetName = "\(projectName.lowercased()).app"

        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            enumerator.skipDescendants()
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if url.lastPathComponent.lowercased() == targetName {
                if date > bestDate {
                    bestDate = date
                    bestMatch = url
                }
            } else if bestMatch == nil || date > bestDate {
                if bestMatch?.lastPathComponent.lowercased() != targetName && date > bestDate {
                    bestDate = date
                    bestMatch = url
                }
            }
        }
        return bestMatch
    }

    public func cancelPackaging() {
        guard isBusy, let process = activeProcess else { return }
        process.terminate()
        buildState = .cancelled
        appendLog("[SYSTEM] Operation aborted by user.", isError: true)
    }

    // MARK: - xcodebuild compilation (no manual Builds-folder / .app hunting)

    /// Managed directory where freshly compiled .app bundles are staged:
    /// ~/Library/Application Support/SwiftCode/Builds/<ProjectName>/
    public func managedBuildsDirectory(projectName: String) -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/Builds/\(projectName)", isDirectory: true)
    }

    /// The most recently modified .app bundle in the managed builds directory.
    public func newestManagedAppBundle(projectName: String) -> URL? {
        let dir = managedBuildsDirectory(projectName: projectName)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return nil }
        return items
            .filter { $0.pathExtension == "app" }
            .sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }
            .first
    }

    /// Compiles the project with xcodebuild and stages the resulting .app in the
    /// managed builds directory. Returns the staged .app URL on success.
    public func compileAppBundle(
        projectURL: URL,
        scheme: String,
        configuration: String,
        destination: String?
    ) async -> (appURL: URL?, errorMessage: String?) {
        guard !isBusy else {
            return (nil, "A build or packaging operation is already in progress.")
        }

        buildState = .compiling
        currentProgress = 0.05
        progressDescription = "Compiling with xcodebuild..."
        startTime = Date()
        appendLog("[SYSTEM] Compiling \(projectURL.lastPathComponent) with xcodebuild (scheme: \(scheme), configuration: \(configuration))…", isError: false)

        let buildPath = UserDefaults.standard.string(forKey: "xcodebuild_executable_path") ?? "/usr/bin/xcodebuild"
        guard FileManager.default.isExecutableFile(atPath: buildPath) else {
            buildState = .failed
            let msg = "xcodebuild not found at \(buildPath). Configure it in the Build Center settings."
            appendLog("[ERROR] \(msg)", isError: true)
            return (nil, msg)
        }

        let derivedData = projectURL.appendingPathComponent("build/DerivedData", isDirectory: true)
        var arguments = [
            "-scheme", scheme,
            "-configuration", configuration,
            "-derivedDataPath", derivedData.path
        ]
        if let destination, !destination.isEmpty {
            arguments.append(contentsOf: ["-destination", destination])
        }
        arguments.append("build")
        // Relaxed signing for simulator-style destinations so a plain compile
        // succeeds without provisioning profiles.
        if (destination ?? "").lowercased().contains("simulator") {
            arguments.append(contentsOf: [
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO"
            ])
        }

        appendLog("[SYSTEM] Running: \(buildPath) \(arguments.joined(separator: " "))", isError: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: buildPath)
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
                process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            }
        }

        do {
            try process.run()
            let status = try await terminationStatusTask.value
            activeProcess = nil

            if buildState == .cancelled {
                return (nil, "Compilation cancelled by user.")
            }

            if status != 0 {
                buildState = .failed
                currentProgress = 0
                progressDescription = "Compilation failed."
                let tail = logs.suffix(8).map(\.message).joined(separator: "\n")
                let msg = "xcodebuild exited with code \(status).\n\(tail)"
                appendLog("[ERROR] xcodebuild exited with code \(status).", isError: true)
                return (nil, msg)
            }

            // Locate the freshest .app under the DerivedData products.
            let productsDir = derivedData.appendingPathComponent("Build/Products", isDirectory: true)
            guard let freshApp = newestAppBundle(in: productsDir) else {
                buildState = .failed
                let msg = "xcodebuild succeeded but no .app bundle was found under \(productsDir.path)."
                appendLog("[ERROR] \(msg)", isError: true)
                return (nil, msg)
            }

            // Stage it in the managed builds directory.
            let fm = FileManager.default
            let managedDir = managedBuildsDirectory(projectName: projectURL.deletingPathExtension().lastPathComponent)
            try? fm.createDirectory(at: managedDir, withIntermediateDirectories: true)
            let stagedURL = managedDir.appendingPathComponent(freshApp.lastPathComponent)
            if fm.fileExists(atPath: stagedURL.path) { try? fm.removeItem(at: stagedURL) }
            do {
                try fm.copyItem(at: freshApp, to: stagedURL)
            } catch {
                appendLog("[WARNING] Could not stage .app in managed directory: \(error.localizedDescription)", isError: true)
            }

            buildState = .idle
            currentProgress = 0.4
            progressDescription = "Compilation succeeded."
            appendLog("[SYSTEM] Compilation succeeded: \(stagedURL.path)", isError: false)
            return (stagedURL, nil)
        } catch {
            activeProcess = nil
            buildState = .failed
            let msg = "Failed to launch xcodebuild: \(error.localizedDescription)"
            appendLog("[ERROR] \(msg)", isError: true)
            return (nil, msg)
        }
    }

    /// Packages the most up-to-date managed .app bundle into an .ipa.
    /// Used by the "Always Build Archive" flow and the Latest Archive card.
    public func packageLatestApp(
        projectName: String,
        outputDirectory: String,
        customIPAName: String? = nil
    ) async -> IPABuildResult {
        guard let appURL = newestManagedAppBundle(projectName: projectName) else {
            let msg = "No compiled .app found for “\(projectName)”. Build the project first."
            appendLog("[ERROR] \(msg)", isError: true)
            return IPABuildResult(success: false, ipaPath: nil, errorMessage: msg)
        }
        appendLog("[SYSTEM] Using most up-to-date .app: \(appURL.lastPathComponent)", isError: false)
        return await packageAppIntoIPA(appPath: appURL.path, outputDirectory: outputDirectory, customIPAName: customIPAName)
    }

    /// Newest .app anywhere under a directory tree (used for DerivedData products).
    private func newestAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var best: URL? = nil
        var bestDate = Date.distantPast
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            enumerator.skipDescendants()
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date > bestDate {
                bestDate = date
                best = url
            }
        }
        return best
    }

    // MARK: - IPA packaging

    public func packageAppIntoIPA(appPath: String, outputDirectory: String, customIPAName: String? = nil) async -> IPABuildResult {
        guard !isBusy else {
            return IPABuildResult(success: false, ipaPath: nil, errorMessage: "A build or packaging operation is in progress.")
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
                recordLatestArchive(path: ipaPath)
                AlertSoundPlayer.shared.play(.buildSuccess)
                return IPABuildResult(success: true, ipaPath: ipaPath, errorMessage: nil)
            } else {
                buildState = .failed
                currentProgress = 0.0
                progressDescription = "Packaging failed."
                let errMsg = "Process exited with code \(status)."
                appendLog("[ERROR] \(errMsg)", isError: true)
                AlertSoundPlayer.shared.play(.buildFailure)
                return IPABuildResult(success: false, ipaPath: nil, errorMessage: errMsg)
            }
        } catch {
            activeProcess = nil
            buildState = .failed
            currentProgress = 0.0
            progressDescription = "Failed to launch pipeline."
            let errMsg = error.localizedDescription
            appendLog("[ERROR] Failed to run process: \(errMsg)", isError: true)
            AlertSoundPlayer.shared.play(.buildFailure)
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

    public func appendLog(_ message: String, isError: Bool) {
        logs.append(IPABuildLogEntry(message: message, isError: isError))
    }
}
