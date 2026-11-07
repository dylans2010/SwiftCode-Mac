import YcodeDarwinABI

public enum MachKernelObject: Equatable, Sendable, CustomStringConvertible {
    case task
    case taskName
    case taskRead
    case taskInspect
    case thread(serial: UInt64)
    case host
    case bootstrap
    case clock(id: Int32)
    case semaphore(serial: UInt64)
    case fileport(serial: UInt64)
    case memoryEntry(serial: UInt64)
    case ioMain
    case ioObject(serial: UInt64)
    case workInterval(serial: UInt64)

    public var isTaskFlavor: Bool {
        switch self {
        case .task, .taskName, .taskRead, .taskInspect: true
        default: false
        }
    }

    public var description: String {
        switch self {
        case .task: "task"
        case .taskName: "task-name"
        case .taskRead: "task-read"
        case .taskInspect: "task-inspect"
        case let .fileport(serial): "fileport#\(serial)"
        case let .memoryEntry(serial): "memory-entry#\(serial)"
        case let .thread(serial): "thread#\(serial)"
        case .host: "host"
        case .bootstrap: "bootstrap"
        case let .clock(id): "clock(\(id))"
        case let .semaphore(serial): "semaphore#\(serial)"
        case .ioMain: "iokit-main"
        case let .ioObject(serial): "iokit-object#\(serial)"
        case let .workInterval(serial): "work-interval#\(serial)"
        }
    }
}

final class IPCPort {
    let serial: UInt64
    var kernelObject: MachKernelObject?
    var semaphore: KernelSemaphore?
    var isSpecialReply = false
    weak var task: MachIPC?
    var fileportFile: DarwinOpenFile?
    var memoryEntry: MachMemoryEntry?
    var workInterval: KernelWorkInterval?
    var mkTimer: MachTimer?
    var active = true
    weak var receiver: MachIPC?
    var inSpace: Bool { receiver != nil }
    weak var transitHolder: IPCPort?

    var srights = 0
    var sorights = 0
    var mscount: UInt32 = 0
    var seqno: UInt32 = 0
    var qlimit = MachIPCLimits.qlimitDefault
    var messages = MessageQueue()

    var context: UInt64 = 0
    var guarded = false
    var strict = false
    var immovable = false

    var pdRequest: IPCPort?
    var nsRequest: IPCPort?
    var dnRequests: [DNKey: IPCPort] = [:]
    var spRequests: [DNKey: Bool] = [:]
    var hasArmedSendPossible: Bool { spRequests.values.contains(true) }
    var deadNameNotified: Set<DNKey> = []

    var sets: [IPCPortSet] = []
    var readyStamp: UInt64 = 0
    var changeStamp: UInt64 = 0
    var waitingReceivers = 0
    var importanceCount = 0
    var importanceDonation = false
    var tempOwner = false
    weak var watchProcess: DarwinProcess?
    weak var creditedProcess: DarwinProcess?
    let receiveWaiters = WaitQueue()
    let sendWaiters = WaitQueue()
    var grantedSlots = 0
    var occupiedSlots: Int { messages.count + grantedSlots }
    var snapshotPendingSends: [(context: ObjectIdentifier, message: KMessage)] = []

    init(serial: UInt64) {
        self.serial = serial
    }

    var isKernelObject: Bool { kernelObject != nil }
}

struct DNKey: Hashable, Comparable {
    var space: UInt64
    var name: UInt32

    static func < (a: DNKey, b: DNKey) -> Bool { (a.name, a.space) < (b.name, b.space) }
}

struct MachSenderIdentity: Equatable {
    var uid: UInt32
    var gid: UInt32
    var pid: Int32
    var pidVersion: UInt32
    var auditSessionID: UInt32

    var auditToken: [UInt32] { [uid, uid, gid, uid, gid, UInt32(bitPattern: pid), auditSessionID, pidVersion] }
}

final class IPCPortSet {
    let serial: UInt64
    var name: UInt32 = 0
    var members: [IPCPort] = []
    var active = true
    var changeStamp: UInt64 = 0
    var waitingReceivers = 0
    let waiters = WaitQueue()

    init(serial: UInt64) {
        self.serial = serial
    }
}

struct IPCEntry {
    var generation: UInt32 = 63
    var inUse = false
    var bits: UInt32 = 0
    var urefs: UInt32 = 0
    var port: IPCPort?
    var set: IPCPortSet?
}

enum CarriedRight {
    case null
    case dead
    case send(IPCPort)
    case sendOnce(IPCPort)
    case receive(IPCPort)

    var port: IPCPort? {
        switch self {
        case .null, .dead: nil
        case let .send(p), let .sendOnce(p), let .receive(p): p
        }
    }

    var rawName: UInt32? {
        switch self {
        case .null: MachPortName.null
        case .dead: MachPortName.dead
        default: nil
        }
    }
}

enum KItem {
    case port(CarriedRight, type: UInt32)
    case ool(data: [UInt8], copy: UInt8, volatile: Bool)
    case oolPorts([CarriedRight], type: UInt32, copy: UInt8)
    case guarded(CarriedRight, flags: UInt16, type: UInt32)

    var wireSize: Int {
        if case .port = self { return 12 }
        return 16
    }

    var rightCount: Int {
        switch self {
        case .port, .guarded: 1
        case let .oolPorts(rights, _, _): rights.count
        case .ool: 0
        }
    }
}

struct KMessage {
    var complex: Bool
    var destination: CarriedRight
    var destinationType: UInt32
    var reply: CarriedRight
    var replyType: UInt32
    var voucherRaw: UInt32 = 0
    var id: Int32
    var items: [KItem] = []
    var inline: [UInt8] = []
    var aux: [UInt8]?
    var fromKernel = false
    var isTimerExpiry = false
    var sender: MachSenderIdentity?
    var importance = false
    var pushClass: Int8 = -1

    var size: Int {
        24 + (complex ? 4 + items.reduce(0) { $0 + $1.wireSize } : 0) + inline.count
    }

    var receiveRights: [IPCPort] {
        var out: [IPCPort] = []
        for item in items {
            switch item {
            case let .port(.receive(p), _), let .guarded(.receive(p), _, _): out.append(p)
            case let .oolPorts(rights, _, _):
                for case let .receive(p) in rights { out.append(p) }
            default: break
            }
        }
        return out
    }
}

struct MessageQueue {
    private var items: [KMessage] = []
    private var head = 0

    var count: Int { items.count - head }
    var isEmpty: Bool { count == 0 }
    var first: KMessage? { isEmpty ? nil : items[head] }

    mutating func append(_ m: KMessage) { items.append(m) }

    mutating func popFirst() -> KMessage? {
        guard !isEmpty else { return nil }
        let m = items[head]
        head += 1
        if head > 64 && head * 2 > items.count {
            items.removeFirst(head)
            head = 0
        }
        return m
    }

    mutating func removeAll() -> [KMessage] {
        let all = Array(items[head...])
        items = []
        head = 0
        return all
    }

    var all: ArraySlice<KMessage> { items[head...] }
}

public enum MachReceiveTarget: Equatable, Sendable {
    case none
    case notReceivable
    case port
    case specialReplyPort
    case portSet
}
