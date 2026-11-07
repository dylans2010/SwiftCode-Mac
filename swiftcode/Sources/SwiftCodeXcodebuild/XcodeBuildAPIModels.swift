import Foundation
import Observation
import SwiftUI
import os

public struct BuildDestination: Sendable, Codable, Hashable {
    public let destination: String

    public init(destination: String) {
        self.destination = destination
    }
}

public struct BuildDiagnostics: Sendable, Codable, Identifiable {
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

public struct BuildLogs: Sendable, Codable {
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }
}

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

public struct BundleMetadata: Sendable, Codable {
    public let bundleIdentifier: String
    public let productName: String

    public init(bundleIdentifier: String, productName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.productName = productName
    }
}

public struct SchemeMetadata: Sendable, Codable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

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

public enum XcodeGenInstallationState: String, Sendable, Codable {
    case installed
    case missing
    case installing
    case failed
}

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
