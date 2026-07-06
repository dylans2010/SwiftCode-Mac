import SwiftUI

struct TestsSidebarView: View {
    @State private var testGroups: [TestGroup] = []
    @State private var isRunningTests = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.1))
            }

            List {
                ForEach(testGroups) { group in
                    Section(group.name) {
                        ForEach(group.tests) { test in
                            HStack {
                                Image(systemName: test.status.iconName)
                                    .foregroundColor(test.status.color)
                                Text(test.name)
                                Spacer()
                                if let duration = test.duration {
                                    Text("\(String(format: "%.2fs", duration))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                if testGroups.isEmpty && !isRunningTests {
                    ContentUnavailableView("No Tests Discovered", systemImage: "checklist", description: Text("Click the refresh button to discover tests in your project."))
                }
            }

            Divider()

            HStack {
                Button(action: runAllTests) {
                    if isRunningTests {
                        ProgressView().controlSize(.small)
                        Text("Running...")
                    } else {
                        Label("Run All Tests", systemImage: "play.fill")
                    }
                }
                .disabled(isRunningTests)
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(action: discoverTests) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isRunningTests)
            }
            .padding()
        }
        .onAppear {
            discoverTests()
        }
    }

    private func discoverTests() {
        statusMessage = "Discovering tests..."
        Task {
            let projectRoot = FileManager.default.currentDirectoryPath
            let tool = ExecuteTerminalCommandTool()
            do {
                let result = try await tool.run(command: "swift test --list-tests", workingDirectory: projectRoot)
                if result.exitCode == 0 {
                    let lines = result.stdout.components(separatedBy: .newlines).filter { !$0.contains("Listing tests") && !$0.isEmpty }
                    var groups: [String: [TestItem]] = [:]
                    for line in lines {
                        let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "/")
                        guard parts.count == 2 else { continue }
                        let groupName = parts[0]
                        let testName = parts[1]
                        groups[groupName, default: []].append(TestItem(name: testName))
                    }
                    testGroups = groups.map { TestGroup(name: $0.key, tests: $0.value) }.sorted(by: { $0.name < $1.name })
                    statusMessage = "Discovered \(lines.count) tests."
                } else {
                    statusMessage = "Discovery failed: \(result.stderr)"
                }
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func runAllTests() {
        isRunningTests = true
        statusMessage = "Running tests..."
        let startTime = Date()

        Task {
            let projectRoot = FileManager.default.currentDirectoryPath
            let tool = RunTestsTool()
            do {
                let output = try await tool.run(projectPath: projectRoot)
                let totalDuration = Date().timeIntervalSince(startTime)

                // Robust parsing: check for XCTest failure patterns
                let failureCount = parseFailureCount(from: output)
                let success = failureCount == 0 && output.contains("Test Case")

                let testCount = testGroups.reduce(0) { $0 + $1.tests.count }
                let durationPerTest = testCount > 0 ? totalDuration / Double(testCount) : 0

                for i in testGroups.indices {
                    for j in testGroups[i].tests.indices {
                        // In a production app, we'd map output to specific tests
                        // For now we use the overall result but calculate real average duration
                        testGroups[i].tests[j].status = success ? .passed : .failed
                        testGroups[i].tests[j].duration = durationPerTest
                    }
                }
                statusMessage = success ? "All tests passed in \(String(format: "%.2fs", totalDuration))." : "Tests failed. Found \(failureCount) failures."
            } catch {
                statusMessage = "Execution failed: \(error.localizedDescription)"
            }
            isRunningTests = false
        }
    }

    private func parseFailureCount(from output: String) -> Int {
        // Look for "failed" or "failed with" followed by numbers
        let regex = try? NSRegularExpression(pattern: "failed with (\\d+) failure", options: .caseInsensitive)
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        if let match = regex?.firstMatch(in: output, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: output),
           let count = Int(output[range]) {
            return count
        }
        return output.contains("failed") ? 1 : 0
    }
}

struct TestGroup: Identifiable {
    let id = UUID()
    let name: String
    var tests: [TestItem]
}

struct TestItem: Identifiable {
    let id = UUID()
    let name: String
    var status: SidebarTestStatus = .notRun
    var duration: Double?
}

enum SidebarTestStatus {
    case notRun, passed, failed, running

    var iconName: String {
        switch self {
        case .notRun: return "circle"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .notRun: return .secondary
        case .passed: return .green
        case .failed: return .red
        case .running: return .blue
        }
    }
}
