import Foundation
import SwiftCodeDeviceModel

extension RemoteSimulator {
    public var displaySocketPath: String {
        let dir = "\(settings.dataDirectory)/display/"
        if let displaySocketName { return dir + displaySocketName }
        let name = target?.deviceDirectoryName ?? settings.deviceName
        let path = dir + name + ".sock"
        let short = "d-" + Self.shortHash(name) + ".sock"
        return path.utf8.count <= Self.socketPathLimit || short.utf8.count >= name.utf8.count + 5 ? path : dir + short
    }

    static let socketPathLimit = 100

    static func shortHash(_ s: String) -> String {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return String(format: "%08x", h)
    }

    public var displayServerArguments: [String] { ["--display-server", "unix:" + displaySocketPath] }

    public var startCommand: String {
        let q = Self.quote
        return "mkdir -p \(q("\(settings.dataDirectory)/display")); echo SWIFTCODE-REMOTE-PID $$; exec \(environmentPrefix)\(q(settings.simdPath))"
            + " --device \(q(remoteDevicePath)) --runtime-root \(q(runtimeRoot))"
            + (target?.deviceTypeArguments ?? []).map { " " + q($0) }.joined()
            + displayServerArguments.map { " " + q($0) }.joined()
            + Self.words(settings.additionalArguments).map { " " + q($0) }.joined()
            + cameraArguments.map { " " + q($0) }.joined()
            + visionDisplayArguments.map { " " + q($0) }.joined()
    }

    public func displayForwardArguments(localSocket: String) -> [String] {
        sshOptions + ["-N", "-o", "ExitOnForwardFailure=yes", "-o", "StreamLocalBindUnlink=yes", "-o", "ServerAliveInterval=15",
                      "-L", "\(localSocket):\(displaySocketPath)", settings.destination]
    }

    public var frameSpec: DeviceFrameSpec {
        target.flatMap { DeviceFrameSpec.named(typeID: $0.deviceType.id) } ?? .iPhoneDuo
    }
}
