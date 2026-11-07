import Foundation
import Synchronization
import YcodeDarwinABI

extension DarwinKernel {
    nonisolated(unsafe) public static var taskLocalTrapsEnabled = getenv("SWIFTCODE_TASK_LOCAL_TRAPS").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var taskLocalMadviseEnabled = getenv("SWIFTCODE_TASK_LOCAL_MADVISE").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var taskLocalMoreEnabled = getenv("SWIFTCODE_TASK_LOCAL_MORE").map { String(cString: $0) != "0" } ?? true

    @inline(__always) static func isLoaderHelper(pc: UInt64) -> Bool {
        pc >= VMLayout.hostPageVA && pc < VMLayout.hostPageVA + VMLayout.hostPageCodeSize
    }

    public static func isTaskLocalTrap(_ number: Int32) -> Bool {
        switch number {
        case 338, 340, -10, -12, -14, -11: return true
        case 75: return taskLocalMadviseEnabled
        case 73, 74, -3, -4, -15, -43, Int32(bitPattern: Private.vmCopy): return taskLocalMoreEnabled
        default: return false
        }
    }

    public func handleTaskLocal(_ frame: inout TrapFrame, context: ThreadContext, memory: any KernelGuestMemory) -> Outcome? {
        guard Self.taskLocalTrapsEnabled, !tracing, frame.trapKind == .svc, frame.x.count >= TrapFrame.registerCount,
              context.kernel === self, !isTerminating else { return nil }
        let number = Int32(truncatingIfNeeded: frame.x[16])
        let a = frame.x.prefixArray(8)
        let generation = memory.tlbGeneration
        defer { if memory.tlbGeneration != generation { frame.requestTLBInvalidation(memory.tlbRange(since: generation)) } }
        switch number {
        case 338, 340:
            do {
                let path = try readPath(a[0], memory)
                let st = try fileSystem.stat(path, followSymlinks: number == 338,
                                             cacheImages: !Self.isLoaderHelper(pc: frame.elr))
                try memory.write(va: a[1], bytes: st.encodedStat64())
                frame.x[0] = 0
                frame.x[1] = 0
                frame.carry = false
            } catch {
                frame.x[0] = UInt64(UInt32(bitPattern: errno(of: error, default: Errno.EINVAL)))
                frame.x[1] = 0
                frame.carry = true
            }
            return .resume

        case -10:
            guard a[3] & Self.vmFlagsAnywhere != 0 else { return nil }
            frame.x[0] = vmAllocateAnywhere(a, memory)
            return .resume

        case -12:
            if a[2] != 0 {
                let start = a[1] & ~Self.pageMask
                let size = roundUp(a[2] + (a[1] - start), to: Self.pageSize)
                do { try memory.unmap(va: start, size: size) } catch {
                    frame.x[0] = KernReturn.invalidArgument
                    return .resume
                }
            }
            frame.x[0] = KernReturn.success
            return .resume

        case -14:
            guard a[3] & 0xFFFF_FFFF == 0 else { return nil }
            if a[2] != 0 {
                let start = a[1] & ~Self.pageMask
                let size = roundUp(a[2] + (a[1] - start), to: Self.pageSize)
                let bits = a[4] & ~Self.vmProtCopy & 7
                do {
                    try memory.protect(va: start, size: size,
                                       protection: VMProtection(rawValue: VMProtection.RawValue(truncatingIfNeeded: bits)))
                } catch {
                    frame.x[0] = KernReturn.invalidAddress
                    return .resume
                }
            }
            frame.x[0] = KernReturn.success
            return .resume

        case Int32(bitPattern: Private.vmCopy):
            guard a[2] <= UInt64(Int32.max) else {
                frame.x[0] = KernReturn.invalidArgument
                frame.carry = false
                return .resume
            }
            if let bytes = try? memory.read(va: a[1], count: Int(a[2])), (try? memory.write(va: a[3], bytes: bytes)) != nil {
                frame.x[0] = KernReturn.success
            } else {
                frame.x[0] = KernReturn.invalidAddress
            }
            frame.carry = false
            return .resume

        case -15:
            frame.x[0] = vmMapAnonymous(a, memory).0
            return .resume

        case -43:
            frame.x[0] = generateActivityID(a, memory) != nil ? KernReturn.success : KernReturn.invalidAddress
            return .resume

        case -3, -4:
            frame.x[0] = counter()
            return .resume

        case 73, 74:
            var failure: Int32 = 0
            do {
                if number == 73 {
                    if a[0] & Self.pageMask != 0 || a[1] == 0 { throw Failure(errno: Errno.EINVAL) }
                    try memory.unmap(va: a[0], size: roundUp(a[1], to: Self.pageSize))
                } else {
                    let start = a[0] & ~Self.pageMask
                    let size = roundUp(a[1] + (a[0] - start), to: Self.pageSize)
                    if size > 0 {
                        try memory.protect(va: start, size: size,
                                           protection: VMProtection(rawValue: VMProtection.RawValue(truncatingIfNeeded: a[2] & 7)))
                    }
                }
            } catch {
                failure = errno(of: error, default: Errno.EINVAL)
            }
            frame.x[0] = failure == 0 ? 0 : UInt64(UInt32(bitPattern: failure))
            frame.x[1] = 0
            frame.carry = failure != 0
            return .resume

        case -11:
            frame.x[0] = purgeableControl(a, memory)
            return .resume

        case 75:
            guard Self.taskLocalMadviseEnabled else { return nil }
            let advice = Int32(truncatingIfNeeded: a[2])
            var failure: Int32 = 0
            if !(0...11).contains(advice) {
                failure = Errno.EINVAL
            } else if advice == 11, a[1] > 0 {
                let end = a[0].addingReportingOverflow(a[1])
                if end.overflow {
                    failure = Errno.EINVAL
                } else {
                    let zeros = [UInt8](repeating: 0, count: Int(min(a[1], 1 << 20)))
                    var at = a[0]
                    while at < end.partialValue {
                        let n = Int(min(UInt64(zeros.count), end.partialValue - at))
                        do { try memory.write(va: at, bytes: n == zeros.count ? zeros : Array(zeros[0..<n])) } catch {
                            failure = Errno.ENOMEM
                            break
                        }
                        at += UInt64(n)
                    }
                }
            }
            frame.x[0] = failure == 0 ? 0 : UInt64(UInt32(bitPattern: failure))
            frame.x[1] = 0
            frame.carry = failure != 0
            return .resume

        default:
            return nil
        }
    }

    func purgeableControl(_ a: [UInt64], _ mem: any KernelGuestMemory) -> UInt64 {
        let control = Int32(truncatingIfNeeded: a[2])
        let page = a[1] & ~Self.pageMask
        switch control {
        case 0, 1:
            guard let raw = try? mem.read(va: a[3], count: 4) else { return KernReturn.invalidAddress }
            let state = raw.readLE(Int32.self, at: 0) & 0x3
            if control == 0, state == 2 { return KernReturn.invalidArgument }
            let old: Int32 = purgeableStore.withLock { table in
                let old = table[page] ?? 0
                if control == 0 { table[page] = state == 0 ? nil : state }
                return old
            }
            var out: [UInt8] = []
            out.appendLE(old)
            guard (try? mem.write(va: a[3], bytes: out)) != nil else { return KernReturn.invalidAddress }
            return KernReturn.success
        case 2:
            return KernReturn.success
        default:
            return KernReturn.invalidArgument
        }
    }

    func vmAllocateAnywhere(_ a: [UInt64], _ mem: any KernelGuestMemory) -> UInt64 {
        guard let requested = try? readU64(a[1], mem) else { return KernReturn.invalidAddress }
        if a[2] == 0 {
            guard (try? writeU64(a[1], 0, mem)) != nil else { return KernReturn.invalidAddress }
            return KernReturn.success
        }
        let size = roundUp(a[2], to: Self.pageSize)
        guard let va = try? mem.mapAnonymous(at: nil, size: size, protection: [.read, .write],
                                             hint: requested == 0 ? nil : requested & ~Self.pageMask) else {
            return KernReturn.noSpace
        }
        guard (try? writeU64(a[1], va, mem)) != nil else { return KernReturn.invalidAddress }
        return KernReturn.success
    }
}
