import Foundation

public enum AssistCIFunctions {
    public struct BuildYMLConfig: Sendable {
        public enum BuildConfiguration: String, CaseIterable, Sendable {
            case debug = "Debug"
            case release = "Release"
        }

        public enum DestinationType: String, CaseIterable, Sendable {
            case device = "Device"
            case simulator = "Simulator"
        }

        public enum TriggerMode: String, CaseIterable, Sendable {
            case manual = "Manual Only"
            case pushOnly = "On Push"
            case pushAndManual = "Push and Manual"
        }

        public enum ExportFormat: String, CaseIterable, Sendable {
            case ipa = "ipa"
            case pkg = "pkg"
            case app = "app"
        }

        public enum RunnerImage: String, CaseIterable, Sendable {
            case macOS14 = "macos-14"
            case macOS13 = "macos-13"
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
            outputDirectory: String,
            outputName: String,
            triggerBranch: String,
            triggerMode: TriggerMode,
            includeTests: Bool,
            includeLint: Bool,
            cleanBuild: Bool,
            failFast: Bool,
            includeCaching: Bool,
            uploadLogsArtifact: Bool,
            exportFormat: ExportFormat,
            runnerImage: RunnerImage,
            timeoutMinutes: Int,
            includeConcurrencyControl: Bool,
            appName: String,
            bundleIdentifier: String,
            marketingVersion: String,
            buildVersion: String,
            supportedDevices: String
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
            self.timeoutMinutes = timeoutMinutes
            self.includeConcurrencyControl = includeConcurrencyControl
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.marketingVersion = marketingVersion
            self.buildVersion = buildVersion
            self.supportedDevices = supportedDevices
        }
    }

    public static func generateBuildYML(config: BuildYMLConfig) -> String {
        var yaml = """
name: \(config.appName) Build

on:
"""
        if config.triggerMode == .pushOnly || config.triggerMode == .pushAndManual {
            yaml += """

  push:
    branches: [ "\(config.triggerBranch)" ]
"""
        }
        if config.triggerMode == .manual || config.triggerMode == .pushAndManual {
            yaml += """

  workflow_dispatch:
"""
        }

        yaml += """

jobs:
  build:
    name: Build and Export
    runs-on: \(config.runnerImage.rawValue)
    timeout-minutes: \(config.timeoutMinutes)

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_\(config.xcodeVersion).app

"""

        if config.includeCaching {
            yaml += """
      - name: Cache DerivedData
        uses: actions/cache@v3
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: ${{ runner.os }}-xcode-deriveddata-${{ hashFiles('**/*.swift') }}

"""
        }

        yaml += """
      - name: Build
        run: |
          xcodebuild build-for-testing \\
            -project "\(config.projectName).xcodeproj" \\
            -scheme "\(config.scheme)" \\
            -configuration \(config.buildConfiguration.rawValue) \\
            -destination "generic/platform=iOS"

"""
        return yaml
    }
}
