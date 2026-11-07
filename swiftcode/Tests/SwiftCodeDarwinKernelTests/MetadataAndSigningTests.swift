import Foundation
import Testing
import SwiftCodeDarwinABI
@testable import SwiftCodeDarwinKernel

@Suite struct MetadataAndSigningTests {
    typealias At = ProcEnv.At

    func put(_ env: ProcEnv, _ k: DarwinKernel, _ s: String, _ va: UInt64) -> UInt64 { env.putString(k, s, at: va); return va }

    @Test func renamesModesOwnersTimes() throws {
        let env = try ProcEnv()
        let k = env.rootKernel!
        let a = env.root + "/a", b = env.root + "/b", c = env.root + "/c"
        try Data("one".utf8).write(to: URL(fileURLWithPath: a))
        try Data("two".utf8).write(to: URL(fileURLWithPath: c))
        let pa = put(env, k, a, At.out + 0x100), pb = put(env, k, b, At.out + 0x300), pc = put(env, k, c, At.out + 0x500)
        #expect(env.bsd(k, 128, [pa, pb]) == 0)
        #expect(!FileManager.default.fileExists(atPath: a))
        #expect(env.bsd(k, 128, [pa, pb]) == -2)
        #expect(env.bsd(k, 488, [UInt64(bitPattern: -2), pb, UInt64(bitPattern: -2), pc, 4]) == -17)
        #expect(env.bsd(k, 488, [UInt64(bitPattern: -2), pb, UInt64(bitPattern: -2), pc, 2]) == 0)
        #expect(try String(contentsOfFile: b, encoding: .utf8) == "two" && String(contentsOfFile: c, encoding: .utf8) == "one")
        #expect(env.bsd(k, 15, [pb, 0o600]) == 0)
        #expect(try (FileManager.default.attributesOfItem(atPath: b)[.posixPermissions] as! Int) == 0o600)
        #expect(env.bsd(k, 16, [pb, UInt64(UInt32.max), 20]) == 0)
        #expect(env.bsd(k, 16, [pb, 0, UInt64(UInt32.max)]) == -1)
        let fd = env.bsd(k, 5, [pb, 2, 0])
        #expect(env.bsd(k, 123, [UInt64(fd), 501, 20]) == 0)
        #expect(env.bsd(k, 124, [UInt64(fd), 0o644]) == 0)
        var tv = [UInt8](repeating: 0, count: 32)
        tv.putLE(Int64(1_000_000), at: 0)
        tv.putLE(Int64(2_000_000), at: 16)
        env.put(k, tv, at: At.out + 0x700)
        #expect(env.bsd(k, 138, [pb, At.out + 0x700]) == 0)
        let mtime = try FileManager.default.attributesOfItem(atPath: b)[.modificationDate] as! Date
        #expect(Int(mtime.timeIntervalSince1970) == 2_000_000)
        #expect(env.bsd(k, 139, [UInt64(fd), 0]) == 0)
        env.put(k, [UInt8](repeating: 0xFF, count: 8), at: At.out + 0xA00)
        #expect(env.bsd(k, 343, [UInt64(fd), At.out + 0xB00, 0, At.out + 0xA00]) == 0)
        #expect(env.read(k, At.out + 0xA00, 8) == [UInt8](repeating: 0, count: 8))
        #expect(env.bsd(k, 200, [pb, 1]) == 0)
        #expect(try String(contentsOfFile: b, encoding: .utf8) == "t")
        #expect(env.bsd(k, 34, [pb, 0x8000]) == 0)
        #expect(env.bsd(k, 381, [put(env, k, "Sandbox", At.out + 0x900), 4, 0]) == -103)
        #expect(env.bsd(k, 381, [put(env, k, "Sandbox", At.out + 0x900), 2, 0]) == 0)
        #expect(env.bsd(k, 381, [put(env, k, "AMFI", At.out + 0x900), 2, 0]) == -103)
        #expect(env.bsd(k, 517, [UInt64(fd), UInt64(bitPattern: -2), pa, 0]) == 0)
        #expect(try String(contentsOfFile: a, encoding: .utf8) == "t")
    }

    @Test func renameNoFollowAnyAndSeclude() throws {
        let env = try ProcEnv()
        let k = env.rootKernel!
        let cwd = UInt64(bitPattern: -2)
        let dir = env.root + "/real", link = env.root + "/link"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: dir)
        try Data("s".utf8).write(to: URL(fileURLWithPath: dir + "/state.tmp"))
        let tmp = put(env, k, dir + "/state.tmp", At.out + 0x100), state = put(env, k, dir + "/state", At.out + 0x300)
        #expect(env.bsd(k, 488, [cwd, tmp, cwd, state, 0x10]) == 0)
        #expect(FileManager.default.fileExists(atPath: dir + "/state"))
        let viaLink = put(env, k, link + "/state", At.out + 0x500), back = put(env, k, dir + "/again", At.out + 0x700)
        #expect(env.bsd(k, 488, [cwd, viaLink, cwd, back, 0x10]) == -62)
        #expect(env.bsd(k, 488, [cwd, state, cwd, viaLink, 0x10]) == -62)
        #expect(env.bsd(k, 488, [cwd, viaLink, cwd, back, 0x1]) == 0)
        #expect(FileManager.default.fileExists(atPath: dir + "/again"))
        #expect(env.bsd(k, 488, [cwd, back, cwd, state, 0x8]) == -22)
        #expect(env.bsd(k, 488, [cwd, back, cwd, state, 0x6]) == -22)
    }

    @Test func extendedAttributesRoundTrip() throws {
        let env = try ProcEnv()
        let k = env.rootKernel!
        let file = env.root + "/db"
        try Data("x".utf8).write(to: URL(fileURLWithPath: file))
        let path = put(env, k, file, At.out + 0x100), name = put(env, k, "com.apple.db.uuid", At.out + 0x300)
        env.put(k, Array("0123456789abcdef".utf8), at: At.out + 0x400)
        #expect(env.bsd(k, 234, [path, name, 0, 0, 0, 0]) == -93)
        #expect(env.bsd(k, 236, [path, name, At.out + 0x400, 16, 0, 4]) == -93)
        #expect(env.bsd(k, 236, [path, name, At.out + 0x400, 16, 0, 2]) == 0)
        #expect(env.bsd(k, 236, [path, name, At.out + 0x400, 16, 0, 2]) == -17)
        #expect(env.bsd(k, 234, [path, name, 0, 0, 0, 0]) == 16)
        #expect(env.bsd(k, 234, [path, name, At.out + 0x500, 4, 0, 0]) == -34)
        #expect(env.bsd(k, 234, [path, name, At.out + 0x500, 64, 0, 0]) == 16)
        #expect(env.read(k, At.out + 0x500, 16) == Array("0123456789abcdef".utf8))
        let fd = env.bsd(k, 5, [path, 2, 0])
        #expect(env.bsd(k, 241, [UInt64(fd), At.out + 0x600, 64, 0]) == 18)
        #expect(String(decoding: env.read(k, At.out + 0x600, 17), as: UTF8.self) == "com.apple.db.uuid")
        #expect(env.bsd(k, 239, [UInt64(fd), name, 0]) == 0)
        #expect(env.bsd(k, 240, [path, 0, 0, 0]) == 0)
    }

    static func signedMachO(identifier: String, platform: UInt8, entitlements: String) -> [UInt8] {
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
        var cd = [UInt8](repeating: 0, count: 88)
        let ident = Array(identifier.utf8) + [0]
        cd.replaceSubrange(0..<4, with: be(0xFADE_0C02))
        cd.replaceSubrange(8..<12, with: be(0x20400))
        cd.replaceSubrange(16..<20, with: be(UInt32(88 + ident.count)))
        cd.replaceSubrange(20..<24, with: be(88))
        cd[36] = 32; cd[37] = 2; cd[38] = platform; cd[39] = 14
        cd += ident
        cd.replaceSubrange(4..<8, with: be(UInt32(cd.count)))
        let ent = be(0xFADE_7171) + be(UInt32(8 + entitlements.utf8.count)) + Array(entitlements.utf8)
        var blob = be(0xFADE_0CC0) + be(0) + be(2) + be(0) + be(28) + be(5) + be(UInt32(28 + cd.count))
        blob += cd + ent
        blob.replaceSubrange(4..<8, with: be(UInt32(blob.count)))
        var macho: [UInt8] = []
        for v: UInt32 in [0xFEED_FACF, 0x0100_000C, 0, 2, 2, 40, 0, 0] { macho.appendLE(v) }
        for v: UInt32 in [0x32, 24, 7, 0x1A_0000, 0x1A_0000, 0] { macho.appendLE(v) }
        let offset = UInt32(macho.count + 16)
        for v: UInt32 in [0x1D, 16, offset, UInt32(blob.count)] { macho.appendLE(v) }
        return macho + blob
    }

    @Test func csopsReadsTheSignature() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let exe = env.root + "/signed"
        try Data(Self.signedMachO(identifier: "com.example.daemon", platform: 1, entitlements: "<plist/>"))
            .write(to: URL(fileURLWithPath: exe))
        let (_, _, child) = env.spawn(from: root, path: exe)
        let c = try #require(env.kernel(child))
        let buf = At.out
        #expect(env.bsd(root, 169, [UInt64(child), 0, buf, 4]) == 0)
        #expect(env.u32(root, buf) == 0x2600_4201)
        #expect(env.bsd(root, 169, [UInt64(child), 11, buf, 256]) == 0)
        let id = env.read(root, buf, 8 + 19)
        #expect(Array(id[0..<8]) == [0, 0, 0, 0, 0, 0, 0, 27])
        #expect(String(decoding: id[8..<26], as: UTF8.self) == "com.example.daemon")
        #expect(env.bsd(root, 169, [UInt64(child), 11, buf, 4]) == -34)
        env.put(root, [UInt8](repeating: 0xEE, count: 8), at: buf)
        #expect(env.bsd(root, 169, [UInt64(child), 11, buf, 8]) == -34)
        #expect(env.read(root, buf, 8) == [0, 0, 0, 0, 0, 0, 0, 27])
        #expect(env.bsd(root, 169, [UInt64(child), 14, buf, 256]) == -2)
        #expect(env.bsd(root, 169, [UInt64(child), 7, buf, 8]) == -34)
        #expect(env.read(root, buf, 8) == [0xFA, 0xDE, 0x71, 0x71, 0, 0, 0, 16])
        #expect(env.bsd(root, 169, [UInt64(child), 7, buf, 64]) == 0)
        #expect(String(decoding: env.read(root, buf + 8, 8), as: UTF8.self) == "<plist/>")
        #expect(env.bsd(root, 169, [UInt64(child), 5, buf, 20]) == 0)
        #expect(env.bsd(root, 169, [UInt64(child), 17, buf, 4]) == 0 && env.u32(root, buf) == 1)
        #expect(env.bsd(root, 169, [UInt64(child), 2, 0, 0]) == -1)
        #expect(env.bsd(root, 169, [4242, 0, buf, 4]) == -3)
        var token = [UInt8](repeating: 0, count: 32)
        token.putLE(child, at: 20)
        token.putLE(c.pidVersion, at: 28)
        env.put(root, token, at: buf + 0x100)
        #expect(env.bsd(root, 170, [UInt64(child), 0, buf, 4, buf + 0x100]) == 0)
        token.putLE(c.pidVersion &+ 1, at: 28)
        env.put(root, token, at: buf + 0x100)
        #expect(env.bsd(root, 170, [UInt64(child), 0, buf, 4, buf + 0x100]) == -3)
        #expect(env.bsd(root, 169, [0, 0, buf, 4]) == 0 && env.u32(root, buf) == 0)
        #expect(env.bsd(root, 169, [0, 11, buf, 64]) == -22)
    }

    @Test func platformCodeRoots() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let exe = env.root + "/runtime-daemon"
        try Data(Self.signedMachO(identifier: "com.example.rtd", platform: 0, entitlements: "<plist/>"))
            .write(to: URL(fileURLWithPath: exe))
        let (_, _, child) = env.spawn(from: root, path: exe)
        let buf = At.out
        DarwinKernel.setPlatformCodeRoots([])
        #expect(env.bsd(root, 169, [UInt64(child), 0, buf, 4]) == 0 && env.u32(root, buf) == 0x2200_0201)
        DarwinKernel.setPlatformCodeRoots([env.root])
        defer { DarwinKernel.setPlatformCodeRoots([]) }
        #expect(env.bsd(root, 169, [UInt64(child), 0, buf, 4]) == 0 && env.u32(root, buf) == 0x2600_4201)
        #expect(env.bsd(root, 169, [UInt64(child), 17, buf, 4]) == 0 && env.u32(root, buf) == 1)
    }
}
