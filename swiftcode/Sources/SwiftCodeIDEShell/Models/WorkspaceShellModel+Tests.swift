import Foundation
import SwiftCodeBuild
import SwiftCodeIDECore
import SwiftCodeSubprocess

extension WorkspaceShellModel {
    @discardableResult
    public func runTests(_ only: [DiscoveredTest] = []) async -> [TestOutcome] {
        guard saveAllBeforeBuilding() else { return [] }
        #if os(Linux)
        if session.model.kind == .package, session.testRunner.swift == TestRunner().swift, !HostTool.isInFlatpak(),
           ShellToolchain.locate("swift") == nil {
            await build(.test)
            return []
        }
        #endif
        isDebugAreaShown = true
        debugPane = .buildLog
        testing.noteRunning(only)
        let outcomes = await session.runTests(only: only)
        testing.noteFinished()
        return outcomes
    }

    public func testAgain() async {
        guard let last = session.lastTestRun else { return }
        await runTests(last.tests)
    }

    public func runTests(forRow id: String) {
        let list = testing.tests(forRow: id)
        guard !list.isEmpty, !isBusy else { return }
        Task { await runTests(id == "tests:root" ? [] : list) }
    }

    public func runTests(atLine line: Int) {
        guard let path = document?.path, !isBusy else { return }
        let list = session.testsForDiamond(file: path, line: line)
        guard !list.isEmpty else { return }
        Task { await runTests(list) }
    }

    public var testDiamonds: [Int: TestOutcome.Status?] {
        guard let path = document?.path else { return [:] }
        return testing.diamonds(in: path)
    }
}
