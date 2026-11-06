import Foundation
import DiagnosticsKit
import WorkspaceKit
import ProjectKit
import BuildKit
import SourceControlKit
import ExtensionKit

public struct SDKVersion: Sendable, CustomStringConvertible {
    public static let current = SDKVersion(major: 1, minor: 0, patch: 0)

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var description: String {
        if let pre = prerelease {
            return "\(major).\(minor).\(patch)-\(pre)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public var isCompatibleWithHost: Bool {
        // SwiftCode 1.0+ compatible
        major == 1
    }
}

public struct SDKConfiguration: Sendable {
    public let sdkRoot: String
    public let binDirectory: String
    public let libDirectory: String
    public let toolsDirectory: String
    public let templatesDirectory: String
    public let documentationDirectory: String

    public static func standard(sdkRoot: String? = nil) -> SDKConfiguration {
        let root = sdkRoot ?? defaultSDKRoot()
        let ws = WorkspacePath(root)
        return SDKConfiguration(
            sdkRoot: root,
            binDirectory: ws.appending("bin").normalizedPath,
            libDirectory: ws.appending("lib").normalizedPath,
            toolsDirectory: ws.appending("tools").normalizedPath,
            templatesDirectory: ws.appending("templates").normalizedPath,
            documentationDirectory: ws.appending("documentation").normalizedPath
        )
    }

    private static func defaultSDKRoot() -> String {
        if let env = ProcessInfo.processInfo.environment["SWIFTCODE_SDK_ROOT"] {
            return env
        }
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.deletingLastPathComponent().path
    }
}
