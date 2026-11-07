import Foundation
import SwiftCodeDarwinABI

typealias Code = DarwinErrnoCode

func fail(_ errno: Int32) -> DarwinErrnoError { DarwinErrnoError(errno) }

final class ObjectSignals {
    let waiters = WaitQueue()
    private var observers: [Int: () -> Void] = [:]
    private var nextToken = 1

    func addObserver(_ observer: @escaping () -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        observers[token] = observer
        return token
    }

    func removeObserver(_ token: Int) { observers[token] = nil }

    func fire() {
        waiters.wakeAll()
        for token in observers.keys.sorted() {
            observers[token]?()
        }
    }
}

struct DescriptorUser {
    var pid: Int32
    var pidVersion: UInt32
    var uid: UInt32
    var gid: UInt32
    weak var kernel: DarwinKernel?

    var xucred: [UInt8] {
        var b = [UInt8](repeating: 0, count: 76)
        b.putLE(UInt32(0), at: 0)
        b.putLE(uid, at: 4)
        b.putLE(Int16(1), at: 8)
        b.putLE(gid, at: 12)
        return b
    }
}

extension DarwinKernel {
    var descriptorUser: DescriptorUser {
        DescriptorUser(pid: pid, pidVersion: pidVersion, uid: DarwinFileSystem.guestUID,
                       gid: DarwinFileSystem.guestGID, kernel: self)
    }

    var descriptorAuditToken: [UInt8] {
        let uid = DarwinFileSystem.guestUID, gid = DarwinFileSystem.guestGID
        var b: [UInt8] = []
        for v in [uid, uid, gid, uid, gid, UInt32(bitPattern: pid), 0, pidVersion] { b.appendLE(v) }
        return b
    }

    func waitOnObject(_ signals: ObjectSignals, deadline: UInt64?) throws -> Bool {
        switch signals.waiters.wait(on: lock, deadline: deadline) {
        case .woken: return true
        case .timedOut: return false
        case .interrupted: throw fail(Code.EINTR)
        }
    }
}

struct ByteQueue {
    private var storage: [UInt8] = []
    private var head = 0

    var count: Int { storage.count - head }
    var isEmpty: Bool { count == 0 }

    mutating func append<C: Collection>(contentsOf bytes: C) where C.Element == UInt8 {
        storage.append(contentsOf: bytes)
    }

    func peek(_ n: Int) -> [UInt8] {
        Array(storage[head..<(head + min(n, count))])
    }

    mutating func take(_ n: Int) -> [UInt8] {
        let out = peek(n)
        head += out.count
        if head == storage.count {
            storage.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 4096 && head * 2 >= storage.count {
            storage.removeFirst(head)
            head = 0
        }
        return out
    }

    mutating func removeAll() {
        storage.removeAll()
        head = 0
    }
}

enum DescriptorInodes {
    private static let mutex = RecursiveMutex(name: "descriptor inodes")
    nonisolated(unsafe) private static var next: UInt64 = 0x7964_0000_0000_0001

    static func make() -> UInt64 {
        mutex.lock()
        defer { mutex.unlock() }
        let v = next
        next += 1
        return v
    }
}

func descriptorNow() -> DarwinTimespec {
    let t = Date().timeIntervalSince1970
    let s = t.rounded(.down)
    return DarwinTimespec(sec: Int64(s), nsec: Int64((t - s) * 1e9))
}

let descriptorSIGPIPE: Int32 = 13
