import Foundation

public struct AssistCIFunctions {
    public struct BuildYMLConfig: Codable, Equatable {
        public enum BuildConfiguration: String, Codable, CaseIterable {
            case debug = "Debug"
            case release = "Release"
        }

        public enum DestinationType: String, Codable, CaseIterable {
            case simulator
            case device

            var destination: String {
                switch self {
                case .simulator: return "generic/platform=iOS Simulator"
                case .device: return "generic/platform=iOS"
                }
            }

            var sdk: String {
                switch self {
                case .simulator: return "iphonesimulator"
                case .device: return "iphoneos"
                }
            }
        }

        public enum TriggerMode: String, Codable, CaseIterable {
            case manualOnly = "Manual only"
            case pushAndManual = "Push + Manual"
            case pullRequestAndManual = "Pull Request + Manual"
            case all = "Push + PR + Manual"
        }

        public enum ExportFormat: String, Codable, CaseIterable {
            case ipa = "IPA"
            case xcarchive = "XCArchive"
            case both = "Both"
        }

        public enum RunnerImage: String, Codable, CaseIterable {
            case macOS14 = "macos-14"
            case macOS15 = "macos-15"
        }

        public var projectName: String
        public var scheme: String
        public var xcodeVersion: String
        public var buildConfiguration: BuildConfiguration
        public var destinationType: DestinationType
        public var outputDirectory: String
        public var outputName: String
        public var triggerBranch: String
        public var triggerMode: TriggerMode
        public var includeTests: Bool
        public var includeLint: Bool
        public var cleanBuild: Bool
        public var failFast: Bool
        public var includeCaching: Bool
        public var uploadLogsArtifact: Bool
        public var exportFormat: ExportFormat
        public var runnerImage: RunnerImage
        public var timeoutMinutes: Int
        public var includeConcurrencyControl: Bool
        public var appName: String
        public var bundleIdentifier: String
        public var marketingVersion: String
        public var buildVersion: String
        public var supportedDevices: String

        public init(
            projectName: String,
            scheme: String,
            xcodeVersion: String,
            buildConfiguration: BuildConfiguration,
            destinationType: DestinationType,
            outputDirectory: String = "upload",
            outputName: String,
            triggerBranch: String,
            triggerMode: TriggerMode = .pushAndManual,
            includeTests: Bool = false,
            includeLint: Bool = false,
            cleanBuild: Bool = true,
            failFast: Bool = true,
            includeCaching: Bool = true,
            uploadLogsArtifact: Bool = true,
            exportFormat: ExportFormat = .ipa,
            runnerImage: RunnerImage = .macOS14,
            timeoutMinutes: Int = 30,
            includeConcurrencyControl: Bool = true,
            appName: String = "",
            bundleIdentifier: String = "",
            marketingVersion: String = "1.0",
            buildVersion: String = "1",
            supportedDevices: String = "iPhone + iPad"
        ) {
            self.projectName = projectName
            self.scheme = scheme
            self.xcodeVersion = xcodeVersion
            self.buildConfiguration = buildConfiguration
            self.destinationType = destinationType
            self.outputDirectory = outputDirectory
            self.outputName = outputName
            self.triggerBranch = triggerBranch
            self.triggerMode = triggerMode
            self.includeTests = includeTests
            self.includeLint = includeLint
            self.cleanBuild = cleanBuild
            self.failFast = failFast
            self.includeCaching = includeCaching
            self.uploadLogsArtifact = uploadLogsArtifact
            self.exportFormat = exportFormat
            self.runnerImage = runnerImage
            self.timeoutMinutes = min(max(timeoutMinutes, 5), 180)
            self.includeConcurrencyControl = includeConcurrencyControl
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.marketingVersion = marketingVersion
            self.buildVersion = buildVersion
            self.supportedDevices = supportedDevices
        }
    }

    public struct PipelineValidationResult {
        public let pipelinesFound: Int
        public let valid: Int
        public let invalid: Int
        public let errors: [String]
        public let validPipelines: [String]
    }

    private struct ParsedPipeline {
        let name: String?
        let stepCount: Int
        let scriptCount: Int
    }

    @discardableResult
    public static func generateBuildYML(config: BuildYMLConfig, workspaceRoot: URL) throws -> URL {
        let ciDirectory = resolveCIDirectory(workspaceRoot: workspaceRoot)
        try FileManager.default.createDirectory(at: ciDirectory, withIntermediateDirectories: true)
        let fileURL = ciDirectory.appendingPathComponent("build.yml")
        let yaml = generateBuildYML(config: config)
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public static func generateBuildYML(config: BuildYMLConfig) -> String {
        let safeProject = sanitizeYAMLValue(config.projectName)
        let safeScheme = sanitizeYAMLValue(config.scheme)
        let safeBranch = sanitizeYAMLValue(config.triggerBranch)
        let safeOutputDirectory = sanitizePathComponent(config.outputDirectory)
        let safeOutputName = sanitizePathComponent(config.outputName)
        let archivePath = "\(safeOutputDirectory)/\(safeOutputName).xcarchive"
        let safeAppName = sanitizeYAMLValue(config.appName.isEmpty ? config.projectName : config.appName)
        let safeBundleID = sanitizeYAMLValue(config.bundleIdentifier)
        let safeMarketingVersion = sanitizeYAMLValue(config.marketingVersion)
        let safeBuildVersion = sanitizeYAMLValue(config.buildVersion)
        let safeSupportedDevices = sanitizeYAMLValue(config.supportedDevices)
        let timeoutMinutes = min(max(config.timeoutMinutes, 5), 180)

        let onSection = makeTriggers(trigger: config.triggerMode, branch: safeBranch)
        let cacheSection = config.includeCaching ? """
      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: ${{ runner.os }}-xcode-${{ hashFiles('**/*.xcodeproj/project.pbxproj') }}
          restore-keys: |
            ${{ runner.os }}-xcode-
""" : ""

        let lintSection = config.includeLint ? """
      - name: Swift Lint (basic)
        run: |
          if command -v swiftlint >/dev/null 2>&1; then
            swiftlint --strict
          else
            echo \"swiftlint not installed on runner; skipping\"
          fi
""" : ""

        let testSection = config.includeTests ? """
      - name: Run Unit Tests
        run: |
          xcodebuild test \\
            -project \(safeProject).xcodeproj \\
            -scheme \(safeScheme) \\
            -configuration \(config.buildConfiguration.rawValue) \\
            -destination \"platform=iOS Simulator,name=iPhone 15\" \\
            -sdk iphonesimulator
""" : ""

        let deviceFamilyValue: String = {
            switch config.supportedDevices.lowercased() {
            case "iphone": return "1"
            case "ipad": return "2"
            default: return "1,2"
            }
        }()

        let cleanCommand = config.cleanBuild ? "clean \\\n            " : ""
        let failFastHeader = config.failFast ? "set -e\n          " : ""

        let archiveUploadSection = (config.exportFormat == .xcarchive || config.exportFormat == .both) ? """
      - name: Upload XCArchive Artifact
        uses: actions/upload-artifact@v4
        with:
          name: \(safeOutputName)-xcarchive
          path: \(archivePath)
""" : ""

        let ipaCreateSection = (config.exportFormat == .ipa || config.exportFormat == .both) ? """
      - name: Create IPA
        run: |
          mkdir -p \(safeOutputDirectory)/Payload
          cp -R \(archivePath)/Products/Applications/*.app \(safeOutputDirectory)/Payload/
          cd \(safeOutputDirectory)
          zip -r \(safeOutputName).ipa Payload

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: \(safeOutputName)-ipa
          path: \(safeOutputDirectory)/\(safeOutputName).ipa
""" : ""

        let logsSection = config.uploadLogsArtifact ? """
      - name: Upload Build Logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: \(safeOutputName)-build-logs
          path: ~/Library/Logs
""" : ""

        let concurrencySection = config.includeConcurrencyControl ? """
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
""" : ""

        return """
name: Build \(safeProject)

\(onSection)
\(concurrencySection)permissions:
  contents: read

env:
  APP_NAME: \(safeAppName)
  BUNDLE_IDENTIFIER: \(safeBundleID)
  MARKETING_VERSION: \(safeMarketingVersion)
  BUILD_VERSION: \(safeBuildVersion)
  SUPPORTED_DEVICES: \(safeSupportedDevices)

jobs:
  build:
    runs-on: \(config.runnerImage.rawValue)
    timeout-minutes: \(timeoutMinutes)
    steps:
      - name: Checkout
        uses: actions/checkout@v4
\(cacheSection)
      - name: Set up Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '\(sanitizeYAMLValue(config.xcodeVersion))'
\(lintSection)
      - name: Build
        run: |
          \(failFastHeader)mkdir -p \(safeOutputDirectory)
          xcodebuild -project \(safeProject).xcodeproj \\
            -scheme \(safeScheme) \\
            -configuration \(config.buildConfiguration.rawValue) \\
            -destination \"\(config.destinationType.destination)\" \\
            -sdk \(config.destinationType.sdk) \\
            -archivePath \(archivePath) \\
            \(cleanCommand)archive \\
            PRODUCT_BUNDLE_IDENTIFIER=\"$BUNDLE_IDENTIFIER\" \\
            MARKETING_VERSION=\"$MARKETING_VERSION\" \\
            CURRENT_PROJECT_VERSION=\"$BUILD_VERSION\" \\
            PRODUCT_NAME=\"$APP_NAME\" \\
            TARGETED_DEVICE_FAMILY=\"\(deviceFamilyValue)\" \\
            CODE_SIGNING_ALLOWED=NO \\
            CODE_SIGNING_REQUIRED=NO
\(testSection)
\(archiveUploadSection)
\(ipaCreateSection)
\(logsSection)
"""
    }

    private static func makeTriggers(trigger: BuildYMLConfig.TriggerMode, branch: String) -> String {
        switch trigger {
        case .manualOnly:
            return """
on:
  workflow_dispatch:
"""
        case .pushAndManual:
            return """
on:
  workflow_dispatch:
  push:
    branches:
      - \(branch)
"""
        case .pullRequestAndManual:
            return """
on:
  workflow_dispatch:
  pull_request:
    branches:
      - \(branch)
"""
        case .all:
            return """
on:
  workflow_dispatch:
  push:
    branches:
      - \(branch)
  pull_request:
    branches:
      - \(branch)
"""
        }
    }

    public static func validateCIPipelines(workspaceRoot: URL) throws -> PipelineValidationResult {
        let ciDirectory = resolveCIDirectory(workspaceRoot: workspaceRoot)
        let yamlFiles = try FileManager.default.contentsOfDirectory(at: ciDirectory, includingPropertiesForKeys: nil)
            .filter { ["yml", "yaml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var validCount = 0
        var errors: [String] = []
        var validPipelines: [String] = []

        for fileURL in yamlFiles {
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let parsed = try parsePipeline(content: content)

                var pipelineErrors: [String] = []
                if (parsed.name?.isEmpty ?? true) {
                    pipelineErrors.append("missing key 'name'")
                }
                if parsed.stepCount == 0 {
                    pipelineErrors.append("missing key 'steps'")
                }
                if parsed.scriptCount == 0 {
                    pipelineErrors.append("missing key 'scripts' (no run/script commands)")
                }

                if pipelineErrors.isEmpty {
                    validCount += 1
                    validPipelines.append(fileURL.lastPathComponent)
                } else {
                    errors.append("\(fileURL.lastPathComponent): \(pipelineErrors.joined(separator: ", "))")
                }
            } catch {
                errors.append("\(fileURL.lastPathComponent): parse error - \(error.localizedDescription)")
            }
        }

        return PipelineValidationResult(
            pipelinesFound: yamlFiles.count,
            valid: validCount,
            invalid: max(0, yamlFiles.count - validCount),
            errors: errors,
            validPipelines: validPipelines
        )
    }

    private static func resolveCIDirectory(workspaceRoot: URL) -> URL {
        let candidates = [
            workspaceRoot.appendingPathComponent("SwiftCode/Backend/CI Building", isDirectory: true),
            workspaceRoot.appendingPathComponent("Backend/CI Building", isDirectory: true)
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return candidates[0]
    }

    private static func sanitizeYAMLValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func sanitizePathComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
    }

    private static func parsePipeline(content: String) throws -> ParsedPipeline {
        let lines = content.components(separatedBy: .newlines)

        var name: String?
        var stepCount = 0
        var scriptCount = 0

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("name:"), name == nil {
                name = line.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if line.hasPrefix("- name:") || line.hasPrefix("- uses:") || line.hasPrefix("- run:") || line == "steps:" {
                if line.hasPrefix("-") {
                    stepCount += 1
                }
            }

            if line.contains("run:") || line.contains("script:") {
                scriptCount += 1
            }
        }

        return ParsedPipeline(name: name, stepCount: stepCount, scriptCount: scriptCount)
    }
}
