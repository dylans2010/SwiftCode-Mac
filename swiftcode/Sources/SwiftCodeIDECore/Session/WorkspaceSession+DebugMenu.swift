import Foundation
import SwiftCodeDebug

extension WorkspaceSession {
    public func continueToLine(file: String, line: Int) async {
        guard let c = debugClient, let t = stoppedThread else { return }
        temporaryBreakpoint = (file, line)
        await syncBreakpoints()
        try? await c.continue(threadID: t)
        clearStopState()
        setActivity(.running(runningActivityTitle))
    }

    public func step(_ kind: String, instruction: Bool, singleThread: Bool) async {
        guard let c = debugClient, let t = stoppedThread else { return }
        let command = kind == "in" ? "stepIn" : (kind == "out" ? "stepOut" : "next")
        let granular = instruction || (alwaysShowDisassembly && kind != "out")
        try? await c.step(command, threadID: t, granularity: granular ? "instruction" : nil, singleThread: singleThread)
    }

    public var testFailureFilter: String? {
        debugClient?.exceptionFilters.first { f in
            let text = (f.id + " " + f.label).lowercased()
            return text.contains("test") && text.contains("fail")
        }?.id
    }
}
