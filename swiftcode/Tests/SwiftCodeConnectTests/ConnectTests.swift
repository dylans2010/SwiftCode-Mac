// Tests for the SwiftCode Connect port (Legacy -> SwiftCodeConnect).
// Static only: not executed here (no Swift toolchain in this environment).
// No network is involved: the envelope round-trip and the /usr/bin/git
// helper run entirely on the local machine.

import Foundation
import Testing
@testable import SwiftCodeConnect

@Suite("SwiftCode Connect ports")
struct ConnectTests {

    @Test("MessageEnvelope encode/decode round-trips a payload")
    func envelopeRoundTrip() throws {
        let info = ConnectProjectInfo(id: UUID().uuidString, name: "Demo",
                                      path: "/tmp/Demo", activeScheme: "Demo",
                                      activeTarget: "Demo", destinations: ["macOS"],
                                      swiftVersion: "6.0")
        let envelope = try MessageEnvelope.encode(payload: info, type: .projectResponse,
                                                  correlationID: "corr-1")
        #expect(envelope.protocolVersion == ConnectProtocolVersion.current)
        #expect(envelope.type == .projectResponse)
        #expect(envelope.correlationID == "corr-1")
        let decoded = try envelope.decodePayload(ConnectProjectInfo.self)
        #expect(decoded == info)
    }

    @Test("ConnectProjectSummary maps to the wire project info")
    func projectSummaryMapping() {
        let summary = ConnectProjectSummary(name: "Demo", path: "/tmp/Demo",
                                            scheme: "Demo", destinations: ["macOS"],
                                            swiftVersion: "6.0")
        let info = summary.connectProjectInfo
        #expect(info.name == "Demo")
        #expect(info.path == "/tmp/Demo")
        #expect(info.activeScheme == "Demo")
        #expect(info.activeTarget == "Demo")
        #expect(info.destinations == ["macOS"])
        #expect(info.swiftVersion == "6.0")
        #expect(info.id == summary.id.uuidString)
    }

    @Test("ConnectLocalGit reads status and branches of a real repo")
    func localGitStatusAndBranches() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"),
                      "git is required for Connect git tests")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func git(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = root
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "git \(args.joined(separator: " ")) failed")
        }
        try git("init", "-b", "main")
        try "hello".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git("add", ".")
        try git("-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "init")

        let status = try ConnectLocalGit.status(at: root)
        #expect(status.branch == "main")
        #expect(status.isClean)
        #expect(status.ahead == 0)
        #expect(status.behind == 0)

        let branches = try ConnectLocalGit.branches(at: root)
        #expect(branches == ["main"])

        // A dirty file shows up as modified.
        try "hello world".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let dirty = try ConnectLocalGit.status(at: root)
        #expect(!dirty.isClean)
        #expect(dirty.modifiedFiles.contains("README.md"))
    }

    @Test("ConnectUnavailableWorkspaceProvider answers honestly")
    func unavailableProvider() async {
        let provider = ConnectUnavailableWorkspaceProvider.shared
        #expect(provider.activeProject == nil)
        #expect(provider.availableProjects.isEmpty)
        #expect(await provider.devices().isEmpty)
        do {
            _ = try await provider.gitStatus(at: URL(fileURLWithPath: "/tmp"))
            Issue.record("expected gitStatus to throw without a workspace")
        } catch {
            #expect(error.localizedDescription.contains("No workspace"))
        }
    }
}
