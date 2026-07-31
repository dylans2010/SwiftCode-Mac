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
