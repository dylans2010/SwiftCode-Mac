#if os(Linux) && arch(arm64)
import CKVM
import Foundation
import Glibc
import SwiftCodeDarwinKernel

enum CPUFeatureSetup {
    static func install() {
        let mode = GuestCPUProfile.Mode.fromEnvironment()
        let wanted = IDRegister.vcpuRead
        var ids = wanted.map { r -> UInt64 in
            let e = r.encoding
            return ckvm_reg_sysreg(e.op0, e.op1, e.crn, e.crm, e.op2)
        }
        var values = [UInt64](repeating: 0, count: ids.count)
        var results = [Int32](repeating: 0, count: ids.count)
        let rc = ckvm_probe_vcpu_registers(&ids, &values, &results, Int32(ids.count))
        let caches = CacheGeometry.read(cpuDirectory: "/sys/devices/system/cpu/cpu0")
        let hostHz = ckvm_host_cntfrq()
        guard rc == 0 else {
            var p = GuestCPUProfile.minimal
            p.caches = caches
            p.timebaseFrequency = GuestTimebase.frequency(hostFrequency: hostHz)
            GuestCPUProfile.install(p)
            stderrLine("swiftcode-simd: cannot read the guest ID registers (errno \(-rc)); no optional CPU features published")
            return
        }
        var registers = GuestIDRegisters()
        var failed: [String] = []
        for (i, r) in wanted.enumerated() {
            if results[i] == 0 { registers[r] = values[i] } else { failed.append("\(r.rawValue) (errno \(-results[i]))") }
        }
        registers[.ctr] = ckvm_host_ctr_el0()
        registers[.dczid] = ckvm_host_dczid_el0()
        let fpcr = ckvm_host_fpcr_trap_probe()
        let profile = GuestCPUProfile.make(registers: registers, fpcrTrapBits: fpcr, mode: mode, caches: caches,
                                           hostCounterFrequency: hostHz)
        GuestCPUProfile.install(profile)
        var line = "swiftcode-simd: " + profile.summary + "; FPCR trap bits 0x" + String(fpcr, radix: 16)
        if !failed.isEmpty { line += "; unreadable: " + failed.joined(separator: ", ") }
        stderrLine(line)
    }
}
#endif
