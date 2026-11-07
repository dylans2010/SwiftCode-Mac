import Foundation
import Synchronization
import YcodeDarwinABI

public final class KernelWorkInterval: @unchecked Sendable, Equatable {
    public let id: UInt64
    public let createFlags: UInt32
    public let creatorPID: Int32

    public init(id: UInt64, createFlags: UInt32, creatorPID: Int32) {
        self.id = id
        self.createFlags = createFlags
        self.creatorPID = creatorPID
    }

    public static func == (a: KernelWorkInterval, b: KernelWorkInterval) -> Bool { a === b }

    private static let counter = Mutex<UInt64>(1)
    public static func nextID() -> UInt64 { counter.withLock { $0 += 1; return $0 } }
    static func noteRestoredID(_ id: UInt64) { counter.withLock { $0 = max($0, id) } }
}

public enum WorkIntervalABI {
    public static let syscall = 499
    public static let operationCreate: UInt32 = 1, operationDestroy: UInt32 = 2, operationNotify: UInt32 = 3
    public static let operationCreate2: UInt32 = 4, operationJoin: UInt32 = 5, operationGetFlags: UInt32 = 9
    public static let flagJoinable: UInt32 = 0x1, flagGroup: UInt32 = 0x2, flagUnrestricted: UInt32 = 0x4
    public static let flagEnableAutoJoin: UInt32 = 0x8, flagEnableDeferredFinish: UInt32 = 0x10
    public static let flagIgnored: UInt32 = 0x20
    public static let typeMask: UInt32 = 0xF000_0000
    public static let typeDefault: UInt32 = 0, typeCoreAudio: UInt32 = 0x1000_0000
    public static let createParamsSize = 16
    public static let notificationSize = 40

    static func operationName(_ op: UInt32) -> String {
        switch op {
        case operationCreate: "create"
        case operationDestroy: "destroy"
        case operationNotify: "notify"
        case operationCreate2: "create2"
        case operationJoin: "join"
        case operationGetFlags: "get_flags"
        default: "op\(op)"
        }
    }
}

extension MachIPC {
    func makeWorkIntervalName(flags: UInt32, creatorPID: Int32) -> (KernelWorkInterval, UInt32)? {
        let wi = KernelWorkInterval(id: KernelWorkInterval.nextID(), createFlags: flags, creatorPID: creatorPID)
        guard let (p, name) = makeKernelObjectName(.workInterval(serial: nextSerial())) else { return nil }
        p.workInterval = wi
        return (wi, name)
    }

    func workInterval(named name: UInt32) -> KernelWorkInterval? {
        guard let (p, object) = kernelObject(named: name), case .workInterval = object, p.active else { return nil }
        return p.workInterval
    }
}

extension MachHostTask {
    public func makeWorkIntervalPort(flags: UInt32) throws -> UInt32 {
        try lock.withLock {
            guard let (_, name) = ipc.makeWorkIntervalName(flags: flags | WorkIntervalABI.flagJoinable, creatorPID: 0) else {
                throw MachHostError(MachKern.noSpace)
            }
            return name
        }
    }

    public func workInterval(named name: UInt32) -> KernelWorkInterval? {
        lock.withLock { ipc.workInterval(named: name) }
    }
}

extension DarwinKernel {
    static let debugWorkIntervals = getenv("SWIFTCODE_DEBUG_WORK_INTERVALS").map { String(cString: $0) == "1" } ?? false

    func workIntervalCtl(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let op = UInt32(truncatingIfNeeded: a[0])
        call.set("work_interval_ctl(\(WorkIntervalABI.operationName(op)), id=\(hx(a[1])), arg=\(hx(a[2])), len=\(a[3]))")
        do {
            let note = try workIntervalOperation(op, id: a[1], arg: a[2], len: a[3], mem)
            call += " [\(note)]"
            if Self.debugWorkIntervals { debugWorkInterval(op, a, "ok: \(note)") }
            return 0
        } catch let f as Failure {
            if Self.debugWorkIntervals { debugWorkInterval(op, a, Errno.name(f.errno)) }
            throw f
        }
    }

    private func debugWorkInterval(_ op: UInt32, _ a: [UInt64], _ result: String) {
        FileHandle.standardError.write(Data(("swiftcode-work-interval: pid \(pid) (\(processRecord?.comm ?? "?")) thread "
            + "\(current.threadID) \(WorkIntervalABI.operationName(op)) id=\(hx(a[1])) -> \(result)\n").utf8))
    }

    private func workIntervalOperation(_ op: UInt32, id: UInt64, arg: UInt64, len: UInt64,
                                       _ mem: any KernelGuestMemory) throws -> String {
        let thread = current
        switch op {
        case WorkIntervalABI.operationCreate:
            throw Failure(errno: Errno.ENOTSUP)

        case WorkIntervalABI.operationCreate2:
            throw Failure(errno: Errno.ENOSYS)

        case WorkIntervalABI.operationGetFlags:
            guard arg != 0, len >= UInt64(WorkIntervalABI.createParamsSize) else { throw Failure(errno: Errno.EINVAL) }
            let name = UInt32(truncatingIfNeeded: id)
            guard MachPortName.isValid(name), let wi = try lookUpWorkInterval(name) else { throw Failure(errno: Errno.EINVAL) }
            var record: [UInt8] = []
            record.appendLE(UInt64(0))
            record.appendLE(name)
            record.appendLE(wi.createFlags)
            try mem.write(va: arg, bytes: record)
            return "flags \(hx(UInt64(wi.createFlags)))"

        case WorkIntervalABI.operationJoin:
            guard arg == 0 else { throw Failure(errno: Errno.EINVAL) }
            let name = UInt32(truncatingIfNeeded: id)
            if name == 0 {
                let left = thread.workInterval
                thread.workInterval = nil
                return left.map { "left #\($0.id)" } ?? "left (none)"
            }
            guard MachPortName.isValid(name), let wi = try lookUpWorkInterval(name) else { throw Failure(errno: Errno.EINVAL) }
            thread.workInterval = wi
            return "joined #\(wi.id)"

        case WorkIntervalABI.operationDestroy:
            guard arg == 0, id != 0 else { throw Failure(errno: Errno.EINVAL) }
            guard let wi = thread.workInterval, wi.id == id else { throw Failure(errno: Errno.EINVAL) }
            thread.workInterval = nil
            return "left #\(wi.id)"

        case WorkIntervalABI.operationNotify:
            guard arg != 0, id != 0, len >= UInt64(WorkIntervalABI.notificationSize) else {
                throw Failure(errno: Errno.EINVAL)
            }
            _ = try mem.read(va: arg, count: WorkIntervalABI.notificationSize)
            guard let wi = thread.workInterval, wi.id == id, wi.creatorPID == pid else { throw Failure(errno: Errno.EINVAL) }
            return "noted"

        default:
            throw Failure(errno: Errno.ENOTSUP)
        }
    }

    private func lookUpWorkInterval(_ name: UInt32) throws -> KernelWorkInterval? {
        guard let ipc = machIPC as? MachIPC else { return nil }
        return withPorts { ipc.workInterval(named: name) }
    }
}
