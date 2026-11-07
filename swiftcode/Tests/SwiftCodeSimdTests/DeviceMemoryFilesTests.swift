import Foundation
import Testing
@testable import swiftcode_simd

@Suite(.serialized) struct DeviceMemoryFilesTests {
    @Test func coldSaveRestoreFinish() throws {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "swiftcode-memfiles-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: root) }
        let shm = root + "/shm"
        try fm.createDirectory(atPath: shm, withIntermediateDirectories: true)
        setenv("SWIFTCODE_MEMORY_DIR", shm, 1)
        defer { unsetenv("SWIFTCODE_MEMORY_DIR") }
        var layout = DeviceLayout(dev: root + "/dev", runtimeRoot: "/rr", udid: nil, jobPaths: [])
        try fm.createDirectory(atPath: layout.data + "/tmp", withIntermediateDirectories: true)
        let host = layout.memoryHostPath
        #expect(host.hasPrefix(shm + "/swiftcode-\(getuid())-"))
        #expect(layout.framebufferStatePath == host + "/swiftcode-framebuffer.state")
        #expect(layout.framebufferStateGuestPath == layout.dev + "/swiftcode-memory/swiftcode-framebuffer.state")

        try fm.createDirectory(atPath: host, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: URL(fileURLWithPath: host + "/old"))
        try layout.prepareMemoryDirectory()
        #expect(try fm.contentsOfDirectory(atPath: host) == [".owner"])
        #expect(fm.contents(atPath: host + "/.owner") == Data("\(getpid())\n".utf8))

        try Data("frame 7".utf8).write(to: URL(fileURLWithPath: layout.framebufferStatePath))
        layout.saveMemoryDirectory()
        #expect(try fm.contentsOfDirectory(atPath: layout.memorySavedPath) == ["swiftcode-framebuffer.state"])
        let saved = try Data(contentsOf: URL(fileURLWithPath: layout.memorySavedPath + "/swiftcode-framebuffer.state"))
        #expect(saved == Data("frame 7".utf8))
        let savedTime = try fm.attributesOfItem(atPath: layout.framebufferStatePath)[.modificationDate] as? Date

        try Data("timing".utf8).write(to: URL(fileURLWithPath: host + "/swiftcode-framebuffer.timing"))
        layout.finishMemoryDirectory()
        #expect(!fm.fileExists(atPath: host))
        #expect(fm.fileExists(atPath: layout.data + "/tmp/swiftcode-framebuffer.timing"))

        layout.restoring = true
        try layout.prepareMemoryDirectory()
        #expect(try Data(contentsOf: URL(fileURLWithPath: layout.framebufferStatePath)) == Data("frame 7".utf8))
        let restoredTime = try fm.attributesOfItem(atPath: layout.framebufferStatePath)[.modificationDate] as? Date
        #expect(restoredTime.map { Int($0.timeIntervalSince1970) } == savedTime.map { Int($0.timeIntervalSince1970) })
        layout.finishMemoryDirectory()
    }

    @Test func staleDirectoriesAreSwept() throws {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "swiftcode-memsweep-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: root) }
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        setenv("SWIFTCODE_MEMORY_DIR", root, 1)
        defer { unsetenv("SWIFTCODE_MEMORY_DIR") }
        let prefix = root + "/" + DeviceLayout.memoryNamePrefix
        func make(_ name: String, owner: String?) throws {
            try fm.createDirectory(atPath: prefix + name, withIntermediateDirectories: true)
            if let owner { try Data(owner.utf8).write(to: URL(fileURLWithPath: prefix + name + "/.owner")) }
        }
        try make("dead", owner: "1073741808\n")
        try make("alive", owner: "\(getpid())\n")
        try make("young", owner: nil)
        try fm.createDirectory(atPath: root + "/swiftcode-other-user", withIntermediateDirectories: true)
        DeviceLayout.sweepStaleMemoryDirectories(except: prefix + "this-device")
        #expect(!fm.fileExists(atPath: prefix + "dead"))
        #expect(fm.fileExists(atPath: prefix + "alive"))
        #expect(fm.fileExists(atPath: prefix + "young"))
        #expect(fm.fileExists(atPath: root + "/swiftcode-other-user"))
    }

    @Test func unusableMemoryDirectoryFallsBackToTheDataVolume() throws {
        setenv("SWIFTCODE_MEMORY_DIR", "/nonexistent-swiftcode-memory", 1)
        defer { unsetenv("SWIFTCODE_MEMORY_DIR") }
        let layout = DeviceLayout(dev: "/tmp/swiftcode-dev-x", runtimeRoot: "/rr", udid: nil, jobPaths: [])
        #expect(layout.memoryHostPath == layout.data + "/tmp/swiftcode-memory")
    }
}
