import Foundation
import Testing
@testable import YcodeIDECore

@Suite struct SevenZipLookupTests {
    func folders(_ layout: [[String]]) throws -> (root: URL, path: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-7z-\(UUID().uuidString)")
        var dirs: [String] = []
        for (i, tools) in layout.enumerated() {
            let dir = root.appendingPathComponent("p\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for t in tools {
                let file = dir.appendingPathComponent(t).path
                FileManager.default.createFile(atPath: file, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
            }
            dirs.append(dir.path)
        }
        return (root, dirs.joined(separator: ":"))
    }

    @Test func thePackagedSevenZipIsFoundOnTheFlatpaksPath() throws {
        let f = try folders([["swift", "git"], ["7zz", "swiftcode"], ["7z"]])
        defer { try? FileManager.default.removeItem(at: f.root) }
        let found = SevenZipImageReader.find(environment: ["PATH": f.path])
        #expect(found == f.root.appendingPathComponent("p1/7zz").path)
    }

    @Test func sevenZipEnvironmentVariableWinsAndPlainSevenZIsTheFallback() throws {
        let f = try folders([[], ["7z"]])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(SevenZipImageReader.find(environment: ["PATH": f.path]) == f.root.appendingPathComponent("p1/7z").path)
        #expect(SevenZipImageReader.find(environment: ["PATH": f.path, "SWIFTCODE_7Z": "/opt/7zz"]) == "/opt/7zz")
        #expect(SevenZipImageReader.find(environment: ["PATH": f.root.appendingPathComponent("p0").path]) == nil)
    }
}
