#if os(Linux) && arch(arm64)
import Glibc

enum A64 {
    static func movz(_ rd: UInt32, _ imm: UInt16, shift: UInt32 = 0) -> UInt32 { 0xD280_0000 | (shift / 16) << 21 | UInt32(imm) << 5 | rd }
    static func movk(_ rd: UInt32, _ imm: UInt16, shift: UInt32) -> UInt32 { 0xF280_0000 | (shift / 16) << 21 | UInt32(imm) << 5 | rd }
    static func mov64(_ rd: UInt32, _ value: UInt64) -> [UInt32] {
        var words = [movz(rd, UInt16(value & 0xFFFF))]
        for shift in stride(from: UInt32(16), to: 64, by: 16) where (value >> UInt64(shift)) & 0xFFFF != 0 {
            words.append(movk(rd, UInt16((value >> UInt64(shift)) & 0xFFFF), shift: shift))
        }
        return words
    }
    static func ldr(_ rt: UInt32, _ rn: UInt32, _ offset: UInt32 = 0) -> UInt32 { 0xF940_0000 | (offset / 8) << 10 | rn << 5 | rt }
    static func str(_ rt: UInt32, _ rn: UInt32, _ offset: UInt32 = 0) -> UInt32 { 0xF900_0000 | (offset / 8) << 10 | rn << 5 | rt }
    static let hvc0: UInt32 = 0xD400_0002
    static let branchSelf: UInt32 = 0x1400_0000

    static func bytes(_ words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        for word in words { withUnsafeBytes(of: word.littleEndian) { out.append(contentsOf: $0) } }
        return out
    }
}

public enum KVMSmokeTest {
    public static func run(log: (String) -> Void) throws {
        let vm = try VirtualMachine()
        let vcpu = try vm.makeVCPU()
        let mmfr0 = try vcpu.get(.idAA64MMFR0EL1)
        log("vCPU created; ID_AA64MMFR0_EL1 = 0x\(String(mmfr0, radix: 16)) (TGran16 field \((mmfr0 >> 20) & 0xF))")

        let program: [UInt32] = [
            0xD2A1_2001,
            0xD282_4682,
            0xF900_0022,
            0xF940_0423,
            0xF900_0823,
            0xD280_0100,
            0xF2B0_8000,
            0xD400_0002,
            0x1400_0000,
        ]
        var bytes: [UInt8] = []
        for word in program { withUnsafeBytes(of: word.littleEndian) { bytes.append(contentsOf: $0) } }
        try vm.write(gpa: vm.ramGPA, bytes: bytes)

        try vcpu.set(.pc, vm.ramGPA)
        try vcpu.set(.pstate, VCPU.pstateEL1hMasked)
        try vcpu.set(.x(5), 0xFEED_FACE)
        guard try vcpu.get(.x(5)) == 0xFEED_FACE else { throw KVMError("smoke", detail: "ONE_REG round trip of x5") }
        try vcpu.set(.tpidrroEL0, 0x1234_5678_9ABC)
        guard try vcpu.get(.tpidrroEL0) == 0x1234_5678_9ABC else { throw KVMError("smoke", detail: "ONE_REG round trip of TPIDRRO_EL0") }
        log("registers set: PC=0x\(String(vm.ramGPA, radix: 16)) PSTATE=0x3c5")

        try Watchdog.arm(milliseconds: 5_000)
        defer { try? Watchdog.arm(milliseconds: 0) }

        var exit = try vcpu.run()
        log("exit 1: \(exit)")
        guard exit == .mmio(.write, address: 0x0900_0000, data: 0x1234, length: 8) else {
            throw KVMError("smoke", detail: "expected an 8-byte MMIO write of 0x1234, got \(exit)")
        }
        exit = try vcpu.run()
        log("exit 2: \(exit)")
        guard exit == .mmio(.read, address: 0x0900_0008, data: 0, length: 8) else {
            throw KVMError("smoke", detail: "expected an 8-byte MMIO read, got \(exit)")
        }
        vcpu.completeMMIORead(0xC0FF_EE00_1122_3344, length: 8)
        exit = try vcpu.run()
        log("exit 3: \(exit)")
        guard exit == .mmio(.write, address: 0x0900_0010, data: 0xC0FF_EE00_1122_3344, length: 8) else {
            throw KVMError("smoke", detail: "expected the read value written back, got \(exit)")
        }
        let x2 = try vcpu.get(.x(2)), x3 = try vcpu.get(.x(3)), pc = try vcpu.get(.pc)
        log("registers: x2=0x\(String(x2, radix: 16)) x3=0x\(String(x3, radix: 16)) pc=0x\(String(pc, radix: 16))")
        guard x2 == 0x1234, x3 == 0xC0FF_EE00_1122_3344, pc == vm.ramGPA + 16 else {
            throw KVMError("smoke", detail: "register values after the MMIO exits")
        }
        exit = try vcpu.run()
        log("exit 4: \(exit)")
        guard case .systemEvent = exit else { throw KVMError("smoke", detail: "expected PSCI SYSTEM_OFF, got \(exit)") }

        let exits = vcpu.exitCount

        let spinVM = try VirtualMachine(ramSize: 1 << 20)
        let spinner = try spinVM.makeVCPU()
        try spinVM.write(gpa: spinVM.ramGPA, bytes: [0x00, 0x00, 0x00, 0x14])
        try spinner.set(.pc, spinVM.ramGPA)
        try spinner.set(.pstate, VCPU.pstateEL1hMasked)
        try Watchdog.arm(milliseconds: 200)
        exit = try spinner.run()
        log("spin test: \(exit)")
        guard exit == .watchdog else { throw KVMError("smoke", detail: "watchdog did not interrupt a spinning guest") }
        log("KVM smoke test passed (\(exits) exits)")
        try runMemslots(log: log)
        try runVCPUBatch(log: log)
    }

    public static func runVCPUBatch(log: (String) -> Void) throws {
        let batch = VirtualMachine.creationBatch
        let vm = try VirtualMachine(ramSize: 1 << 20)
        vm.vcpuIDLimit = 1 + batch + 1
        _ = try vm.makeVCPU(id: 0)
        for id in 1...max(1, batch) where batch > 0 {
            let began = monotonicNanoseconds()
            let vcpu = try vm.makeVCPU(id: id)
            let micros = (monotonicNanoseconds() &- began) / 1000
            guard vcpu.id == id, micros < 2000 else {
                throw KVMError("smoke", detail: "batched vCPU \(id): id \(vcpu.id), \(micros) us (a spare should be immediate)")
            }
        }
        let last = try vm.makeVCPU(id: batch + 1)
        guard last.id == batch + 1, vm.vcpus.count == batch + 2 else {
            throw KVMError("smoke", detail: "vCPU batch: \(vm.vcpus.count) vCPUs, expected \(batch + 2)")
        }
        vm.vcpuIDLimit = Int.max
        let next = try vm.makeVCPU()
        guard next.id == batch + 2 else { throw KVMError("smoke", detail: "vCPU batch: default id \(next.id)") }
        vm.close()
        log("vCPU batch test passed (batch \(batch))")
    }

    public static func runMemslots(log: (String) -> Void) throws {
        let vm = try VirtualMachine(ramSize: 1 << 20)
        log("memslots: KVM_CAP_NR_MEMSLOTS = \(vm.maxMemorySlots)")
        let backing = try KVMPhysicalBacking(vm: vm)

        let fileSize = 40_000
        var content = [UInt8](repeating: 0, count: fileSize)
        for i in 0..<(fileSize / 8) {
            withUnsafeBytes(of: (0x5943_0000_0000_0000 | UInt64(i)).littleEndian) { content.replaceSubrange(i * 8..<i * 8 + 8, with: $0) }
        }
        let tmpdir = getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp"
        var template = Array("\(tmpdir)/swiftcode-memslot-XXXXXX".utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { throw KVMError("mkstemp", errno: Glibc.errno) }
        let path = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        defer { close(fd); unlink(path) }
        guard content.withUnsafeBytes({ Glibc.write(fd, $0.baseAddress!, $0.count) }) == fileSize else {
            throw KVMError("write temp file", errno: Glibc.errno)
        }

        let fileA = try backing.mapFile(hostFD: fd, fileSize: UInt64(fileSize), offset: 0, size: UInt64(fileSize), name: "memslot-test")
        let fileB = try backing.mapFile(hostFD: fd, fileSize: UInt64(fileSize), offset: 16384, size: 32768, name: "memslot-test")
        let anon1 = try backing.allocateAnonymous(size: 16384)
        let anon2 = try backing.allocateAnonymous(size: 3 * 16384)
        try backing.writePhysical(gpa: anon1, bytes: A64.bytes([0xAAAA_5555, 0x1234_5678]))
        backing.release(gpa: anon1, size: 16384)
        let anon3 = try backing.allocateAnonymous(size: 16384)
        guard anon3 == anon1 else { throw KVMError("smoke", detail: "pool did not reuse the released run") }
        try backing.writePhysical(gpa: anon2 + 16384, bytes: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        log("memslots: file A at 0x\(String(fileA, radix: 16)), file B at 0x\(String(fileB, radix: 16)), pool runs 0x\(String(anon3, radix: 16)) and 0x\(String(anon2, radix: 16)); \(vm.memorySlotCount) slots")

        let doorbell: UInt64 = 0x0900_0000
        var program: [UInt32] = A64.mov64(1, doorbell)
        func report(_ base: UInt64, _ offset: UInt32) {
            program += A64.mov64(4, base)
            program += [A64.ldr(2, 4, offset), A64.str(2, 1)]
        }
        report(fileA, 0)
        program += A64.mov64(4, fileA + 39_992)
        program += [A64.ldr(2, 4), A64.str(2, 1)]
        program += A64.mov64(4, fileA + 40_000)
        program += [A64.ldr(2, 4), A64.str(2, 1)]
        program += A64.mov64(4, fileA + 40_960)
        program += [A64.ldr(2, 4), A64.str(2, 1)]
        report(fileB, 0)
        report(fileB, 24_576)
        program += A64.mov64(4, fileA)
        program += A64.mov64(3, 0xC000_0000_0000_BEEF)
        program += [A64.str(3, 4), A64.ldr(2, 4), A64.str(2, 1)]
        report(anon3, 0)
        report(anon2, 16384)
        program += A64.mov64(0, 0x8400_0008) + [A64.hvc0, A64.branchSelf]
        try vm.write(gpa: vm.ramGPA, bytes: A64.bytes(program))

        let expected: [(String, UInt64)] = [
            ("file word 0", 0x5943_0000_0000_0000),
            ("last file word", 0x5943_0000_0000_0000 | 4999),
            ("past EOF, same host page as EOF", 0),
            ("past EOF, next host page", 0),
            ("file B word 0 (file word 2048)", 0x5943_0000_0000_0000 | 2048),
            ("file B past EOF", 0),
            ("copy-on-write store", 0xC000_0000_0000_BEEF),
            ("reused pool page", 0),
            ("pool page written by the VMM", 0x8877_6655_4433_2211),
        ]
        let vcpu = try vm.makeVCPU()
        try vcpu.set(.pc, vm.ramGPA)
        try vcpu.set(.pstate, VCPU.pstateEL1hMasked)
        try Watchdog.arm(milliseconds: 5_000)
        defer { try? Watchdog.arm(milliseconds: 0) }
        for (name, value) in expected {
            let exit = try vcpu.run()
            guard case let .mmio(.write, address, data, 8) = exit, address == doorbell else {
                throw KVMError("smoke", detail: "\(name): expected an MMIO report, got \(exit)")
            }
            guard data == value else {
                throw KVMError("smoke", detail: "\(name): guest read 0x\(String(data, radix: 16)), expected 0x\(String(value, radix: 16))")
            }
            log("memslots: \(name) = 0x\(String(data, radix: 16)) ok")
        }
        let last = try vcpu.run()
        guard case .systemEvent = last else { throw KVMError("smoke", detail: "expected PSCI SYSTEM_OFF, got \(last)") }

        var check = [UInt8](repeating: 0, count: 8)
        guard pread(fd, &check, 8, 0) == 8, check == Array(content[0..<8]) else {
            throw KVMError("smoke", detail: "the guest's store reached the host file")
        }
        let privateWord = try backing.readPhysical(gpa: fileA, count: 8)
        guard privateWord == A64.bytes([0x0000_BEEF, 0xC000_0000]) else {
            throw KVMError("smoke", detail: "VMM read of the copied page: \(privateWord)")
        }
        log("memslots: host file unchanged; VMM sees the private copy")

        let (hz, source) = vcpu.counterFrequency()
        let c1 = try vcpu.virtualCounter()
        usleep(10_000)
        let c2 = try vcpu.virtualCounter()
        log("timer: CNTFRQ = \(hz) Hz (\(source)); virtual counter \(c1) -> \(c2) over 10 ms (\(c2 &- c1) ticks)")
        guard hz > 0, c2 > c1 else { throw KVMError("smoke", detail: "timer registers") }
        log("memslot smoke test passed")
    }
}
#endif
