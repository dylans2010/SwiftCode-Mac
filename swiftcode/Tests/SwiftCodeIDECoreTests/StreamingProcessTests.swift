import Foundation
import Testing
@testable import SwiftCodeIDECore

@MainActor
@Suite struct StreamingProcessTests {
    #if os(macOS)
    nonisolated static let reportsExitBeforeThePipeCloses = true
    #else
    nonisolated static let reportsExitBeforeThePipeCloses = false
    #endif

    final class Seen {
        var lines: [String] = []
        var linesAtExit: Int?
        var status: Int32?
    }

    func run(_ script: String, readDelay: TimeInterval = 0, grace: TimeInterval = 1, timeout: TimeInterval = 60) async throws -> Seen {
        let seen = Seen()
        let p = StreamingProcess(executable: "/bin/sh", arguments: ["-c", script])
        p.readDelayForTesting = readDelay
        p.outputGrace = grace
        try p.start(onLine: { seen.lines.append($0) }, onExit: { status in
            seen.linesAtExit = seen.lines.count
            seen.status = status
        })
        let end = Date().addingTimeInterval(timeout)
        while seen.status == nil, Date() < end { try await Task.sleep(nanoseconds: 5_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        return seen
    }

    @Test func everyLineArrivesBeforeTheExit() async throws {
        for delay in [0.02, 0, 0, 0] {
            let seen = try await run("i=0; while [ $i -lt 20000 ]; do echo \"line $i of the run\"; i=$((i+1)); done; printf 'last'; exit 3",
                                     readDelay: delay, grace: 30)
            #expect(seen.status == 3)
            #expect(seen.lines.count == 20001)
            #expect(seen.linesAtExit == seen.lines.count)
            #expect(seen.lines.first == "line 0 of the run" && seen.lines.last == "last")
            #expect(seen.lines.dropLast().enumerated().allSatisfy { $0.element == "line \($0.offset) of the run" })
        }
    }

    @Test(.enabled(if: Self.reportsExitBeforeThePipeCloses))
    func anInheritedPipeDoesNotHoldTheExitBack() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("inherited-\(UUID().uuidString)")
        defer { killChild(in: pidFile) }
        let start = Date()
        let seen = try await run("echo before; sleep 60 & echo $! > '\(pidFile.path)'; echo after; exit 0", timeout: 40)
        #expect(seen.status == 0)
        #expect(seen.lines == ["before", "after"])
        #expect(Date().timeIntervalSince(start) < 20)
    }
}
