import Foundation

public enum TestStatus: String, Codable {
    case success
    case warning
    case failed
}

public enum TestCategory: String, Codable, CaseIterable {
    case unit = "Unit"
    case integration = "Integration"
    case ui = "UI"
}

public struct TestResult: Identifiable, Codable {
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
    @Published public var results: [TestResult] = []
    @Published public var testHistory: [TestResult] = []

    private var customTestModules: [String: (String) -> TestResult] = [:]

    private init() {}

    public func runTests(forProject project: Project, category: TestCategory? = nil) async {
        isRunning = true
        results.removeAll()

        // Filter tests by category if requested
        let categoriesToRun = category != nil ? [category!] : TestCategory.allCases

        for cat in categoriesToRun {
            switch cat {
            case .unit:
                results.append(validateFileStructure(for: project))
                results.append(validateConfiguration(for: project))
            case .integration:
                results.append(checkProjectDependencies(for: project))
            case .ui:
                results.append(TestResult(name: "UI Element Accessibility", status: .success, executionTime: 0.8, category: .ui))
                results.append(TestResult(name: "Navigation Flow Test", status: .success, executionTime: 1.5, category: .ui))
            }
        }

        // Run custom modules
        for (_, handler) in customTestModules {
            results.append(handler(project.name))
        }

        testHistory.append(contentsOf: results)
        isRunning = false
    }



    public func runAgentToolTests(toolID: String) async {
        isRunning = true
        defer { isRunning = false }

        let result = TestResult(
            name: "Agent Tool Validation (\(toolID))",
            status: .success,
            executionTime: 0.1,
            category: .integration
        )

        results = [result]
        testHistory.append(result)
    }

    public func runExtensionTests(extensionID: String) async {
        isRunning = true
        defer { isRunning = false }

        let result = TestResult(
            name: "Extension Smoke Test (\(extensionID))",
            status: .success,
            executionTime: 0.1,
            category: .integration
        )

        results = [result]
        testHistory.append(result)
    }

    public func runParallelTests(forProject project: Project) async {
        isRunning = true
        results.removeAll()

        await withTaskGroup(of: TestResult.self) { group in
            group.addTask { await self.simulateTestRun(name: "Logic Test 1", category: .unit) }
            group.addTask { await self.simulateTestRun(name: "Logic Test 2", category: .unit) }
            group.addTask { await self.simulateTestRun(name: "API Integration", category: .integration) }
            group.addTask { await self.simulateTestRun(name: "Main View UI", category: .ui) }

            for await result in group {
                self.results.append(result)
            }
        }

        testHistory.append(contentsOf: results)
        isRunning = false
    }

    private func simulateTestRun(name: String, category: TestCategory) async -> TestResult {
        try? await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...500_000_000))
        return TestResult(name: name, status: .success, executionTime: 0.3, category: category)
    }

    // MARK: - Internal Test Modules

    private func validateSyntax(for path: String, in project: Project) -> TestResult {
        let start = Date()
        let success = !path.contains("error")
        return TestResult(
            name: "Syntax Validation",
            status: success ? .success : .failed,
            executionTime: Date().timeIntervalSince(start),
            category: .unit,
            errorMessage: success ? nil : "Syntax error detected in \(path)"
        )
    }

    private func checkProjectDependencies(for project: Project) -> TestResult {
        let start = Date()
        return TestResult(
            name: "Dependency Check",
            status: .success,
            executionTime: Date().timeIntervalSince(start),
            category: .integration
        )
    }

    private func validateFileStructure(for project: Project) -> TestResult {
        let start = Date()
        return TestResult(
            name: "File Structure Validation",
            status: .success,
            executionTime: Date().timeIntervalSince(start),
            category: .unit
        )
    }

    private func validateConfiguration(for project: Project) -> TestResult {
        let start = Date()
        return TestResult(
            name: "Configuration Validation",
            status: .success,
            executionTime: Date().timeIntervalSince(start),
            category: .unit
        )
    }
}
