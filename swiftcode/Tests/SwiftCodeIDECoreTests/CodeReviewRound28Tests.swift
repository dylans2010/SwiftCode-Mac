import Foundation
import Testing
@testable import SwiftCodeIDECore

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct CodeReviewRound28Tests {
    private func repo(_ name: String) throws -> (URL, URL) {
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/\(name)")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let main = dir.appendingPathComponent("Sources/App/main.swift")
        func git(_ a: String...) throws { _ = try GitRepository.run("/usr/bin/git", ["-C", dir.path, "-c", "user.name=T", "-c", "user.email=t@swiftcode.invalid", "-c", "commit.gpgsign=false"] + a) }
        try git("init", "-q", "-b", "main")
        try "let a = 1\n".write(to: main, atomically: true, encoding: .utf8)
        try git("add", "-A"); try git("commit", "-q", "-m", "one")
        try "let a = 1\nlet b = 2\n".write(to: main, atomically: true, encoding: .utf8)
        try git("commit", "-qam", "two")
        try "let a = 10\nlet b = 2\nlet c = 3\n".write(to: main, atomically: true, encoding: .utf8)
        return (dir, main)
    }

    @Test func commitSheetUsesGitDiff() throws {
        let (dir, main) = try repo("cr28-c")
        let r = try #require(GitRepository(containing: dir))
        #expect(r.diff(of: main.path) == r.diff(of: main.path, scope: .all))
        #expect(r.diff(of: main.path).hasPrefix("@@"))
    }
}
