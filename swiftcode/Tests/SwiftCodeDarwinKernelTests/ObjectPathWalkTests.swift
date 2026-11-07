import Foundation
import Testing
@testable import SwiftCodeDarwinKernel

@Suite struct ObjectPathWalkTests {
    @Test func findsNestedFileAndNotesEveryEntry() throws {
        let base = NSTemporaryDirectory() + "swiftcode-objwalk-\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        let fm = FileManager.default
        try fm.createDirectory(atPath: base + "/a/b/c", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: base + "/d", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: base + "/a/b/c/target"))
        try Data("y".utf8).write(to: URL(fileURLWithPath: base + "/d/other"))
        try fm.createSymbolicLink(atPath: base + "/loop", withDestinationPath: base)
        defer { try? fm.removeItem(atPath: base) }

        var st = stat()
        #expect(lstat(base + "/a/b/c/target", &st) == 0)
        var noted: [UInt64: String] = [:]
        let found = DarwinKernel.walkForObject(hostBase: base, guestBase: "/vol", objid: UInt64(st.st_ino)) { ino, path in
            noted[ino] = path
        }
        #expect(found == "/vol/a/b/c/target")
        #expect(noted[UInt64(st.st_ino)] == "/vol/a/b/c/target")

        var all: [String] = []
        let none = DarwinKernel.walkForObject(hostBase: base, guestBase: "", objid: UInt64.max) { _, path in all.append(path) }
        #expect(none == nil)
        #expect(Set(all) == Set(["/a", "/a/b", "/a/b/c", "/a/b/c/target", "/d", "/d/other", "/loop"]))
        #expect(all.count == 7)
    }
}
