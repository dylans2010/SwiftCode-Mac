import CKVM
import SwiftCodeDarwinABI

public enum Hypervisor {
    public static var isAvailable: Bool { ckvm_available() != 0 }
}

#if os(Linux) && arch(arm64)
extension Hypervisor {
    public static func hostCounter() -> UInt64 { ckvm_host_cntvct() }
    public static func hostIDAA64MMFR2() -> UInt64 { ckvm_host_id_aa64mmfr2() }
}
#endif

public struct KVMError: Error, CustomStringConvertible, Equatable, Sendable {
    public var operation: String
    public var errno: Int32
    public var detail: String

    public init(_ operation: String, errno: Int32 = 0, detail: String = "") {
        self.operation = operation
        self.errno = errno
        self.detail = detail
    }

    public var description: String {
        var text = "\(operation) failed"
        if errno != 0 { text += " (errno \(errno))" }
        if !detail.isEmpty { text += ": \(detail)" }
        return text
    }
}

#if os(Linux) && arch(arm64)
import Glibc
import Synchronization

let quarantineHostMemory = getenv("SWIFTCODE_DEBUG_QUARANTINE").map { String(cString: $0) == "1" } ?? false

public enum HardwareWatchpoint {
    public static func arm(_ slot: Int, _ address: UInt64) -> Int32 { ckvm_hwwatch_arm_slot(Int32(slot), address) }
    public static func disarm(_ slot: Int) { ckvm_hwwatch_disarm_slot(Int32(slot)) }
    public static func startMemoryCheck(threads: Int) { _ = ckvm_memcheck_start(Int32(threads)) }
    public static func installFrameCapture() { DebugAccessGuard.captureFrames = ckvm_capture_frames }
}

func releaseHostMemory(_ address: UnsafeMutableRawPointer, _ size: Int) {
    if quarantineHostMemory {
        _ = mmap(address, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED, -1, 0)
    } else {
        munmap(address, size)
    }
}

@discardableResult
func kvmCheck(_ result: Int32, _ operation: String) throws -> Int32 {
    if result < 0 { throw KVMError(operation, errno: -result, detail: String(cString: strerror(-result))) }
    return result
}

public struct MemorySlot: Sendable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable { case ram, anonymousPool, file, shared, readOnlyFiles }
    public var slot: UInt32
    public var gpa: UInt64
    public var size: UInt64
    public var hostAddress: UInt
    public var kind: Kind
    public var name: String
    public var readOnly: Bool = false

    public var end: UInt64 { gpa + size }
    public func contains(gpa a: UInt64, count: Int) -> Bool {
        guard count >= 0, a >= gpa else { return false }
        let offset = a - gpa
        return offset <= size && UInt64(count) <= size - offset
    }
    public var description: String {
        "slot \(slot) gpa 0x\(String(gpa, radix: 16))-0x\(String(end, radix: 16)) \(kind) \(name)"
    }
}

public final class VirtualMachine: @unchecked Sendable {
    public let kvmFD: Int32
    public let vmFD: Int32
    public let ramGPA: UInt64
    public let ramSize: Int
    public let ram: UnsafeMutableRawPointer
    public var vcpus: [VCPU] { lock.withLock { vcpuList } }
    private var vcpuList: [VCPU] = []
    private var spareVCPUs: [Int: VCPU] = [:]
    private var creatingIDs: Set<Int> = []
    public var vcpuIDLimit: Int {
        get { lock.withLock { idLimit } }
        set { lock.withLock { idLimit = newValue } }
    }
    private var idLimit = Int.max

    public static let creationBatch = getenv("SWIFTCODE_VCPU_BATCH").flatMap { Int(String(cString: $0)) }.map { max(0, $0) } ?? 3

    public static let precreateCount = getenv("SWIFTCODE_VCPU_PRECREATE").flatMap { Int(String(cString: $0)) }
        .map { max(1, min($0, 64)) } ?? (creationBatch + 1)

    public static let batchGrow = getenv("SWIFTCODE_VCPU_BATCH_GROW").map { String(cString: $0) == "1" } ?? false
    public let maxMemorySlots: Int
    public let supportsReadOnlyMemory: Bool
    public let maxVCPUs: Int
    public let recommendedVCPUs: Int
    public var memorySlots: [MemorySlot] { lock.withLock { slotList } }
    private var slotList: [MemorySlot] = []
    private var nextSlotNumber: UInt32 = 1
    private let lock = HostMutex(name: "VM")
    private var creationsInFlight = 0
    private let slotChangeLock = HostMutex(name: "VM memslot changes")
    private let creationsDone = HostCondition()
    private let closedFlag = Atomic<Bool>(false)
    public var isClosed: Bool { closedFlag.load(ordering: .acquiring) }

    static let capReadOnlyMemory = 81
    static let memoryFlagReadOnly: UInt32 = 1 << 1

    public static let createVMCount = Atomic<UInt64>(0)
    public static let createVMNanoseconds = Atomic<UInt64>(0)
    public static let closeCount = Atomic<UInt64>(0)
    public static let closeNanoseconds = Atomic<UInt64>(0)

    public static let defaultRAMGPA: UInt64 = 0x4000_0000
    public static let defaultRAMSize = 512 << 20

    public init(ramGPA: UInt64 = VirtualMachine.defaultRAMGPA, ramSize: Int = VirtualMachine.defaultRAMSize) throws {
        let kvm = try kvmCheck(ckvm_open(), "open /dev/kvm")
        var vm: Int32 = -1
        var ramPointer: UnsafeMutableRawPointer?
        var slotLimit = 0
        var readOnlyMemory = false
        var vcpuLimits = (max: 0, recommended: 0)
        do {
            let version = try kvmCheck(ckvm_get_api_version(kvm), "KVM_GET_API_VERSION")
            guard version == 12 else { throw KVMError("KVM_GET_API_VERSION", detail: "unexpected API version \(version)") }
            let createBegan = monotonicNanoseconds()
            vm = try kvmCheck(ckvm_create_vm(kvm, 0), "KVM_CREATE_VM")
            Self.createVMNanoseconds.wrappingAdd(monotonicNanoseconds() &- createBegan, ordering: .relaxed)
            Self.createVMCount.wrappingAdd(1, ordering: .relaxed)
            slotLimit = Int(ckvm_check_extension(vm, Int(CKVM_CAP_NR_MEMSLOTS)))
            if slotLimit <= 0 { slotLimit = Int(ckvm_check_extension(kvm, Int(CKVM_CAP_NR_MEMSLOTS))) }
            readOnlyMemory = ckvm_check_extension(vm, Self.capReadOnlyMemory) > 0
                || ckvm_check_extension(kvm, Self.capReadOnlyMemory) > 0
            guard slotLimit > 0 else { throw KVMError("KVM_CAP_NR_MEMSLOTS", detail: "the kernel reports no memslots") }
            func capability(_ cap: Int) -> Int {
                let v = Int(ckvm_check_extension(vm, cap))
                return v > 0 ? v : max(0, Int(ckvm_check_extension(kvm, cap)))
            }
            let recommended = capability(Int(CKVM_CAP_NR_VCPUS))
            vcpuLimits.recommended = recommended > 0 ? recommended : 4
            let hard = capability(Int(CKVM_CAP_MAX_VCPUS))
            vcpuLimits.max = hard > 0 ? hard : vcpuLimits.recommended
            guard let pointer = ckvm_alloc_anonymous(ramSize) else {
                throw KVMError("mmap guest RAM", errno: Glibc.errno)
            }
            ramPointer = pointer
            try kvmCheck(ckvm_set_user_memory_region(vm, 0, 0, ramGPA, UInt64(ramSize), UInt64(UInt(bitPattern: pointer))),
                         "KVM_SET_USER_MEMORY_REGION")
        } catch {
            if let ramPointer { _ = ckvm_free_anonymous(ramPointer, ramSize) }
            if vm >= 0 { _ = ckvm_close(vm) }
            _ = ckvm_close(kvm)
            throw error
        }
        self.kvmFD = kvm
        self.vmFD = vm
        self.ramGPA = ramGPA
        self.ramSize = ramSize
        self.ram = ramPointer!
        self.maxMemorySlots = slotLimit
        self.supportsReadOnlyMemory = readOnlyMemory
        self.maxVCPUs = vcpuLimits.max
        self.recommendedVCPUs = vcpuLimits.recommended
        self.slotList = [MemorySlot(slot: 0, gpa: ramGPA, size: UInt64(ramSize),
                                       hostAddress: UInt(bitPattern: ramPointer!), kind: .ram, name: "RAM")]
    }

    deinit { close() }

    public func close() {
        let detached: (vcpus: [VCPU], slots: [MemorySlot])? = lock.withLock {
            guard !closedFlag.exchange(true, ordering: .acquiringAndReleasing) else { return nil }
            while creationsInFlight > 0 { creationsDone.wait(lock) }
            let taken = (vcpuList + spareVCPUs.values, slotList)
            spareVCPUs.removeAll()
            vcpuList.removeAll()
            slotList.removeAll()
            return taken
        }
        guard let detached else { return }
        let closeBegan = monotonicNanoseconds()
        detached.vcpus.forEach { $0.close() }
        _ = ckvm_close(vmFD)
        for slot in detached.slots where slot.kind != .shared && slot.kind != .readOnlyFiles {
            releaseHostMemory(UnsafeMutableRawPointer(bitPattern: slot.hostAddress)!, Int(slot.size))
        }
        _ = ckvm_close(kvmFD)
        Self.closeNanoseconds.wrappingAdd(monotonicNanoseconds() &- closeBegan, ordering: .relaxed)
        Self.closeCount.wrappingAdd(1, ordering: .relaxed)
    }

    public var supportsCounterOffset: Bool {
        ckvm_check_extension(vmFD, Int(CKVM_CAP_COUNTER_OFFSET)) > 0
            || ckvm_check_extension(kvmFD, Int(CKVM_CAP_COUNTER_OFFSET)) > 0
    }

    public func setCounterOffset(_ offset: UInt64) throws {
        if lock.withLock({ counterOffsetSet == offset }) { return }
        try kvmCheck(ckvm_set_counter_offset(vmFD, offset), "KVM_ARM_SET_COUNTER_OFFSET")
        lock.withLock { counterOffsetSet = offset }
    }
    private var counterOffsetSet: UInt64?
    private var hvcDoorbellInstalled = false

    public static let hvcDoorbellFunction: UInt32 = 0xC600_5943

    public func installHVCDoorbell() throws {
        if lock.withLock({ hvcDoorbellInstalled }) { return }
        try kvmCheck(ckvm_set_smccc_filter(vmFD, Self.hvcDoorbellFunction, 1, UInt8(CKVM_SMCCC_FILTER_FWD_TO_USER)),
                     "KVM_SET_DEVICE_ATTR(KVM_ARM_VM_SMCCC_FILTER)")
        lock.withLock { hvcDoorbellInstalled = true }
    }

    public private(set) var reuseCount = 0

    public func resetForReuse() -> Bool {
        let vcpus: [VCPU]? = lock.withLock {
            guard !isClosed, creationsInFlight == 0, creatingIDs.isEmpty else { return nil }
            let all = vcpuList + Array(spareVCPUs.values)
            vcpuList.removeAll()
            spareVCPUs.removeAll()
            return all
        }
        guard let vcpus else { return false }
        var ok = true
        for vcpu in vcpus where ok { ok = vcpu.reset(vmFD: vmFD) }
        lock.withLock {
            if ok { for vcpu in vcpus { spareVCPUs[vcpu.id] = vcpu } } else { vcpuList += vcpus }
            if ok { reuseCount += 1 }
        }
        guard ok else { return false }
        _ = ckvm_discard_anonymous(ram, ramSize)
        return true
    }

    public func makeVCPU(id: Int? = nil) throws -> VCPU {
        enum Plan { case spare(VCPU), create([Int]) }
        let plan: Plan = try lock.withLock {
            guard !isClosed else { throw KVMError("KVM_CREATE_VCPU", errno: EBADF, detail: "the VM is closed") }
            let known = Set(vcpuList.map(\.id)).union(spareVCPUs.keys)
            let vcpuID = id ?? ((known.union(creatingIDs).max() ?? -1) + 1)
            while creatingIDs.contains(vcpuID) { creationsDone.wait(lock) }
            guard !isClosed else { throw KVMError("KVM_CREATE_VCPU", errno: EBADF, detail: "the VM is closed") }
            if let spare = spareVCPUs.removeValue(forKey: vcpuID) {
                vcpuList.append(spare)
                return .spare(spare)
            }
            var ids = [vcpuID]
            var next = vcpuID + 1
            let taken = known.union(creatingIDs)
            let existing = vcpuList.count + spareVCPUs.count + creatingIDs.count
            let batch = existing == 0 ? Self.precreateCount
                : Self.batchGrow ? max(Self.creationBatch + 1, existing) : Self.creationBatch + 1
            while ids.count < batch, next < idLimit {
                if !taken.contains(next) { ids.append(next) }
                next += 1
            }
            creatingIDs.formUnion(ids)
            creationsInFlight += 1
            return .create(ids)
        }
        guard case let .create(ids) = plan else {
            if case let .spare(vcpu) = plan { return vcpu }
            fatalError("unreachable")
        }
        let created = Result { try VCPU(vm: self, id: ids[0]) }
        var spares: [VCPU] = []
        if case .success = created {
            for spareID in ids.dropFirst() {
                guard let spare = try? VCPU(vm: self, id: spareID) else { break }
                spares.append(spare)
            }
        }
        lock.withLock {
            if case let .success(vcpu) = created { vcpuList.append(vcpu) }
            for spare in spares { spareVCPUs[spare.id] = spare }
            creatingIDs.subtract(ids)
            creationsInFlight -= 1
            creationsDone.broadcast()
        }
        return try created.get()
    }

    public func makeSpareVCPUs(count: Int) {
        let ids: [Int]? = lock.withLock {
            guard !isClosed, vcpuList.isEmpty, spareVCPUs.isEmpty, creatingIDs.isEmpty else { return nil }
            let ids = Array(0..<max(0, min(count, idLimit)))
            creatingIDs.formUnion(ids)
            creationsInFlight += 1
            return ids
        }
        guard let ids else { return }
        var spares: [VCPU] = []
        for id in ids {
            guard let vcpu = try? VCPU(vm: self, id: id) else { break }
            spares.append(vcpu)
        }
        lock.withLock {
            for spare in spares { spareVCPUs[spare.id] = spare }
            creatingIDs.subtract(ids)
            creationsInFlight -= 1
            creationsDone.broadcast()
        }
    }

    @discardableResult
    public func addMemorySlot(gpa: UInt64, size: UInt64, host: UnsafeMutableRawPointer,
                              kind: MemorySlot.Kind, name: String, readOnly: Bool = false) throws -> MemorySlot {
        try slotChangeLock.withLock {
            let (number, index) = try lock.withLock { () throws -> (UInt32, Int) in
                let reserved = try reserveMemorySlot(gpa: gpa, size: size, name: name, readOnly: readOnly)
                creationsInFlight += 1
                return reserved
            }
            defer {
                lock.withLock {
                    creationsInFlight -= 1
                    if creationsInFlight == 0 { creationsDone.broadcast() }
                }
            }
            try kvmCheck(ckvm_set_user_memory_region(vmFD, number, readOnly ? Self.memoryFlagReadOnly : 0, gpa, size,
                                                     UInt64(UInt(bitPattern: host))),
                         "KVM_SET_USER_MEMORY_REGION slot \(number) (\(name))")
            let slot = MemorySlot(slot: number, gpa: gpa, size: size, hostAddress: UInt(bitPattern: host), kind: kind, name: name,
                                  readOnly: readOnly)
            lock.withLock { slotList.insert(slot, at: index) }
            return slot
        }
    }

    private func reserveMemorySlot(gpa: UInt64, size: UInt64, name: String, readOnly: Bool) throws -> (UInt32, Int) {
        guard !isClosed else { throw KVMError("KVM_SET_USER_MEMORY_REGION", errno: EBADF, detail: "the VM is closed") }
        guard Int(nextSlotNumber) < maxMemorySlots else {
            throw KVMError("KVM_SET_USER_MEMORY_REGION", detail: "memslots exhausted (KVM_CAP_NR_MEMSLOTS = \(maxMemorySlots)) mapping \(name)")
        }
        guard size > 0 else { throw KVMError("KVM_SET_USER_MEMORY_REGION", detail: "empty slot for \(name)") }
        if readOnly && !supportsReadOnlyMemory {
            throw KVMError("KVM_SET_USER_MEMORY_REGION", detail: "read-only memslots are not supported (\(name))")
        }
        let index = slotIndex(after: gpa)
        for i in [index - 1, index] where i >= 0 && i < slotList.count {
            let other = slotList[i]
            if gpa < other.end && other.gpa < gpa + size {
                throw KVMError("KVM_SET_USER_MEMORY_REGION", detail: "GPA range of \(name) overlaps \(other)")
            }
        }
        let number = nextSlotNumber
        nextSlotNumber += 1
        return (number, index)
    }

    public var memorySlotCount: Int { lock.withLock { slotList.count } }

    private func slotIndex(after gpa: UInt64) -> Int {
        var low = 0, high = slotList.count
        while low < high {
            let mid = (low + high) / 2
            if slotList[mid].gpa <= gpa { low = mid + 1 } else { high = mid }
        }
        return low
    }

    public func memorySlot(containing gpa: UInt64) -> MemorySlot? {
        if isClosed { return nil }
        if gpa >= ramGPA, gpa - ramGPA < UInt64(ramSize) {
            return MemorySlot(slot: 0, gpa: ramGPA, size: UInt64(ramSize), hostAddress: UInt(bitPattern: ram), kind: .ram, name: "RAM")
        }
        return lock.withLock {
            let low = slotIndex(after: gpa)
            guard low > 0, gpa < slotList[low - 1].end else { return nil }
            return slotList[low - 1]
        }
    }

    public func writableHostPointer(gpa: UInt64, count: Int) throws -> UnsafeMutableRawPointer {
        guard let slot = memorySlot(containing: gpa), slot.contains(gpa: gpa, count: count) else {
            throw KVMError("guest physical access", detail: "GPA 0x\(String(gpa, radix: 16)) + \(count) is outside every memslot")
        }
        guard !slot.readOnly else {
            throw KVMError("guest physical write", errno: EFAULT, detail: "GPA 0x\(String(gpa, radix: 16)) is in read-only \(slot)")
        }
        return UnsafeMutableRawPointer(bitPattern: slot.hostAddress)! + Int(gpa - slot.gpa)
    }

    public func contains(gpa: UInt64, count: Int) -> Bool {
        memorySlot(containing: gpa)?.contains(gpa: gpa, count: count) ?? false
    }

    public func hostPointer(gpa: UInt64, count: Int) throws -> UnsafeMutableRawPointer {
        guard let slot = memorySlot(containing: gpa), slot.contains(gpa: gpa, count: count) else {
            throw KVMError("guest physical access", detail: "GPA 0x\(String(gpa, radix: 16)) + \(count) is outside every memslot")
        }
        return UnsafeMutableRawPointer(bitPattern: slot.hostAddress)! + Int(gpa - slot.gpa)
    }

    public func cleanDataCache(gpa: UInt64, count: Int) throws {
        let pointer = try hostPointer(gpa: gpa, count: count)
        ckvm_clean_dcache_range(pointer, count)
    }

    private func pointer(gpa: UInt64, count: Int) throws -> UnsafeMutableRawPointer {
        try hostPointer(gpa: gpa, count: count)
    }

    public func read(gpa: UInt64, count: Int) throws -> [UInt8] {
        let source = try pointer(gpa: gpa, count: count)
        return [UInt8](UnsafeRawBufferPointer(start: source, count: count))
    }

    public func write(gpa: UInt64, bytes: [UInt8]) throws {
        let destination = try writableHostPointer(gpa: gpa, count: bytes.count)
        bytes.withUnsafeBytes { if !$0.isEmpty { destination.copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
    }

    public func readU64(gpa: UInt64) throws -> UInt64 {
        let source = try pointer(gpa: gpa, count: 8)
        return UInt64(littleEndian: source.loadUnaligned(as: UInt64.self))
    }

    public func writeU64(gpa: UInt64, _ value: UInt64) throws {
        let destination = try writableHostPointer(gpa: gpa, count: 8)
        destination.storeBytes(of: value.littleEndian, as: UInt64.self)
    }

    public func zero(gpa: UInt64, count: Int) throws {
        let destination = try writableHostPointer(gpa: gpa, count: count)
        destination.initializeMemory(as: UInt8.self, repeating: 0, count: count)
    }
}

public enum VCPUExit: Equatable, Sendable, CustomStringConvertible {
    public enum MMIODirection: Equatable, Sendable { case read, write }
    case mmio(MMIODirection, address: UInt64, data: UInt64, length: Int)
    case hlt
    case shutdown
    case systemEvent(type: UInt32, data: [UInt64])
    case internalError(suberror: UInt32, data: [UInt64])
    case failEntry(reason: UInt64, cpu: UInt32)
    case armNISV(esrISS: UInt64, faultIPA: UInt64)
    case watchdog
    case hypercall(function: UInt64, flags: UInt64)
    case interrupted
    case other(reason: UInt32)

    public var description: String {
        func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }
        switch self {
        case let .mmio(direction, address, data, length):
            return "mmio \(direction == .write ? "write" : "read") \(hex(address)) len \(length)" + (direction == .write ? " data \(hex(data))" : "")
        case .hlt: return "hlt"
        case .shutdown: return "shutdown"
        case let .systemEvent(type, data): return "system event type \(type) data \(data.map(hex))"
        case let .internalError(suberror, data): return "internal error suberror \(suberror) data \(data.map(hex))"
        case let .failEntry(reason, cpu): return "fail entry reason \(hex(reason)) cpu \(cpu)"
        case let .armNISV(iss, ipa): return "data abort without syndrome: ESR ISS \(hex(iss)) IPA \(hex(ipa))"
        case .watchdog: return "watchdog timeout"
        case let .hypercall(function, flags): return "hypercall function \(hex(function)) flags \(hex(flags))"
        case .interrupted: return "interrupted"
        case let .other(reason): return "exit reason \(reason)"
        }
    }
}

public enum CoreRegister: Equatable, Sendable {
    case x(Int)
    case spEL0, pc, pstate, spEL1, elrEL1, spsrEL1

    var id: UInt64 {
        switch self {
        case let .x(n):
            precondition((0...30).contains(n), "x\(n) is not a general-purpose register")
            return ckvm_reg_x(UInt32(n))
        case .spEL0: return ckvm_reg_sp_el0()
        case .pc: return ckvm_reg_pc()
        case .pstate: return ckvm_reg_pstate()
        case .spEL1: return ckvm_reg_sp_el1()
        case .elrEL1: return ckvm_reg_elr_el1()
        case .spsrEL1: return ckvm_reg_spsr_el1()
        }
    }
}

public struct SystemRegister: Equatable, Sendable {
    public var op0, op1, crn, crm, op2: UInt32
    public init(op0: UInt32, op1: UInt32, crn: UInt32, crm: UInt32, op2: UInt32) {
        (self.op0, self.op1, self.crn, self.crm, self.op2) = (op0, op1, crn, crm, op2)
    }
    var id: UInt64 { ckvm_reg_sysreg(op0, op1, crn, crm, op2) }

    public static let sctlrEL1 = SystemRegister(op0: 3, op1: 0, crn: 1, crm: 0, op2: 0)
    public static let ttbr0EL1 = SystemRegister(op0: 3, op1: 0, crn: 2, crm: 0, op2: 0)
    public static let tcrEL1 = SystemRegister(op0: 3, op1: 0, crn: 2, crm: 0, op2: 2)
    public static let esrEL1 = SystemRegister(op0: 3, op1: 0, crn: 5, crm: 2, op2: 0)
    public static let farEL1 = SystemRegister(op0: 3, op1: 0, crn: 6, crm: 0, op2: 0)
    public static let mairEL1 = SystemRegister(op0: 3, op1: 0, crn: 10, crm: 2, op2: 0)
    public static let vbarEL1 = SystemRegister(op0: 3, op1: 0, crn: 12, crm: 0, op2: 0)
    public static let tpidrEL0 = SystemRegister(op0: 3, op1: 3, crn: 13, crm: 0, op2: 2)
    public static let tpidrroEL0 = SystemRegister(op0: 3, op1: 3, crn: 13, crm: 0, op2: 3)
    public static let idAA64MMFR0EL1 = SystemRegister(op0: 3, op1: 0, crn: 0, crm: 7, op2: 0)
    public static let cntfrqEL0 = SystemRegister(op0: 3, op1: 3, crn: 14, crm: 0, op2: 0)
    public static let cntkctlEL1 = SystemRegister(op0: 3, op1: 0, crn: 14, crm: 1, op2: 0)
    public static let idAA64MMFR2EL1 = SystemRegister(op0: 3, op1: 0, crn: 0, crm: 7, op2: 2)
}

public final class VCPU: @unchecked Sendable {
    public let fd: Int32
    public let id: Int
    private let runArea: UnsafeMutableRawPointer
    private let runSize: Int
    private var closed = false
    public private(set) var exitCount = 0

    public static let pstateEL1hMasked: UInt64 = 0x3C5

    init(vm: VirtualMachine, id: Int) throws {
        let began = monotonicNanoseconds()
        let fd = try kvmCheck(ckvm_create_vcpu(vm.vmFD, UInt(id)), "KVM_CREATE_VCPU")
        let created = monotonicNanoseconds()
        VCPUPool.deferredCreateVCPUNanoseconds.wrappingAdd(created &- began, ordering: .relaxed)
        if VCPUPool.profiling { VCPUPool.creationPhases[1].add(created &- began) }
        defer {
            let end = monotonicNanoseconds()
            VCPUPool.deferredInitNanoseconds.wrappingAdd(end &- created, ordering: .relaxed)
            if VCPUPool.profiling { VCPUPool.creationPhases[2].add(end &- created) }
        }
        do {
            let size = Int(try kvmCheck(ckvm_get_vcpu_mmap_size(vm.kvmFD), "KVM_GET_VCPU_MMAP_SIZE"))
            try kvmCheck(ckvm_arm_vcpu_init_preferred(vm.vmFD, fd, UInt32(1) << UInt32(CKVM_ARM_VCPU_FEATURE_PSCI_0_2)),
                         "KVM_ARM_VCPU_INIT")
            guard let run = ckvm_map_run(fd, size) else { throw KVMError("mmap kvm_run", errno: Glibc.errno) }
            self.runArea = run
            self.runSize = size
        } catch {
            _ = ckvm_close(fd)
            throw error
        }
        self.fd = fd
        self.id = id
    }

    deinit { close() }

    func reset(vmFD: Int32) -> Bool {
        guard !closed else { return false }
        ckvm_run_set_immediate_exit(runArea, 0)
        guard ckvm_arm_vcpu_init_preferred(vmFD, fd, UInt32(1) << UInt32(CKVM_ARM_VCPU_FEATURE_PSCI_0_2)) == 0 else { return false }
        exitCount = 0
        if VCPUPool.profiling {
            let names = ["exits", "wfe_exit_stat", "wfi_exit_stat"]
            statisticsBaseline = Dictionary(uniqueKeysWithValues: zip(names, rawStatistics(names)))
        }
        return true
    }
    private var statisticsBaseline: [String: UInt64] = [:]

    public func kvmStatistics(_ names: [String]) -> [UInt64] {
        let raw = rawStatistics(names)
        return zip(names, raw).map { $1 &- (statisticsBaseline[$0] ?? 0) }
    }

    private func rawStatistics(_ names: [String]) -> [UInt64] {
        var out = [UInt64](repeating: 0, count: names.count)
        let copies = names.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = copies.map { UnsafePointer($0) }
        _ = ckvm_vcpu_stats(fd, &pointers, Int32(names.count), &out)
        return out
    }

    func close() {
        guard !closed else { return }
        closed = true
        releaseHostMemory(runArea, runSize)
        _ = ckvm_close(fd)
    }

    public func get(_ register: CoreRegister) throws -> UInt64 { try getRaw(register.id, "\(register)") }
    public func set(_ register: CoreRegister, _ value: UInt64) throws { try setRaw(register.id, value, "\(register)") }
    public func get(_ register: SystemRegister) throws -> UInt64 { try getRaw(register.id, "sysreg") }
    public func set(_ register: SystemRegister, _ value: UInt64) throws { try setRaw(register.id, value, "sysreg") }

    public func setVirtualCounter(_ value: UInt64) throws {
        try setRaw(ckvm_reg_timer_cnt(), value, "KVM_REG_ARM_TIMER_CNT")
    }

    private func getRaw(_ id: UInt64, _ name: String) throws -> UInt64 {
        var value: UInt64 = 0
        try kvmCheck(ckvm_get_one_reg_u64(fd, id, &value), "KVM_GET_ONE_REG \(name)")
        return value
    }

    private func setRaw(_ id: UInt64, _ value: UInt64, _ name: String) throws {
        try kvmCheck(ckvm_set_one_reg_u64(fd, id, value), "KVM_SET_ONE_REG \(name)")
    }

    public func virtualCounter() throws -> UInt64 { try getRaw(ckvm_reg_timer_cnt(), "KVM_REG_ARM_TIMER_CNT") }

    public func counterOffset() throws -> UInt64 {
        let before = ckvm_host_cntvct()
        let guest = try virtualCounter()
        let after = ckvm_host_cntvct()
        return (before &+ (after &- before) / 2) &- guest
    }

    public func counterFrequency() -> (hz: UInt64, source: String) {
        if let value = try? getRaw(SystemRegister.cntfrqEL0.id, "CNTFRQ_EL0"), value != 0 {
            return (value, "ONE_REG")
        }
        return (ckvm_host_cntfrq(), "host CNTFRQ_EL0")
    }

    public func run() throws -> VCPUExit {
        while true {
            let result = ckvm_run(fd)
            if result == -EINTR || result == -EAGAIN {
                if ckvm_watchdog_fired() != 0 { return .watchdog }
                continue
            }
            try kvmCheck(result, "KVM_RUN")
            exitCount += 1
            return decodeExit()
        }
    }

    public func runOnce() throws -> VCPUExit {
        while true {
            let result = ckvm_run(fd)
            if result == -EINTR { return .interrupted }
            if result == -EAGAIN { continue }
            try kvmCheck(result, "KVM_RUN")
            exitCount += 1
            return decodeExit()
        }
    }

    public func setImmediateExit(_ on: Bool) { ckvm_run_set_immediate_exit(runArea, on ? 1 : 0) }

    public func completeMMIORead(_ value: UInt64, length: Int) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            ckvm_run_mmio_set_data(runArea, bytes.bindMemory(to: UInt8.self).baseAddress, UInt32(min(length, 8)))
        }
    }

    private func decodeExit() -> VCPUExit {
        let reason = ckvm_run_exit_reason(runArea)
        switch Int(reason) {
        case Int(CKVM_EXIT_MMIO):
            let length = Int(ckvm_run_mmio_len(runArea))
            let word = UInt64(littleEndian: ckvm_run_mmio_data_u64(runArea))
            let data = length >= 8 ? word : word & ((UInt64(1) << (8 * UInt64(max(length, 0)))) - 1)
            let direction: VCPUExit.MMIODirection = ckvm_run_mmio_is_write(runArea) != 0 ? .write : .read
            return .mmio(direction, address: ckvm_run_mmio_phys_addr(runArea), data: direction == .write ? data : 0, length: length)
        case Int(CKVM_EXIT_HLT):
            return .hlt
        case Int(CKVM_EXIT_SHUTDOWN):
            return .shutdown
        case Int(CKVM_EXIT_SYSTEM_EVENT):
            let count = min(Int(ckvm_run_system_event_ndata(runArea)), 16)
            return .systemEvent(type: ckvm_run_system_event_type(runArea),
                                data: (0..<count).map { ckvm_run_system_event_data(runArea, UInt32($0)) })
        case Int(CKVM_EXIT_INTERNAL_ERROR):
            let count = min(Int(ckvm_run_internal_ndata(runArea)), 16)
            return .internalError(suberror: ckvm_run_internal_suberror(runArea),
                                  data: (0..<count).map { ckvm_run_internal_data(runArea, UInt32($0)) })
        case Int(CKVM_EXIT_FAIL_ENTRY):
            return .failEntry(reason: ckvm_run_fail_entry_reason(runArea), cpu: ckvm_run_fail_entry_cpu(runArea))
        case Int(CKVM_EXIT_ARM_NISV):
            return .armNISV(esrISS: ckvm_run_arm_nisv_esr_iss(runArea), faultIPA: ckvm_run_arm_nisv_fault_ipa(runArea))
        case Int(CKVM_EXIT_HYPERCALL):
            return .hypercall(function: ckvm_run_hypercall_nr(runArea), flags: ckvm_run_hypercall_flags(runArea))
        case Int(CKVM_EXIT_INTR):
            return ckvm_watchdog_fired() != 0 ? .watchdog : .other(reason: reason)
        default:
            return .other(reason: reason)
        }
    }
}

public enum Watchdog {
    public static func arm(milliseconds: UInt64) throws {
        try kvmCheck(ckvm_watchdog_arm(milliseconds), "watchdog timer")
    }
    public static var fired: Bool { ckvm_watchdog_fired() != 0 }
}
#endif
