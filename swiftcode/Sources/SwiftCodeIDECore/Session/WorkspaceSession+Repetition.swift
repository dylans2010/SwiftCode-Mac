import Foundation
import SwiftCodeBuild

extension WorkspaceSession {
    public struct RepetitionResult: Equatable, Sendable {
        public var iterations: [[DiscoveredTest]]
        public var failedIterations: Int
    }

    @discardableResult
    public func runTestsRepeatedly(only: [DiscoveredTest] = [], repetition: TestRepetition) async -> RepetitionResult {
        var result = RepetitionResult(iterations: [], failedIterations: 0)
        var next: [DiscoveredTest]? = only
        repetitionCancelled = false
        while let tests = next, !repetitionCancelled {
            result.iterations.append(tests)
            let all = await runTests(only: tests)
            let outcomes = tests.isEmpty ? all : all.filter { o in tests.contains { $0.matches(o) } }
            if outcomes.contains(where: { $0.status == .failed }) { result.failedIterations += 1 }
            next = repetition.next(after: result.iterations.count, outcomes: outcomes, selection: tests, discovered: self.tests)
        }
        appendConsole(TestRepetition.summary(iterations: result.iterations.count, failedIterations: result.failedIterations, mode: repetition.mode) + "\n",
                      kind: .debugger)
        return result
    }

    public func cancelRepetition() { repetitionCancelled = true }
}
