#if os(Linux) && arch(arm64)
import Foundation
import Testing
import SwiftCodeDebug
@testable import swiftcode_simd

@Suite struct DebugStubTests {
    func control(lsc: UInt64, bas: UInt64, mask: UInt64 = 0) -> UInt64 { 1 | (0b10 << 1) | (lsc << 3) | (bas << 5) | (mask << 24) }

    @Test func byteSelectWithinADoubleword() throws {
        let w = try #require(SimDebugProcess.registers(address: 0x1004, size: 4, kind: .write))
        #expect(w.value == 0x1000)
        #expect(w.control == control(lsc: 0b10, bas: 0xF0))
        let r = try #require(SimDebugProcess.registers(address: 0x2000, size: 8, kind: .read))
        #expect(r.value == 0x2000 && r.control == control(lsc: 0b01, bas: 0xFF))
        let a = try #require(SimDebugProcess.registers(address: 0x3003, size: 1, kind: .access))
        #expect(a.value == 0x3000 && a.control == control(lsc: 0b11, bas: 0x08))
    }

    @Test func maskForAnAlignedPowerOfTwo() throws {
        let w = try #require(SimDebugProcess.registers(address: 0x4000, size: 64, kind: .write))
        #expect(w.value == 0x4000)
        #expect(w.control == control(lsc: 0b10, bas: 0xFF, mask: 6))
    }

    @Test func refusesWhatTheRegistersCannotHold() {
        #expect(SimDebugProcess.registers(address: 0x1006, size: 4, kind: .write) == nil)
        #expect(SimDebugProcess.registers(address: 0x1008, size: 24, kind: .write) == nil)
        #expect(SimDebugProcess.registers(address: 0x1008, size: 16, kind: .write) == nil)
    }

    @Test func readsTheRuntimeVersion() throws {
        let root = NSTemporaryDirectory() + "swiftcode-debug-rr-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let dir = root + "/System/Library/CoreServices"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["ProductVersion": "27.0", "ProductBuildVersion": "24A434", "ProductName": "iPhone OS"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: dir + "/SystemVersion.plist"))
        let v = SimDebugServer.runtimeVersion(root: root)
        #expect(v.0 == "27.0" && v.1 == "24A434")
        let missing = SimDebugServer.runtimeVersion(root: root + "/missing")
        #expect(missing.0.isEmpty && missing.1.isEmpty)
    }
}
#endif
