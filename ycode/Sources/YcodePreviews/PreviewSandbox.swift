// Adapted from SwiftCode-Legacy SwiftCode/Core/Preview/PreviewSandbox.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct PreviewSandboxPolicy: Sendable {
    public let projectDirectory: URL
    public let allowNetwork: Bool
    public let blockedPaths: [String]
}

public final class PreviewSandbox: Sendable {
    public init() {}

    public func makePolicy(projectDirectory: URL, allowNetwork: Bool = false) -> PreviewSandboxPolicy {
        PreviewSandboxPolicy(
            projectDirectory: projectDirectory,
            allowNetwork: allowNetwork,
            blockedPaths: ["/System", "/private", "/var"]
        )
    }
}
