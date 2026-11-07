import Foundation

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
