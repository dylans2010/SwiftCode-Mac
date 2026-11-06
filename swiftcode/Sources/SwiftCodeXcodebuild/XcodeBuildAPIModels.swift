// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Build/XcodeBuildAPI.swift (commit d51a8f0d)
//
// Only the types that file declares which the destination does NOT
// already have. Skipped Legacy types (not redeclared here):
// - BuildConfiguration — a nested `BuildConfiguration` already
//   exists in SwiftCodeMCP's SwiftCodeTools+PlanningSupport.swift.
//   The ported XcodeBuildAPI takes the configuration as a plain
//   "Debug"/"Release" string instead.
// - XcodeProject — a nested `XcodeProject` already exists in this
//   same target (SwiftCodeXcodebuild/XcodeProjectPluginSource.swift).
//   Project discovery in the ported XcodeBuildAPI returns its
//   nested DiscoveredProject (same url/name/schemes shape) instead.
// - Workspace — the destination's SwiftCodeWorkspace.Workspace is
//   a different type (the workspace model, not Legacy's
//   {url, name, projects}); determineActiveWorkspace is dropped.
// - BuildResult / BuildStatus — the destination's
//   SwiftCodeBuild.BuildResult (status/exitCode/issues) is a
//   different shape from Legacy's (status/appBundleURL/diagnostics
//   /logs). The ported XcodeBuildAPI keeps Legacy's shape as its
//   nested BuildResult/BuildStatus instead of redeclaring them at
//   top level (both modules are imported together elsewhere, so a
//   top-level duplicate would make the name ambiguous).
// - Severity — only ever nested: Legacy declared it inside
//   BuildDiagnostics, and it is ported the same way below. The
//   top-level-looking `Severity` hits in the destination are
//   nested inside other types in other modules.
// - AppEntry / ContentView — not real types in the Legacy file at
//   all: the three occurrences are SwiftUI template TEXT inside
//   string literals written to generated main.swift files (see
//   XcodeBuildAPI.generateProjectWithXcodeGen / generateProject).
//   No ContentView is ported, as instructed.

import Foundation
import Observation
import PackageDescription
import ProjectDescription
import SwiftUI
import os

/// The destination for a build (`xcodebuild -destination ...`),
/// e.g. "platform=macOS" or "platform=iOS Simulator".
public struct BuildDestination: Sendable, Codable, Hashable {
    public let destination: String

    public init(destination: String) {
        self.destination = destination
    }
}

/// One build diagnostic (error/warning/note) with its location.
public struct BuildDiagnostics: Sendable, Codable, Identifiable {
    // As in Legacy: a fresh UUID on every access (Identifiable
    // conformance only; the id is not a stable identity).
    public var id: UUID { UUID() }
    public let message: String
    public let severity: Severity
    public let filePath: String?
    public let line: Int?
    public let column: Int?

    public enum Severity: String, Sendable, Codable {
        case error
        case warning
        case note
    }

    public init(message: String, severity: Severity, filePath: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.message = message
        self.severity = severity
        self.filePath = filePath
        self.line = line
        self.column = column
    }
}

/// The raw log lines of a build.
public struct BuildLogs: Sendable, Codable {
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }
}

/// The metadata of a discovered Xcode project: its display name,
/// product type, target name and container path. Legacy filled
/// productType with "com.apple.product-type.application" and
/// targetName with the project name (see
/// XcodeBuildAPI.determineProjectMetadata); this type carries
/// whatever the caller determined.
public struct XcodeProjectMetadata: Sendable, Codable {
    public let name: String
    public let productType: String
    public let targetName: String
    public let path: URL

    public init(name: String, productType: String, targetName: String, path: URL) {
        self.name = name
        self.productType = productType
        self.targetName = targetName
        self.path = path
    }
}

/// The bundle identity of a built product.
public struct BundleMetadata: Sendable, Codable {
    public let bundleIdentifier: String
    public let productName: String

    public init(bundleIdentifier: String, productName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.productName = productName
    }
}

/// One scheme of a discovered project (the name of a .xcscheme
/// file, or the project name when the container has no schemes).
public struct SchemeMetadata: Sendable, Codable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// The outcome of generating an Xcode project (Tuist / XcodeGen /
/// SPM fallback): success plus the generated .xcodeproj (or
/// Package.swift, when only the SPM fallback ran) or an error.
public struct GenerationResult: Sendable, Codable {
    public let success: Bool
    public let generatedProjectPath: URL?
    public let errorDescription: String?

    public init(success: Bool, generatedProjectPath: URL?, errorDescription: String?) {
        self.success = success
        self.generatedProjectPath = generatedProjectPath
        self.errorDescription = errorDescription
    }
}

/// The result of validating the build environment: whether
/// xcodebuild is present and executable, the xcode-select path,
/// and the active toolchain.
public struct EnvironmentValidation: Sendable, Codable {
    public let xcodeAvailable: Bool
    public let xcodeSelectPath: String
    public let activeToolchain: String
    public let isValid: Bool
    public let errorDescription: String?

    public init(xcodeAvailable: Bool, xcodeSelectPath: String, activeToolchain: String, isValid: Bool, errorDescription: String?) {
        self.xcodeAvailable = xcodeAvailable
        self.xcodeSelectPath = xcodeSelectPath
        self.activeToolchain = activeToolchain
        self.isValid = isValid
        self.errorDescription = errorDescription
    }
}

/// Whether XcodeGen is installed (and whether an install is in
/// progress or failed).
public enum XcodeGenInstallationState: String, Sendable, Codable {
    case installed
    case missing
    case installing
    case failed
}

/// One project-generation failure: the stage that failed, when,
/// what happened, and how to recover. `id` is a fresh UUID on
/// every access, as in Legacy.
public struct ProjectGenerationError: Identifiable, Sendable, Codable {
    public var id: UUID { UUID() }
    public let stage: String
    public let timestamp: Date
    public let message: String
    public let suggestedRecovery: String?

    public init(stage: String, timestamp: Date = Date(), message: String, suggestedRecovery: String? = nil) {
        self.stage = stage
        self.timestamp = timestamp
        self.message = message
        self.suggestedRecovery = suggestedRecovery
    }
}


// Ported from Legacy `SwiftCode/Backend/Build/XcodeBuildAPI.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: BuildConfiguration, XcodeProject.

public enum BuildConfiguration: String, CaseIterable, Sendable, Codable {
    case debug = "Debug"
    case release = "Release"
}

public struct XcodeProject: Sendable, Codable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let schemes: [SchemeMetadata]

    public init(url: URL, name: String, schemes: [SchemeMetadata]) {
        self.url = url
        self.name = name
        self.schemes = schemes
    }
}
