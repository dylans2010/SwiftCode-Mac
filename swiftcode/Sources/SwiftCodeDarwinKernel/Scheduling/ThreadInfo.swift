import Foundation
import SwiftCodeDarwinABI

extension DarwinKernel {
    static let threadInfoBasic: UInt32 = 3
    static let threadInfoIdentifier: UInt32 = 4
    static let threadInfoExtended: UInt32 = 5
    static let threadInfoSchedTimeshare: UInt32 = 10

    static func threadInfoWords(_ thread: ThreadContext, flavor: UInt32, selfCPUNanoseconds: UInt64?) -> [UInt8]? {
        let cpu = selfCPUNanoseconds ?? 0
        let runState: Int32 = thread.gate.isClosed ? 2 : thread.blockedInKernel ? 3 : 1
        var out: [UInt8] = []
        switch flavor {
        case threadInfoBasic:
            out.appendLE(Int32(truncatingIfNeeded: cpu / 1_000_000_000))
            out.appendLE(Int32(truncatingIfNeeded: (cpu % 1_000_000_000) / 1000))
            out.appendLE(Int32(0)); out.appendLE(Int32(0))
            out.appendLE(Int32(0))
            out.appendLE(Int32(1))
            out.appendLE(runState)
            out.appendLE(Int32(0))
            out.appendLE(Int32(truncatingIfNeeded: thread.suspendCount))
            out.appendLE(Int32(0))
        case threadInfoIdentifier:
            out.appendLE(thread.threadID)
            out.appendLE(thread.pthreadAddress)
            out.appendLE(thread.pthreadAddress == 0 ? UInt64(0) : thread.pthreadAddress + 224 + 20 * 8)
        case threadInfoExtended:
            out.appendLE(cpu)
            out.appendLE(UInt64(0))
            out.appendLE(Int32(0))
            out.appendLE(Int32(1))
            out.appendLE(runState)
            out.appendLE(Int32(0))
            out.appendLE(Int32(0))
            out.appendLE(Int32(31)); out.appendLE(Int32(31)); out.appendLE(Int32(63))
            out += [UInt8](repeating: 0, count: 64)
        case threadInfoSchedTimeshare:
            for v: Int32 in [63, 31, 31, 0, 0] { out.appendLE(v) }
        default:
            return nil
        }
        return out
    }

    func threadInfo(_ a: [UInt64], ipc: MachIPC, memory: any GuestVirtualMemory, caller: ThreadContext) -> (UInt32, String) {
        let name = UInt32(truncatingIfNeeded: a[0]), flavor = UInt32(truncatingIfNeeded: a[1])
        guard let (port, object) = ipc.kernelObject(named: name), case .thread = object,
              let thread = threadsByPort.values.first(where: { ipc.kernelObject(named: $0.portName)?.0 === port }),
              thread.isAlive else {
            return (MachKern.invalidArgument, " [not a thread of this task]")
        }
        let selfCPU: UInt64? = thread === caller
            ? { let now = Self.hostThreadCPUNanoseconds(); return now >= caller.hostCPUBaseNanoseconds ? now - caller.hostCPUBaseNanoseconds : now }()
            : nil
        guard let words = Self.threadInfoWords(thread, flavor: flavor, selfCPUNanoseconds: selfCPU) else {
            return (MachKern.invalidArgument, " [flavor \(flavor)]")
        }
        guard let capacityBytes = try? memory.read(va: a[3], count: 4) else { return (MachKern.invalidAddress, "") }
        let needed = UInt32(words.count / 4)
        guard capacityBytes.readLE(UInt32.self, at: 0) >= needed else { return (UInt32(bitPattern: -307), " [count]") }
        guard (try? memory.write(va: a[2], bytes: words)) != nil,
              (try? memory.write(va: a[3], bytes: le32(needed))) != nil else { return (MachKern.invalidAddress, "") }
        return (MachKern.success, " [thread \(thread.threadID) flavor \(flavor)]")
    }
}
