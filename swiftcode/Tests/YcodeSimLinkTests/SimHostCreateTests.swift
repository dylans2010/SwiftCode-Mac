import Foundation
import Testing
@testable import YcodeSimLink

@Suite struct SimHostCreateTests {
    func devices(_ extra: String = "") throws -> (SimHostDevices, URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-simhost-create-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let text = "SWIFTCODE_SIM_HOME=\(home.path)\nSWIFTCODE_SIM_TREE=/nonexistent/tree\nSWIFTCODE_SIM_RUNTIME=/nonexistent/RuntimeRoot\n" + extra
        return (SimHostDevices(config: try SimHostConfig.load(text: text, environment: [:])), home)
    }

    @Test func withoutAPristineTheDeviceStartsEmpty() throws {
        let (d, home) = try devices()
        defer { try? FileManager.default.removeItem(at: home) }
        try d.create("iPhone-18-Pro", type: "iphone-18-pro")
        let list = d.list()
        #expect(list.map(\.name) == ["iPhone-18-Pro"])
        #expect(list.first?.deviceType == "iphone-18-pro")
        #expect(list.first?.state == "shutdown")
        #expect(throws: LinkError.self) { try d.create("iPhone-18-Pro", type: "iphone-18-pro") }
    }

    @Test func aPristineIsCopied() throws {
        let pristine = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-pristine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pristine.appendingPathComponent("data"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pristine) }
        let (d, home) = try devices("SWIFTCODE_SIM_PRISTINE_IPAD_A16=\(pristine.path)\n")
        defer { try? FileManager.default.removeItem(at: home) }
        try d.create("iPad", type: "ipad-a16")
        #expect(FileManager.default.fileExists(atPath: d.config.devicesDirectory + "/iPad/data"))
        #expect(d.list().first?.deviceType == "ipad-a16")
    }
}

extension SimHostCreateTests {
    @Test func aTreeWithoutGuestToolsSaysItCannotRunApps() throws {
        let (d, home) = try devices()
        defer { try? FileManager.default.removeItem(at: home) }
        let why = try #require(d.config.appRunProblem())
        #expect(why.contains("/nonexistent/tree/SimShim/out/guest-tests/stage7/ylaunch") && why.contains("SWIFTCODE_SIM_GUEST_TOOLS"))
        let tools = home.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tools.appendingPathComponent("ylaunch").path, contents: Data())
        let (d2, home2) = try devices("SWIFTCODE_SIM_GUEST_TOOLS=\(tools.path)\n")
        defer { try? FileManager.default.removeItem(at: home2) }
        #expect(d2.config.appRunProblem() == nil)
    }
}

extension SimHostCreateTests {
    @Test func aViewerOfABootingDeviceIsToldItIsStarting() {
        #expect(SimHostService.displayNotUpNotice(device: "P", state: "booting") == "P is starting")
        #expect(SimHostService.displayNotUpNotice(device: "P", state: "shutdown") == "the device P is not running")
    }
}

extension SimHostCreateTests {
    @Test func aProgramThatCannotStartIsReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad"), good = dir.appendingPathComponent("good")
        try Data("#!/bin/sh\necho 'bad: error while loading shared libraries: libxml2.so.16: cannot open shared object file' >&2\nexit 127\n".utf8).write(to: bad)
        try Data("#!/bin/sh\necho 1.0\n".utf8).write(to: good)
        for f in [bad, good] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path) }
        #expect(SimHostConfig.loaderProblem(bad.path)?.contains("libxml2.so.16") == true)
        #expect(SimHostConfig.loaderProblem(good.path) == nil)
    }
}

extension SimHostCreateTests {
    @Test func linkSocketsAreCloseOnExec() throws {
        let l = try LinkListener(host: "127.0.0.1", port: 0)
        defer { l.close() }
        let u = try LinkDatagramSocket(host: "127.0.0.1", port: 0)
        #expect(fcntl(l.fd, F_GETFD) & FD_CLOEXEC != 0)
        #expect(fcntl(u.fd, F_GETFD) & FD_CLOEXEC != 0)
    }
}

extension SimHostCreateTests {
    @Test func onlyFailuresAreRateLimited() {
        let now = Date()
        #expect(SimHostService.allows(failures: [], now: now))
        #expect(SimHostService.allows(failures: Array(repeating: now, count: 9), now: now))
        #expect(!SimHostService.allows(failures: Array(repeating: now, count: 10), now: now))
        #expect(SimHostService.allows(failures: Array(repeating: now.addingTimeInterval(-61), count: 10), now: now))
    }

    @Test func trustedClientsAreNotRateLimited() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-ratelimit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let port = Int.random(in: 46900..<47400)
        let config = try SimHostConfig.load(text: "SWIFTCODE_SIM_HOME=\(home.path)\nSWIFTCODE_SIM_TREE=\(dir.path)\nSWIFTCODE_SIM_RUNTIME=\(dir.path)/rt\n"
                                            + "SWIFTCODE_SIMHOST_LISTEN=127.0.0.1:\(port)\nSWIFTCODE_SIMHOST_MEDIA_PORT=\(port + 1)\n", environment: [:])
        let hostStore = LinkStore(directory: dir.appendingPathComponent("h")), clientStore = LinkStore(directory: dir.appendingPathComponent("c"))
        try hostStore.addPeer(TrustedPeer(name: "c", publicKey: try clientStore.identity().publicKey, role: "client"))
        try clientStore.addPeer(TrustedPeer(name: "h", publicKey: try hostStore.identity().publicKey, role: "host", address: "127.0.0.1:\(port)"))
        let service = try SimHostService(config: config, store: hostStore)
        try service.start()
        defer { service.stop() }
        let client = try LinkClient(store: clientStore, clientName: "c")
        let h = try client.host(named: "h")
        var served = 0
        for _ in 0..<15 {
            let c = try client.control(h)
            if (try? c.request(LinkRequest(op: "devices")))?.ok == true { served += 1 }
            c.close()
        }
        #expect(served == 15)
    }
}

extension SimHostCreateTests {
    @Test func aPreviewDeviceStartsWithAnEmptyFolder() throws {
        let (d, home) = try devices()
        defer { try? FileManager.default.removeItem(at: home) }
        try d.create("swiftcode-previews-iphone-18-pro", type: "iphone-18-pro")
        let dir = d.config.devicesDirectory + "/swiftcode-previews-iphone-18-pro"
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir)) == [])
        #expect(d.list().first { $0.name == "swiftcode-previews-iphone-18-pro" }?.deviceType == "iphone-18-pro")
    }
}
