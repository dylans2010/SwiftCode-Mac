import Foundation
import Testing
import SwiftCodeDarwinABI
@testable import SwiftCodeDarwinKernel

@Suite(.serialized) struct VolumeFeaturesTests {
    typealias At = ProcEnv.At
    static let cwd = UInt64(bitPattern: -2)
    static let genCount: UInt32 = 0x80000, documentID: UInt32 = 0x100000, flagsAttr: UInt32 = 0x40000
    static let cmnExtended: UInt64 = 0x20
    static let tracked: UInt64 = 0x40

    let env: ProcEnv
    var k: DarwinKernel { env.rootKernel }
    init() throws { env = try ProcEnv() }

    func put(_ s: String, _ va: UInt64) -> UInt64 { env.putString(k, s, at: va); return va }

    func attributes(_ path: String, common: UInt32 = 0, volume: UInt32 = 0, options: UInt64 = cmnExtended) -> [UInt32]? {
        var alist = [UInt8](repeating: 0, count: 24)
        alist.putLE(UInt16(5), at: 0)
        alist.putLE(common, at: 4)
        alist.putLE(volume, at: 8)
        env.put(k, alist, at: At.out + 0x800)
        let p = put(path, At.out + 0x900)
        guard env.bsd(k, 220, [p, At.out + 0x800, At.out + 0xC00, 256, options]) == 0 else { return nil }
        let reply = env.read(k, At.out + 0xC00, 256)
        let length = Int(reply.readLE(UInt32.self, at: 0))
        return stride(from: 4, to: length, by: 4).map { reply.readLE(UInt32.self, at: $0) }
    }

    func statFlags(_ path: String) -> UInt32 {
        #expect(env.bsd(k, 340, [put(path, At.out + 0x900), At.out + 0xA00]) == 0)
        return env.read(k, At.out + 0xA00 + 116, 4).readLE(UInt32.self, at: 0)
    }

    func open(_ path: String, _ flags: UInt64) -> UInt64 {
        let fd = env.bsd(k, 5, [put(path, At.out + 0x900), flags, 0o644])
        #expect(fd >= 0, "open \(path)")
        return UInt64(fd)
    }

    func pwrite(_ fd: UInt64, _ text: String, at offset: UInt64 = 0) {
        env.put(k, Array(text.utf8), at: At.out + 0x1000)
        #expect(env.bsd(k, 154, [fd, At.out + 0x1000, UInt64(text.utf8.count), offset]) == text.utf8.count)
    }

    func rename(_ a: String, _ b: String, flags: UInt64 = 0) -> Int64 {
        env.bsd(k, 488, [Self.cwd, put(a, At.out + 0x100), Self.cwd, put(b, At.out + 0x500), flags])
    }

    @Test func capabilitiesIncludeTheFourBits() throws {
        let caps = try #require(attributes(env.root, volume: 0x8002_0000, options: 0))
        #expect(caps.count == 8)
        #expect(caps[0] & 0x0018_0000 == 0x0018_0000)
        #expect(caps[1] & 0x000D_0000 == 0x000D_0000)
        #expect(caps[0] == 0x001A_4F47 && caps[1] == 0x000D_4302)
        #expect(caps[4] & caps[0] == caps[0] && caps[5] & caps[1] == caps[1])
    }

    @Test func documentIDsFollowTrackedFiles() throws {
        let doc = env.root + "/doc", moved = env.root + "/moved"
        try Data("v1".utf8).write(to: URL(fileURLWithPath: doc))
        #expect(attributes(doc, common: Self.documentID) == [0])
        #expect(attributes(doc, common: Self.documentID, options: 0) == nil)
        #expect(env.bsd(k, 34, [put(doc, At.out + 0x100), Self.tracked | 0x8000]) == 0)
        #expect(statFlags(doc) == 0x8040)
        let id = try #require(attributes(doc, common: Self.flagsAttr | Self.documentID)).last!
        #expect(id != 0)
        #expect(attributes(doc, common: Self.flagsAttr) == [0x8040])
        #expect(rename(doc, moved) == 0)
        #expect(attributes(moved, common: Self.documentID) == [id])
        let tmp = env.root + "/moved.sb-tmp"
        try Data("v2".utf8).write(to: URL(fileURLWithPath: tmp))
        #expect(rename(tmp, moved) == 0)
        #expect(attributes(moved, common: Self.documentID) == [id])
        #expect(statFlags(moved) & 0x40 != 0)
        #expect(env.bsd(k, 10, [put(moved, At.out + 0x100)]) == 0)
        let fd = open(moved, 0x601)
        _ = env.bsd(k, 6, [fd])
        #expect(attributes(moved, common: Self.documentID) == [id])
        #expect(env.bsd(k, 34, [put(moved, At.out + 0x100), 0]) == 0)
        #expect(attributes(moved, common: Self.documentID) == [0] && statFlags(moved) == 0)
        #expect(env.bsd(k, 34, [put(moved, At.out + 0x100), 0x20000]) == -1)
        #expect(env.bsd(k, 34, [put(moved, At.out + 0x100), Self.tracked]) == 0)
        #expect(try #require(attributes(moved, common: Self.documentID)).first! != id)
    }

    @Test func writeGenerationCountsChangeWithEveryWrite() throws {
        let path = env.root + "/gen"
        let fd = open(path, 0x202)
        pwrite(fd, "a")
        let g1 = try #require(attributes(path, common: Self.genCount)).first!
        #expect(g1 != 0)
        #expect(attributes(path, common: Self.genCount) == [g1])
        pwrite(fd, "b")
        let g2 = try #require(attributes(path, common: Self.genCount)).first!
        #expect(g2 != g1)
        #expect(env.bsd(k, 15, [put(path, At.out + 0x100), 0o600]) == 0)
        #expect(attributes(path, common: Self.genCount) == [g2])
        #expect(attributes(path, common: Self.genCount, options: 0) == nil)
        _ = env.bsd(k, 6, [fd])
        #expect(try #require(attributes(env.root, common: Self.genCount)).first! != 0)
    }

    @Test func clonesCopyContentsAndAttributes() throws {
        let src = env.root + "/src", dst = env.root + "/dst"
        try Data("payload".utf8).write(to: URL(fileURLWithPath: src))
        #expect(chmod(src, 0o640) == 0)
        env.put(k, Array("v".utf8), at: At.out + 0x1000)
        #expect(env.bsd(k, 236, [put(src, At.out + 0x100), put("com.example.tag", At.out + 0x300), At.out + 0x1000, 1, 0, 0]) == 0)
        #expect(env.bsd(k, 34, [put(src, At.out + 0x100), Self.tracked]) == 0)
        let srcID = try #require(attributes(src, common: Self.documentID)).first!
        let clone = { (a: String, b: String, flags: UInt64) -> Int64 in
            self.env.bsd(self.k, 462, [Self.cwd, self.put(a, At.out + 0x100), Self.cwd, self.put(b, At.out + 0x500), flags])
        }
        #expect(clone(src, dst, 0) == 0)
        #expect(try String(contentsOfFile: dst, encoding: .utf8) == "payload")
        #expect(try (FileManager.default.attributesOfItem(atPath: dst)[.posixPermissions] as! Int) == 0o640)
        #expect(env.bsd(k, 234, [put(dst, At.out + 0x100), put("com.example.tag", At.out + 0x300), 0, 0, 0, 0]) == 1)
        let dstID = try #require(attributes(dst, common: Self.documentID)).first!
        #expect(dstID != 0 && dstID != srcID && statFlags(dst) & 0x40 != 0)
        #expect(clone(src, dst, 0) == -17)
        #expect(clone(env.root + "/missing", env.root + "/x", 0) == -2)
        #expect(clone(src, env.root + "/x", 0x20) == -22)
        #expect(clone(src, env.root + "/no/such/dir", 0) == -2)
        let tree = env.root + "/tree"
        try FileManager.default.createDirectory(atPath: tree + "/sub", withIntermediateDirectories: true)
        try Data("leaf".utf8).write(to: URL(fileURLWithPath: tree + "/sub/leaf"))
        #expect(clone(tree, env.root + "/tree2", 0) == 0)
        #expect(try String(contentsOfFile: env.root + "/tree2/sub/leaf", encoding: .utf8) == "leaf")
        let wfd = open(src, 0x1)
        #expect(env.bsd(k, 517, [wfd, Self.cwd, put(env.root + "/w", At.out + 0x500), 0]) == -9)
        let rfd = open(src, 0x0)
        #expect(env.bsd(k, 517, [rfd, Self.cwd, put(env.root + "/r", At.out + 0x500), 0]) == 0)
        #expect(try String(contentsOfFile: env.root + "/r", encoding: .utf8) == "payload")
    }

    @Test func exclusiveAndSwappingRenames() throws {
        let a = env.root + "/a", b = env.root + "/b"
        try Data("A".utf8).write(to: URL(fileURLWithPath: a))
        try Data("B".utf8).write(to: URL(fileURLWithPath: b))
        #expect(rename(a, b, flags: 0x4) == -17)
        #expect(rename(a, b, flags: 0x2) == 0)
        #expect(try String(contentsOfFile: a, encoding: .utf8) == "B" && String(contentsOfFile: b, encoding: .utf8) == "A")
        #expect(rename(a, env.root + "/c", flags: 0x4) == 0)
        #expect(rename(b, env.root + "/missing", flags: 0x2) == -2)
        #expect(!FileManager.default.fileExists(atPath: env.root + "/b.swiftcode-swap"))
    }

    @Test func changesReachTheFeed() throws {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var changes: [FileChange] = []
        }
        let box = Box()
        let root = env.root
        fileChangeFeedLock.lock()
        defer { fileChangeFeedLock.unlock() }
        FileChangeFeed.install { c in
            guard c.path.hasPrefix(root + "/") else { return }
            box.lock.withLock { box.changes.append(c) }
        }
        FileChangeFeed.setListening(true)
        defer { FileChangeFeed.install(nil) }
        let file = root + "/f", dir = root + "/d"
        let fd = open(file, 0x202)
        pwrite(fd, "x")
        _ = env.bsd(k, 6, [fd])
        #expect(env.bsd(k, 136, [put(dir, At.out + 0x100), 0o755]) == 0)
        #expect(env.bsd(k, 15, [put(file, At.out + 0x100), 0o600]) == 0)
        #expect(rename(file, dir + "/g") == 0)
        #expect(env.bsd(k, 10, [put(dir + "/g", At.out + 0x100)]) == 0)
        #expect(env.bsd(k, 137, [put(dir, At.out + 0x100)]) == 0)
        let seen = box.lock.withLock { box.changes.map { "\($0.kind) \($0.item) \($0.path.dropFirst(root.count))" } }
        #expect(seen == ["created file /f", "modified file /f", "created directory /d", "owner file /f",
                         "renamed file /f", "renamed file /d/g", "removed file /d/g", "removed directory /d"])
        #expect(box.lock.withLock { box.changes.allSatisfy { $0.pid == k.pid } })
    }
}
