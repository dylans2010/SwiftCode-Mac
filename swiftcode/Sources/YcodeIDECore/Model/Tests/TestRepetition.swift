import Foundation
import YcodeBuild

public struct TestRepetition: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case fixed = "Fixed Iterations"
        case untilFailure = "Until Failure"
        case retryOnFailure = "Retry on Failure"
    }

    public var mode: Mode
    public var maximum: Int

    public init(_ mode: Mode, maximum: Int) {
        self.mode = mode
        self.maximum = max(1, maximum)
    }

    public static let defaultMaximum = 100

    public func next(after n: Int, outcomes: [TestOutcome], selection: [DiscoveredTest], discovered: [DiscoveredTest]) -> [DiscoveredTest]? {
        guard n < maximum else { return nil }
        let failed = outcomes.contains { $0.status == .failed }
        switch mode {
        case .fixed: return selection
        case .untilFailure: return failed ? nil : selection
        case .retryOnFailure:
            guard failed else { return nil }
            let pool = selection.isEmpty ? discovered : selection
            let retry = pool.filter { t in outcomes.contains { $0.status == .failed && t.matches($0) } }
            return retry.isEmpty ? selection : retry
        }
    }

    public static func summary(iterations: Int, failedIterations: Int, mode: Mode) -> String {
        let runs = iterations == 1 ? "1 iteration" : "\(iterations) iterations"
        let fails = failedIterations == 0 ? "no failures" : (failedIterations == 1 ? "1 with failures" : "\(failedIterations) with failures")
        return "SwiftCode: \(mode.rawValue): \(runs), \(fails)."
    }
}
