import Foundation

public enum GDBRemoteResume: Equatable, Sendable {
    case stop
    case `continue`(signal: Int?)
    case step(signal: Int?)
}

public enum GDBRemoteStopReason: Equatable, Sendable {
    case none
    case signal
    case breakpoint
    case trace
    case exception(String)
    case watchpoint(address: UInt64, index: Int, hit: UInt64)
}

public enum GDBRemoteWatchKind: Int, Equatable, Sendable {
    case write = 2, read = 3, access = 4
}

public struct GDBRemoteThreadStop: Equatable, Sendable {
    public var signal: Int
    public var reason: GDBRemoteStopReason
    public init(signal: Int, reason: GDBRemoteStopReason) {
        self.signal = signal
        self.reason = reason
    }

    public static let quiet = GDBRemoteThreadStop(signal: 0, reason: .none)
}

public enum GDBRemoteEvent: Equatable, Sendable {
    case stopped(thread: UInt64)
    case exited(status: Int)
    case terminated(signal: Int)
}

public struct GDBRemoteMemoryRegion: Equatable, Sendable {
    public var start: UInt64
    public var size: UInt64
    public var permissions: String?
    public var name: String?
    public init(start: UInt64, size: UInt64, permissions: String?, name: String? = nil) {
        self.start = start
        self.size = size
        self.permissions = permissions
        self.name = name
    }
}

public struct GDBRemoteError: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: UInt8
    public var message: String
    public init(_ code: UInt8, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { message }
}

public protocol GDBRemoteProcess: AnyObject, Sendable {
    var pid: Int { get }
    var processInfo: [(String, String)] { get }
    var sharedLibraryInfoAddress: UInt64? { get }
    var hasFloatingPointRegisters: Bool { get }
    var breakpoints: GDBRemoteBreakpoints { get }

    func threadIDs() -> [UInt64]
    func threadName(_ tid: UInt64) -> String?
    func dispatchQueueAddress(_ tid: UInt64) -> UInt64?
    func stopInfo(_ tid: UInt64) -> GDBRemoteThreadStop
    func registers(_ tid: UInt64) -> GDBRemoteThreadRegisters?
    func setRegisters(_ tid: UInt64, _ registers: GDBRemoteThreadRegisters) -> Bool
    func readMemory(_ address: UInt64, count: Int) -> [UInt8]
    func writeMemory(_ address: UInt64, bytes: [UInt8]) -> Bool
    func memoryRegion(at address: UInt64) -> GDBRemoteMemoryRegion?
    var sharedCacheInfo: (base: UInt64, uuid: [UInt8])? { get }
    func allocateMemory(size: UInt64, permissions: String) -> UInt64?
    func deallocateMemory(_ address: UInt64) -> Bool

    func loadedImages() -> [(address: UInt64, path: String)]?
    var dyldState: GDBRemoteDyldState? { get }
    var watchpointSlots: Int { get }
    func insertWatchpoint(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> Result<Void, GDBRemoteError>
    func removeWatchpoint(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> Result<Void, GDBRemoteError>

    func resume(_ actions: [UInt64: GDBRemoteResume], others: GDBRemoteResume) -> Result<Void, GDBRemoteError>
    func interrupt()
    func waitForEvent() -> GDBRemoteEvent
    func detach()
    func kill()
}

extension GDBRemoteProcess {
    public var sharedCacheInfo: (base: UInt64, uuid: [UInt8])? { nil }
    public func allocateMemory(size: UInt64, permissions: String) -> UInt64? { nil }
    public func deallocateMemory(_ address: UInt64) -> Bool { false }
    public func loadedImages() -> [(address: UInt64, path: String)]? { nil }
    public var dyldState: GDBRemoteDyldState? { nil }
    public var watchpointSlots: Int { 0 }
    public func insertWatchpoint(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> Result<Void, GDBRemoteError> {
        .failure(GDBRemoteError(0x16, "no hardware watchpoints"))
    }
    public func removeWatchpoint(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> Result<Void, GDBRemoteError> { .success(()) }
}

public protocol GDBRemoteHost: AnyObject, Sendable {
    var hostInfo: [(String, String)] { get }
    func initialProcess() -> GDBRemoteProcess?
    func attach(pid: Int) -> Result<GDBRemoteProcess, GDBRemoteError>
    func attach(name: String, wait: Bool, includeExisting: Bool) -> Result<GDBRemoteProcess, GDBRemoteError>
    func processes() -> [(pid: Int, name: String)]
}

public final class GDBRemoteBreakpoints: @unchecked Sendable {
    public static let instruction: UInt32 = 0xD43E_0000
    public static let instructionBytes: [UInt8] = [0x00, 0x00, 0x3E, 0xD4]

    private let lock = NSLock()
    @inline(__always) private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private var saved: [UInt64: [UInt8]] = [:]
    private let read: (UInt64, Int) -> [UInt8]
    private let write: (UInt64, [UInt8]) -> Bool

    public init(read: @escaping (UInt64, Int) -> [UInt8], write: @escaping (UInt64, [UInt8]) -> Bool) {
        self.read = read
        self.write = write
    }

    public var addresses: [UInt64] { locked { saved.keys.sorted() } }
    public func contains(_ address: UInt64) -> Bool { locked { saved[address] != nil } }

    public func insert(_ address: UInt64) -> Result<Void, GDBRemoteError> {
        guard address & 3 == 0 else { return .failure(GDBRemoteError(0x16, "breakpoint address not 4-byte aligned")) }
        return locked {
            if saved[address] != nil { return .success(()) }
            let original = read(address, 4)
            guard original.count == 4 else { return .failure(GDBRemoteError(0x0E, "cannot read memory at the breakpoint")) }
            guard write(address, Self.instructionBytes) else { return .failure(GDBRemoteError(0x0E, "cannot write the breakpoint")) }
            saved[address] = original
            return .success(())
        }
    }

    public func remove(_ address: UInt64) -> Result<Void, GDBRemoteError> {
        locked {
            guard let original = saved[address] else { return .success(()) }
            guard write(address, original) else { return .failure(GDBRemoteError(0x0E, "cannot restore the bytes under the breakpoint")) }
            saved[address] = nil
            return .success(())
        }
    }

    public func removeAll() {
        for a in addresses { _ = remove(a) }
    }

    public func forgetAll() { locked { saved.removeAll() } }

    public func shadow(_ address: UInt64, _ bytes: [UInt8]) -> [UInt8] {
        locked {
            guard !saved.isEmpty, !bytes.isEmpty else { return bytes }
            var out = bytes
            let end = address &+ UInt64(bytes.count)
            for (bp, original) in saved where bp &+ 4 > address && bp < end {
                for i in 0..<4 {
                    let a = bp &+ UInt64(i)
                    if a >= address && a < end { out[Int(a - address)] = original[i] }
                }
            }
            return out
        }
    }

    public func writeThrough(_ address: UInt64, _ bytes: [UInt8]) -> Bool {
        locked {
            var out = bytes
            let end = address &+ UInt64(bytes.count)
            for (bp, original) in saved where bp &+ 4 > address && bp < end {
                var o = original
                for i in 0..<4 {
                    let a = bp &+ UInt64(i)
                    if a >= address && a < end {
                        o[i] = bytes[Int(a - address)]
                        out[Int(a - address)] = Self.instructionBytes[i]
                    }
                }
                saved[bp] = o
            }
            return write(address, out)
        }
    }
}
