import Foundation
import SwiftCodeDarwinABI

public final class MachIPCSystem: @unchecked Sendable {
    public internal(set) var portLock: KernelLock?
    var serialCounter: UInt64 = 0
    var stampCounter: UInt64 = 0
    var spaceCounter: UInt64 = 0
    let hostPort: IPCPort
    let bootstrapPort: IPCPort
    var ioMain: IPCPort?
    var ioObjects: [UInt64: IOKitObject] = [:]
    var ioRegistryPaths: [String: IPCPort] = [:]
    public var auditSessionID: UInt32 = 0

    public internal(set) var hostTask: MachHostTask?
    public var hostBootstrapPort: UInt32? { hostTask?.bootstrapPort }
    var hostBootstrapObject: IPCPort?
    public var hostBootstrapIsDefault = false

    var defaultBootstrapPort: IPCPort {
        if hostBootstrapIsDefault, let p = hostBootstrapObject, p.active { return p }
        return bootstrapPort
    }

    public init() {
        hostPort = IPCPort(serial: 1)
        hostPort.kernelObject = .host
        bootstrapPort = IPCPort(serial: 2)
        bootstrapPort.kernelObject = .bootstrap
        serialCounter = 2
    }

    func nextSerial() -> UInt64 {
        serialCounter += 1
        return serialCounter
    }

    func nextStamp() -> UInt64 {
        stampCounter += 1
        return stampCounter
    }

    func nextSpaceID() -> UInt64 {
        spaceCounter += 1
        return spaceCounter
    }
}

extension MachIPC {
    public static let bsdFileportMakeport = 430
    public static let bsdFileportMakefd = 431

    func fileportCall(_ n: Int, _ a: [UInt64], fileSystem: DarwinFileSystem,
                      memory: any KernelGuestMemory) throws -> UInt64? {
        switch n {
        case Self.bsdFileportMakeport:
            let fd = Int32(truncatingIfNeeded: a.first ?? 0)
            let out = a.count > 1 ? a[1] : 0
            try fileSystem.checkGuard(fd, DarwinGuard.fileport, flavor: DarwinGuard.exceptionFileport)
            let file = try fileSystem.openFile(for: fd)
            if file.object?.isConfined ?? false { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            let p = newPort()
            p.kernelObject = .fileport(serial: p.serial)
            p.fileportFile = file
            p.srights = 1
            let (name, ok) = copyout(.send(p))
            guard ok else {
                throw DarwinErrnoError(DarwinErrnoCode.ENOMEM)
            }
            do {
                try memory.write(va: out, bytes: le32(name))
            } catch {
                _ = portDeallocate(name)
                throw DarwinErrnoError(DarwinErrnoCode.EFAULT)
            }
            log("fileport_makeport(fd=\(fd)) -> \(hx(name))")
            return 0

        case Self.bsdFileportMakefd:
            let name = UInt32(truncatingIfNeeded: a.first ?? 0)
            guard let (p, object) = kernelObject(named: name), case .fileport = object, p.active,
                  let file = p.fileportFile else {
                throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
            }
            let fd = try fileSystem.install(file, closeOnExec: true)
            log("fileport_makefd(\(hx(name))) -> fd \(fd)")
            return UInt64(UInt32(bitPattern: fd))

        default:
            return nil
        }
    }

    public func fileportFile(named name: UInt32) -> DarwinOpenFile? {
        guard let (p, object) = kernelObject(named: name), case .fileport = object, p.active else { return nil }
        return p.fileportFile
    }
}

public struct SpawnPortAction: Equatable, Sendable {
    public enum Kind: UInt32, Sendable {
        case special = 0
        case exception = 1
        case auditSession = 2
        case importanceWatch = 3
        case registered = 4
        case ptrauthTask = 5
    }

    public var type: UInt32
    public var mask: UInt32
    public var port: UInt32
    public var behavior: UInt32
    public var flavor: UInt32
    public var which: Int32

    public var kind: Kind? { Kind(rawValue: type) }

    public init() {
        self.init(type: 0, port: 0)
    }

    public init(type: UInt32, mask: UInt32 = 0, port: UInt32, behavior: UInt32 = 0, flavor: UInt32 = 0,
                which: Int32 = 0) {
        self.type = type
        self.mask = mask
        self.port = port
        self.behavior = behavior
        self.flavor = flavor
        self.which = which
    }

    public init(kind: Kind, mask: UInt32 = 0, port: UInt32, behavior: UInt32 = 0, flavor: UInt32 = 0,
                which: Int32 = 0) {
        self.init(type: kind.rawValue, mask: mask, port: port, behavior: behavior, flavor: flavor, which: which)
    }

    public static let recordSize = 24

    public init(record bytes: [UInt8]) {
        precondition(bytes.count >= Self.recordSize)
        self.init(type: bytes.readLE(UInt32.self, at: 0), mask: bytes.readLE(UInt32.self, at: 4),
                  port: bytes.readLE(UInt32.self, at: 8), behavior: bytes.readLE(UInt32.self, at: 12),
                  flavor: bytes.readLE(UInt32.self, at: 16), which: bytes.readLE(Int32.self, at: 20))
    }

    public static func parseBlock(_ bytes: [UInt8]) throws -> [SpawnPortAction] {
        guard bytes.count >= 8 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        let count = bytes.readLE(Int32.self, at: 4)
        guard count >= 0, bytes.count >= 8 + Int(count) * recordSize else {
            throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
        }
        return (0..<Int(count)).map { k in
            SpawnPortAction(record: Array(bytes[(8 + k * recordSize)..<(8 + (k + 1) * recordSize)]))
        }
    }

    public var record: [UInt8] {
        le32(type) + le32(mask) + le32(port) + le32(behavior) + le32(flavor) + le32(UInt32(bitPattern: which))
    }
}
