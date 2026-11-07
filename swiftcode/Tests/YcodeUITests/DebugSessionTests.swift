import AppKit
import Foundation
import Testing
import YcodeDebug
@testable import YcodeIDECore
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
func waitUntil(_ seconds: Double = 60, _ condition: () -> Bool) async -> Bool {
    ProcessAudit.arm()
    var waited = 0.0
    while !condition() {
        if waited > seconds || Task.isCancelled { return false }
        let start = Date()
        try? await Task.sleep(nanoseconds: 50_000_000)
        waited += min(Date().timeIntervalSince(start), 0.25)
    }
    return true
}

@MainActor
func endDebugSession(_ session: WorkspaceSession) async {
    guard let client = session.debugClient else { return }
    try? await client.disconnect(terminate: true, timeout: .seconds(5))
    client.close()
    _ = await waitUntil(15) { session.debugClient == nil }
}

private let program = """
#include <stdio.h>

struct Pair { int a; int b; };

int add(int a, int b) {
    int s = a + b;
    return s;
}

int main(void) {
    struct Pair p = { 2, 3 };
    int y = add(p.a, p.b);
    printf("sum=%d\\n", y);
    return 0;
}

"""

@MainActor
@Suite(.serialized, .heavyIntegration, .timeLimit(.minutes(5))) struct DebugSessionEndToEndTests {
    func debuggee() throws -> (exe: String, source: String)? {
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/session-e2e")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("prog.c")
        try program.write(to: src, atomically: true, encoding: .utf8)
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"E2E\")\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let exe = dir.appendingPathComponent("prog").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["clang", "-g", "-O0", "-o", exe, src.path]
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? (exe, src.path) : nil
    }

    @Test func sessionDrivesTheWindow() async throws {
        guard LLDBDAP.locate() != nil else { return }
        let lock = await InterprocessLock.acquire(path: InterprocessLock.debuggerTestLockPath)
        defer { lock.unlock() }
        guard let (exe, source) = try debuggee() else { return }

        guard await Task.detached(operation: { InterprocessLock.canLaunchUnderDebugger(exe) }).value else {
            print("skipping: cannot launch under the debugger (\(InterprocessLock.lastProblem ?? "launch failed"))")
            return
        }
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: source).deletingLastPathComponent()
        let session = WorkspaceSession(model: try WorkspaceModel(url: dir))
        let wc = WorkspaceWindowController(session: session, loadDestinations: false, startLanguageService: false)
        wc.window?.appearance = NSAppearance(named: .aqua)
        wc.applyDefaultLayout()
        session.breakpoints.click(file: source, line: 6)
        do {
            try await drive(session, wc, exe: exe, source: source)
        } catch {
            await endDebugSession(session)
            throw error
        }
        await endDebugSession(session)
    }

    func drive(_ session: WorkspaceSession, _ wc: WorkspaceWindowController, exe: String, source: String) async throws {
        await session.debug(program: exe)
        #expect(await waitUntil(110) { session.stoppedThread != nil && !session.variables.isEmpty })
        #expect(session.currentLocation?.line == 6)
        #expect(Set(session.variables.map(\.name)).isSuperset(of: ["a", "b", "s"]))
        #expect(wc.editor.fileURL?.path == source)
        #expect(wc.editor.gutter.marks.currentLine == 6)

        let stopped = try #require(wc.navigator.debugThreadRows.first { !$0.children.isEmpty })
        #expect(stopped.children.first?.title.contains("add") == true)
        let mainFrame = try #require(stopped.children.first { $0.title.contains("main") })

        await session.selectFrame(mainFrame.frameID!)
        let p = try #require(wc.debugArea.roots.first { $0.variable.name == "p" })
        #expect(p.isExpandable && p.children == nil)
        let fields = await wc.debugArea.expand(p)
        #expect(fields.map(\.variable.name) == ["a", "b"])
        #expect(fields.map(\.variable.value) == ["2", "3"])

        let window = try #require(wc.window)
        _ = try WindowSnapshotTests().render(window.contentView!.superview!, to: "debug-session.png")

        await session.selectFrame(stopped.children[0].frameID!)
        await session.step("over")
        #expect(await waitUntil { session.stoppedThread != nil && session.currentLocation?.line == 7 })
        #expect(await waitUntil { session.variables.first { $0.name == "s" }?.value == "5" })

        await session.continueOrPause()
        #expect(await waitUntil { session.debugClient == nil })
        #expect(session.console.contains("exit code: 0"))
    }
}
