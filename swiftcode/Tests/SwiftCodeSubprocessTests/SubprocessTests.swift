import Foundation
import Testing
import SwiftCodeSubprocess

@Suite struct SubprocessTests {
    @Test func capturesBothStreamsWithoutDeadlock() throws {
        let out = try Subprocess.run("/bin/sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' e >&2; echo hello; exit 3"])
        #expect(out.status == 3)
        #expect(out.stdoutText == "hello\n")
        #expect(out.stderr.count == 200_000)
    }

    @Test func finishesWhenTheGlobalQueuesAreFull() {
        let release = DispatchSemaphore(value: 0)
        let blockers = ProcessInfo.processInfo.activeProcessorCount * 8
        for _ in 0..<blockers { DispatchQueue.global().async { release.wait() } }
        defer { for _ in 0..<blockers { release.signal() } }
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread { _ = try? Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2"]); done.signal() }
        #expect(done.wait(timeout: .now() + 20) == .success)
    }

    @Test func notStartingThrows() {
        #expect(throws: (any Error).self) { try Subprocess.run("/nonexistent/tool", []) }
    }

    @MainActor @Test func guardRecordsMainThreadRunsOnly() throws {
        let mainThread = Thread.isMainThread
        let onMain = try MainThreadGuard.violations { _ = try Subprocess.run("/bin/echo", ["x"]) }
        #if DEBUG
        if mainThread {
            #expect(onMain.count == 1 && onMain.first?.operation.hasPrefix("echo x") == true)
            #expect(onMain.first?.location.hasPrefix("SwiftCodeSubprocessTests/") == true)
            #expect(onMain.first?.stack.isEmpty == false)
        } else {
            #expect(onMain.isEmpty)
        }
        #else
        #expect(onMain.isEmpty)
        #endif
        let offMain = MainThreadGuard.violations {
            let done = DispatchSemaphore(value: 0)
            Thread.detachNewThread { _ = try? Subprocess.run("/bin/echo", ["y"]); done.signal() }
            done.wait()
        }
        #expect(offMain.isEmpty)
    }
}
