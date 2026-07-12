import Foundation

public enum TestStatus: String, Codable, Sendable {
    case success
    case warning
    case failed
}

public enum TestCategory: String, Codable, CaseIterable, Sendable {
    case unit = "Unit"
    case integration = "Integration"
    case ui = "UI"
}

public struct TestResult: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let status: TestStatus
    public let executionTime: TimeInterval
    public let category: TestCategory
    public let errorMessage: String?
    public let timestamp: Date

    public init(name: String, status: TestStatus, executionTime: TimeInterval, category: TestCategory = .unit, errorMessage: String? = nil) {
        self.id = UUID()
        self.name = name
        self.status = status
        self.executionTime = executionTime
        self.category = category
        self.errorMessage = errorMessage
        self.timestamp = Date()
    }
}

@MainActor
public final class TestToolsManager: ObservableObject {
    public static let shared = TestToolsManager()

    @Published public var isRunning = false
    @Published public var consoleOutput = ""
    @Published public var results: [TestResult] = []
    @Published public var duration: TimeInterval = 0.0
    @Published public var passedCount = 0
    @Published public var failedCount = 0
    @Published public var skippedCount = 0

    private var process: Process?
    private var startTime: Date?
    private var timer: Timer?

    private init() {}

    public func runSwiftTests(forProject project: Project) async {
        guard !isRunning else { return }

        isRunning = true
        consoleOutput = "Starting swift test...\n"
        results.removeAll()
        passedCount = 0
        failedCount = 0
        skippedCount = 0
        duration = 0.0
        startTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            self.duration = Date().timeIntervalSince(start)
        }

        let process = Process()
        self.process = process
        process.currentDirectoryURL = project.directoryURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "test"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self?.consoleOutput.append(output)
                    self?.parseTestLogs(output)
                }
            }
        }

        do {
            try process.run()

            // Run on a cooperative detached task to wait without blocking
            try await Task.detached { [process] in
                process.waitUntilExit()
            }.value

            fileHandle.readabilityHandler = nil
            timer?.invalidate()
            timer = nil

            let exitCode = process.terminationStatus
            consoleOutput.append("\nProcess finished with exit code: \(exitCode)\n")

            if exitCode == 0 {
                consoleOutput.append("Tests completed successfully!\n")
            } else {
                consoleOutput.append("Tests failed.\n")
            }
        } catch {
            fileHandle.readabilityHandler = nil
            timer?.invalidate()
            timer = nil
            consoleOutput.append("\nError starting process: \(error.localizedDescription)\n")
        }

        isRunning = false
        self.process = nil
    }

    public func cancelTests() {
        process?.terminate()
        timer?.invalidate()
        timer = nil
        isRunning = false
        consoleOutput.append("\nTest execution cancelled by user.\n")
        self.process = nil
    }

    public func clearResults() {
        consoleOutput = ""
        results.removeAll()
        passedCount = 0
        failedCount = 0
        skippedCount = 0
        duration = 0.0
    }

    private func parseTestLogs(_ text: String) {
        let lines = text.split(separator: "\n")
        for line in lines {
            let lineStr = String(line)
            if lineStr.contains("passed") && lineStr.contains("Test Case") {
                passedCount += 1
                if let name = extractTestCaseName(lineStr) {
                    results.append(TestResult(name: name, status: .success, executionTime: 0.1, category: .unit))
                }
            } else if lineStr.contains("failed") && lineStr.contains("Test Case") {
                failedCount += 1
                if let name = extractTestCaseName(lineStr) {
                    results.append(TestResult(name: name, status: .failed, executionTime: 0.1, category: .unit, errorMessage: "Assertion failed"))
                }
            }
        }
    }

    private func extractTestCaseName(_ line: String) -> String? {
        let pattern = #"Test Case '-\[(.+)\]'"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = line as NSString
        if let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsString.length)) {
            return nsString.substring(with: match.range(at: 1))
        }
        return nil
    }
}
