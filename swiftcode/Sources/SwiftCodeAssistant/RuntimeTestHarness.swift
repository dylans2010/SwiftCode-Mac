// STAGED PORT (verbatim extract) — SwiftCode-Legacy `SwiftCode/Backend/Assist/AssistRuntimeTestSuite.swift`
// (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/RuntimeTestHarness.swift`).
// SUPPORT PORT (not in any worklist): only the two shared result types the five staged
// in-app test suites return (RuntimeTestCaseResult / RuntimeTestSuiteReport), extracted
// verbatim from the 2138-line AssistRuntimeTestSuite.swift. The full AssistRuntimeTestSuite
// aggregator class itself is UNOWNED (no worklist covers it) and is NOT staged here — flag
// to the coordinator. No adaptations.
// UNRESOLVED DEPENDENCIES: none — self-contained (Foundation only).
// WIRING / REGISTRATION: shared harness types for the staged in-app suites; the full suite
// aggregator still needs an owner.

public struct RuntimeTestCaseResult: Codable, Sendable, Identifiable {
    public let id: UUID
    public let testName: String
    public let passed: Bool
    public let message: String
    public let duration: TimeInterval

    public init(id: UUID = UUID(), testName: String, passed: Bool, message: String, duration: TimeInterval) {
        self.id = id
        self.testName = testName
        self.passed = passed
        self.message = message
        self.duration = duration
    }
}

public struct RuntimeTestSuiteReport: Codable, Sendable {
    public let totalTests: Int
    public let passedTests: Int
    public let failedTests: Int
    public let results: [RuntimeTestCaseResult]
    public let totalDuration: TimeInterval

    public var allPassed: Bool {
        return failedTests == 0
    }
}
