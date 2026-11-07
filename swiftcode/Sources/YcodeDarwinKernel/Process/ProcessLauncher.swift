import Foundation
import YcodeDarwinABI

public struct ProcessImageRequest {
    public var executablePath: String
    public var hostExecutablePath: String
    public var argv: [String]
    public var envp: [String]
    public var apple: [String]
    public var startSuspended: Bool

    public init(executablePath: String, hostExecutablePath: String, argv: [String], envp: [String],
                apple: [String] = [], startSuspended: Bool = false) {
        self.executablePath = executablePath
        self.hostExecutablePath = hostExecutablePath
        self.argv = argv
        self.envp = envp
        self.apple = apple
        self.startSuspended = startSuspended
    }
}

public protocol LaunchedImage: AnyObject {
    func resume()
}

public protocol ProcessLauncher: AnyObject {
    func launch(_ request: ProcessImageRequest, kernel: DarwinKernel) throws -> any LaunchedImage

    func prepare(_ request: ProcessImageRequest, kernel: DarwinKernel) throws -> (any PreparedImage)?
    func activate(_ prepared: any PreparedImage, startSuspended: Bool) throws -> any LaunchedImage
    func discard(_ prepared: any PreparedImage)
}

public protocol PreparedImage: AnyObject {}

extension ProcessLauncher {
    public func prepare(_ request: ProcessImageRequest, kernel: DarwinKernel) throws -> (any PreparedImage)? { nil }
    public func activate(_ prepared: any PreparedImage, startSuspended: Bool) throws -> any LaunchedImage {
        preconditionFailure("activate without prepare")
    }
    public func discard(_ prepared: any PreparedImage) {}
}
