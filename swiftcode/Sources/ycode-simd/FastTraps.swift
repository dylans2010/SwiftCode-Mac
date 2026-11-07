#if os(Linux) && arch(arm64)
import CKVM
import Foundation
import Synchronization
import YcodeDarwinABI
import YcodeDarwinKernel
import YcodeHypervisor

enum FastTraps {
    private static func flag(_ name: String) -> Bool {
        getenv(name).map { String(cString: $0) != "0" } ?? true
    }

    static let hvcDoorbell = flag("SWIFTCODE_HVC_DOORBELL")
    static let enabled = flag("SWIFTCODE_FAST_TRAPS")
    static let localCalls = flag("SWIFTCODE_LOCAL_CALLS")
    static let sysctlCache = flag("SWIFTCODE_SYSCTL_CACHE")

    static func doorbellAddress(for vm: VirtualMachine, log: (String) -> Void) -> UInt64 {
        guard hvcDoorbell else { return VMLayout.doorbellGPA }
        do {
            try vm.installHVCDoorbell()
            if !announcedHVC.exchange(true, ordering: .relaxed) {
                stderrLine("swiftcode-simd: HVC doorbell on (SMCCC function 0xC6005943 forwarded to user space)")
            }
            return 0
        } catch {
            warnOnce("HVC doorbell unavailable, using the MMIO doorbell: \(error)", log: log)
            return VMLayout.doorbellGPA
        }
    }

    static func configureCommpage(space: GuestAddressSpace, vm: VirtualMachine, directClock: Bool,
                                  counter: @escaping () -> UInt64, frequency: UInt64,
                                  clockScale: GuestTimebase.ClockScale,
                                  wallClock: () -> (seconds: Int64, nanoseconds: Int64))
        throws -> ((UInt64, Int64, Int64) -> Void)? {
        guard enabled else { return nil }
        guard let pa = space.pageTables.translate(VMLayout.commpageVA)?.pa else { return nil }
        let page = try vm.hostPointer(gpa: pa, count: Int(VMLayout.pageSize))
        var flags = CommpageBuilder.FastFlag.credentialBlock
        if localCalls { flags |= CommpageBuilder.FastFlag.localCalls }
        if sysctlCache { flags |= CommpageBuilder.FastFlag.sysctlCache }
        let creds = page + CommpageBuilder.Offset.credentials
        for (i, v) in [DarwinFileSystem.guestUID, DarwinFileSystem.guestUID,
                       DarwinFileSystem.guestGID, DarwinFileSystem.guestGID].enumerated() {
            creds.storeBytes(of: v.littleEndian, toByteOffset: 4 * i, as: UInt32.self)
        }
        var publisher: ((UInt64, Int64, Int64) -> Void)?
        if directClock {
            page.storeBytes(of: clockScale.multiplier.littleEndian, toByteOffset: CommpageBuilder.Offset.clockMultiplier,
                            as: UInt64.self)
            page.storeBytes(of: clockScale.shift.littleEndian, toByteOffset: CommpageBuilder.Offset.clockShift, as: UInt64.self)
            flags |= CommpageBuilder.FastFlag.directClock
            let block = page + CommpageBuilder.Offset.newTimeOfDay
            let publish: (UInt64, Int64, Int64) -> Void = { tick, seconds, nanoseconds in
                let t = CommpageBuilder.TimeOfDaySnapshot(tick: tick, seconds: seconds, nanoseconds: nanoseconds,
                                                          frequency: frequency)
                ckvm_publish_timeofday(block, t.tick, t.seconds, t.fraction, t.scale, t.ticksPerSecond)
            }
            let tick = counter()
            let (s, ns) = wallClock()
            publish(tick, s, ns)
            publisher = publish
        }
        page.storeBytes(of: flags, toByteOffset: CommpageBuilder.Offset.fastFlags, as: UInt8.self)
        return publisher
    }

    private static let announcedHVC = Atomic<Bool>(false)
    private static let warned = Atomic<Bool>(false)
    private static func warnOnce(_ text: String, log: (String) -> Void) {
        if !warned.exchange(true, ordering: .relaxed) { stderrLine("swiftcode-simd: \(text)") } else { log(text) }
    }
}
#endif
