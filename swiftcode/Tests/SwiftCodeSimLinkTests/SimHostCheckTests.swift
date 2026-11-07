import Foundation
import Testing
@testable import SwiftCodeSimLink

struct SimHostCheckTests {
    @Test func problemsNameEveryMissingPiece() throws {
        let fm = FileManager.default
        let d = fm.temporaryDirectory.appendingPathComponent("swiftcode-simhost-check-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: d) }
        let home = d.appendingPathComponent("home"), tree = d.appendingPathComponent("tree"), rt = d.appendingPathComponent("rt")
        try fm.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let text = "SWIFTCODE_SIM_HOME=\(home.path)\nSWIFTCODE_SIM_TREE=\(tree.path)\nSWIFTCODE_SIM_RUNTIME=\(rt.path)\n"
        let c = try SimHostConfig.load(text: text, environment: [:])
        #expect(c.problems().count == 4)
        try fm.createDirectory(at: tree.appendingPathComponent(".build/release"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tree.appendingPathComponent("SimShim/out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: rt.appendingPathComponent("sbin"), withIntermediateDirectories: true)
        for (url, exec) in [(tree.appendingPathComponent(".build/release/swiftcode-simd"), true), (tree.appendingPathComponent("SimShim/out/shim.bin"), false),
                            (rt.appendingPathComponent("sbin/launchd_sim"), false), (home.appendingPathComponent("bin/swiftcode-sim"), true)] {
            try Data("x".utf8).write(to: url)
            if exec { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        #expect(c.problems() == [])
        #expect(throws: (any Error).self) { try SimHostConfig.load(text: "SWIFTCODE_SIM_HOME=/h\nSWIFTCODE_SIM_RUNTIME=/r\n", environment: [:]) }
    }
}
