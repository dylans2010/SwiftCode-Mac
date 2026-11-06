import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

/// The ported Legacy test-running / coverage tools (Wave 6, slice A),
/// each driven black-box through the server's real write-policy path
/// against a copy of `Samples/AgentSamples/Greeter`.
///
/// Behaviour source: Legacy `AssistTestRunSingleTool`,
/// `AssistXctestDiscoveryTool`, `AssistTestLogParseTool`,
/// `AssistTestFlakyDetectTool`, `AssistTestCoverageReportTool`,
/// `AssistTestCoverageReporterTool`, `AssistTestDataFactoryTool`,
/// `AssistTestSnapshotManageTool`, `AssistTestTargetAddTool`,
/// `AssistUITestScaffoldTool`, `AssistInterfaceSimulatorTool`,
/// `AssistPreflightChecksTool`, `AssistPerformanceBenchmarkTool`,
/// `AssistCompilerDiagnosticsEngine`, `AssistCrashLogParseTool` and
/// `AssistRuntimeDiagnosticsEngine` (Dylan's own code, ported under
/// MIT).
///
/// Assertions are on the tool RESULT (message + on-disk state), never
/// on internals. Messages quoted verbatim are Legacy's. Message
/// assertions use `firstText`, never an exact `resultText ==`
/// (structured results emit two text blocks). Tests that run the
/// real build/test seam are gated on `canBuildPackages`, like the
/// `test` tool's own tests; nothing here claims a build passed
/// without running one.
@MainActor
@Suite(.serialized) struct SwiftCodeTestingToolsTests {
    /// The 16 Wave 6 slice A tool IDs, verified live from each
    /// Legacy tool file's `id`.
    static let sliceAIDs = ["test_run_single", "xctest_discovery", "test_log_parse", "test_flaky_detect",
                            "test_coverage_report", "test_coverage_reporter", "test_data_factory", "test_snapshot_manage",
                            "test_target_add", "ui_test_scaffold", "interface_simulator", "preflight_checks",
                            "performance_benchmark", "compiler_diagnostics_engine", "crash_log_parse", "runtime_diagnostics_engine"]

    /// Opens a copy of Greeter and installs the ported testing tools
    /// on the server (same shape as Wave 2's `opened`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.testingTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.testingTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.testingTools.map(\.name) == Self.sliceAIDs)
        for id in Self.sliceAIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
        // The slice's only Legacy alias, `test_coverage` →
        // `test_coverage_reporter` (registry alias table), lives in
        // `MCPServer.toolAliases`, which the coordinator owns — it is
        // reported as a wiring fragment instead of asserted here.
    }

    // MARK: - Pure reads: logs, crashes, interface, preflight

    @Test func testLogParseCountsAndListsFailures() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Tests/run.log", """
        Test Case '-[MyTests.MyTest testExample]' passed (0.001 seconds).
        Test Case '-[MyTests.MyTest testBroken]' failed (0.002 seconds).
        Test Suite 'MyTest' failed at 2026-01-01 00:00:00.
        Test Suite 'MyTest' passed at 2026-01-01 00:00:00.
        /Sources/File.swift:12: error: something broke
        """)
        let r = try await host.server.callTool("test_log_parse", ["logPath": .string("Tests/run.log")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["total"] == 2 && r.structured?["passed"] == 1 && r.structured?["failed"] == 1)
        #expect(r.structured?["errorCount"] == 1)
        #expect(r.structured?["failedTests"] == "-[MyTests.MyTest testBroken]")
        #expect(r.firstText.contains("Test log 'Tests/run.log': 2 test case(s), 1 passed, 1 failed, 1 error line(s)."))
        #expect(r.firstText.contains("Failed tests:"))
        #expect(r.firstText.contains("Suite summaries:"))
        let missing = try await host.server.callTool("test_log_parse", ["logPath": .string("Tests/nope.log")])
        #expect(missing.isToolError && missing.firstText.contains("Log file not found at 'Tests/nope.log'."))
        let noParam = try await host.server.callTool("test_log_parse")
        #expect(noParam.isToolError)
        let outside = try await host.server.callTool("test_log_parse", ["logPath": .string("../outside.log")])
        #expect(outside.isToolError && outside.firstText.contains("must be inside the workspace"))
    }

    @Test func testFlakyDetectFindsMixedOutcomes() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Logs/run1.log", """
        Test Case '-[MyTests.MyTest testA]' passed (0.001 seconds).
        Test Case '-[MyTests.MyTest testB]' passed (0.001 seconds).
        """)
        try writeFixture(sample, "Logs/run2.log", """
        Test Case '-[MyTests.MyTest testA]' failed (0.002 seconds).
        Test Case '-[MyTests.MyTest testB]' passed (0.001 seconds).
        """)
        let byDir = try await host.server.callTool("test_flaky_detect", ["logsDir": .string("Logs")])
        #expect(!byDir.isToolError, "\(byDir.resultText)")
        #expect(byDir.structured?["filesRead"] == 2 && byDir.structured?["flakyCount"] == 1)
        #expect(byDir.structured?["flakyTests"] == "-[MyTests.MyTest testA]")
        #expect(byDir.firstText.contains("2 distinct tests observed, 1 flaky."))
        #expect(byDir.firstText.contains("1 pass, 1 fail"))
        let byFile = try await host.server.callTool("test_flaky_detect", ["logPath": .string("Logs/run1.log")])
        #expect(!byFile.isToolError && byFile.structured?["flakyCount"] == 0)
        #expect(byFile.firstText.contains("No test showed both a pass and a fail."))
        let neither = try await host.server.callTool("test_flaky_detect")
        #expect(neither.isToolError && neither.firstText.contains("Provide logPath or logsDir."))
        let emptyDir = try await host.server.callTool("test_flaky_detect", ["logsDir": .string("Sources")])
        #expect(emptyDir.isToolError && emptyDir.firstText.contains("No .log or .txt files found"))
    }

    @Test func xctestDiscoveryInventoriesGreeter() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("xctest_discovery")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["classCount"] == 1 && r.structured?["testCount"] == 2)
        #expect(r.firstText.contains("XCTest inventory: 1 test classes, 2 test methods:"))
        #expect(r.firstText.contains("- GreeterTests — Tests/GreeterTests/GreeterTests.swift (2 tests)"))
    }

    @Test func preflightChecksReportSevenChecks() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("preflight_checks")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["checkCount"] == 7)
        #expect(r.firstText.contains("Preflight checks:"))
        #expect(r.firstText.contains("Workspace writable"))
        #expect(r.firstText.contains("xcodebuild available"))
        #expect(r.firstText.contains("Free disk"))
        #expect(r.firstText.contains("Result: "))
        // On this Linux host there is no xcodebuild, so at least one
        // check honestly fails; the count itself is what matters.
        #expect((r.structured?["failureCount"]?.int ?? 0) >= 1)
    }

    @Test func interfaceSimulatorAuditsAView() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/ContentView.swift", """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button("Tap") { }
                        .accessibilityIdentifier("tap")
                    Button("Other") { }
                    Image(systemName: "star")
                    Text("Hello")
                    List { Text("Row") }
                }
                .navigationTitle("Title")
            }
        }
        """)
        let r = try await host.server.callTool("interface_simulator", ["viewPath": .string("Sources/ContentView.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Buttons: 2 (1 have accessibility tags or labels)"))
        #expect(r.firstText.contains("Images: 1"))
        #expect(r.firstText.contains("Text Labels: 2"))
        #expect(r.firstText.contains("Lists/ScrollViews: 1"))
        #expect(r.firstText.contains("Navigation Title Configured: Yes"))
        #expect(r.firstText.contains("Accessibility Identifier Coverage: 50%"))
        #expect(r.firstText.contains("Recommendations:"))
        try writeFixture(sample, "Sources/Plain.swift", "struct Plain { let x = 1 }\n")
        let notAView = try await host.server.callTool("interface_simulator", ["viewPath": .string("Sources/Plain.swift")])
        #expect(notAView.isToolError && notAView.firstText.contains("does not appear to contain a SwiftUI View implementation"))
        let missing = try await host.server.callTool("interface_simulator", ["viewPath": .string("Sources/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("File does not exist: Sources/Nope.swift"))
    }

    @Test func crashLogParseReadsTextAndJSON() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Logs/crash.crash", """
        Incident Identifier: ABC
        Exception Type: EXC_BAD_ACCESS (SIGSEGV)
        Termination Reason: Namespace SIGNAL, Code 11
        Triggered by Thread: 0
        Thread 0 Crashed:
        0   MyApp  0x0000000100000000 main + 0
        1   MyApp  0x0000000100000010 foo + 16
        2   libsystem  0x00000001a0000000 bar + 4
        Thread 1:
        0   libsystem  0x00000001a0000010 baz + 8
        """)
        let r = try await host.server.callTool("crash_log_parse", ["path": .string("Logs/crash.crash")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["hasException"] == true && r.structured?["frameCount"] == 3)
        #expect(r.firstText.contains("Exception Type: EXC_BAD_ACCESS (SIGSEGV)"))
        #expect(r.firstText.contains("Top blamed frames:"))
        try writeFixture(sample, "Logs/crash.ips", "{\"exception\": {\"type\": \"EXC_CRASH\"}, \"termination\": {\"reason\": \"Namespace X\"}}")
        let json = try await host.server.callTool("crash_log_parse", ["path": .string("Logs/crash.ips")])
        #expect(!json.isToolError && json.firstText.contains("Exception Type: EXC_CRASH"))
        try writeFixture(sample, "Logs/plain.txt", "hello world\nnothing to see\n")
        let garbage = try await host.server.callTool("crash_log_parse", ["path": .string("Logs/plain.txt")])
        #expect(garbage.isToolError && garbage.firstText.contains("No crash metadata recognized"))
        let missing = try await host.server.callTool("crash_log_parse", ["path": .string("Logs/nope.crash")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read crash log at: Logs/nope.crash"))
    }

    @Test func runtimeDiagnosticsCountsCrashesAndThreads() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Logs/runtime.log", """
        2026-01-01 fatal error: unexpectedly found nil
        2026-01-01 thread 2 queue com.apple.main-thread: something
        2026-01-01 normal line
        """)
        let r = try await host.server.callTool("runtime_diagnostics_engine", ["logPath": .string("Logs/runtime.log")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["crash_count"] == 1 && r.structured?["thread_anomaly_count"] == 1)
        #expect(r.firstText.contains("Runtime diagnostics complete."))
        #expect(r.structured?["suggestions"]?.string?.contains("guards around nil-sensitive code paths") == true)
        #expect(r.structured?["suggestions"]?.string?.contains("actor/queue confinement") == true)
        try writeFixture(sample, "Logs/clean.log", "all good\nnothing here\n")
        let clean = try await host.server.callTool("runtime_diagnostics_engine", ["logPath": .string("Logs/clean.log")])
        #expect(!clean.isToolError && clean.structured?["crash_count"] == 0)
        #expect(clean.structured?["suggestions"]?.string?.contains("No critical anomalies detected") == true)
        let missing = try await host.server.callTool("runtime_diagnostics_engine", ["logPath": .string("Logs/nope.log")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read log at: Logs/nope.log"))
        let noParam = try await host.server.callTool("runtime_diagnostics_engine")
        #expect(noParam.isToolError)
    }

    // MARK: - Execution: benchmark + coverage reporter

    @Test func performanceBenchmarkRunsAllowListedCommand() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("performance_benchmark",
                                              ["command": .string("/bin/ls"), "arguments": .string("-la"), "iterations": .string("1")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["executable"] == "/bin/ls" && r.structured?["iterations"] == 1)
        #expect(r.structured?["exitCodes"]?.array?.first == 0)
        #expect(r.firstText.contains("Benchmark '/bin/ls -la' over 1 run(s):"))
        #expect(r.firstText.contains("Last run output tail:"))
        let clamped = try await host.server.callTool("performance_benchmark",
                                                    ["command": .string("/bin/ls"), "iterations": .string("99")])
        #expect(!clamped.isToolError && clamped.structured?["iterations"] == 10)
        let denied = try await host.server.callTool("performance_benchmark", ["command": .string("/bin/echo hi")])
        #expect(denied.isToolError && denied.firstText.contains("is not in the allow-list"))
        let unsafe = try await host.server.callTool("performance_benchmark",
                                                   ["command": .string("/bin/ls"), "arguments": .string("a;b")])
        #expect(unsafe.isToolError && unsafe.firstText.contains("contains characters that are not allowed"))
        let badIterations = try await host.server.callTool("performance_benchmark",
                                                          ["command": .string("/bin/ls"), "iterations": .string("0")])
        #expect(badIterations.isToolError && badIterations.firstText.contains("iterations must be an integer of at least 1."))
        let missing = try await host.server.callTool("performance_benchmark", ["command": .string("/bin/nope")])
        #expect(missing.isToolError && missing.firstText.contains("is not in the allow-list"))
    }

    @Test func coverageReporterHandlesMissingReport() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // An explicit path that does not exist: Legacy answers success
        // with the "no report" message, not a failure.
        let missing = try await host.server.callTool("test_coverage_reporter", ["reportPath": .string("Nope.xccovreport")])
        #expect(!missing.isToolError, "\(missing.resultText)")
        #expect(missing.firstText.contains("No active .xccovreport or coverage archive found in DerivedData."))
        // A report file that does exist needs xcrun: present on macOS,
        // absent here. Either way the tool must not invent coverage.
        try writeFixture(sample, "Fake.xccovreport", "")
        let fake = try await host.server.callTool("test_coverage_reporter", ["reportPath": .string("Fake.xccovreport")])
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") {
            #expect(!fake.isToolError, "\(fake.resultText)")
        } else {
            #expect(fake.isToolError && fake.firstText.contains("Failed to execute xccov"))
        }
        // No argument at all: success on either outcome (no DerivedData
        // report here, a real xccov report on a Mac with one).
        let def = try await host.server.callTool("test_coverage_reporter")
        #expect(!def.isToolError, "\(def.resultText)")
        #expect(def.firstText.contains("No active .xccovreport") || def.firstText.contains("Test Coverage Report"))
    }

    // MARK: - Writes: fixtures, scaffolds, snapshots, targets

    @Test func writesAreRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .readOnly)
        let factory = try await host.server.callTool("test_data_factory", ["name": .string("User")])
        #expect(factory.isToolError && factory.firstText.contains("read-only"))
        #expect(!exists(sample, "TestData/User.json"))
        let snaps = try await host.server.callTool("test_snapshot_manage", ["action": .string("list")])
        #expect(snaps.isToolError && snaps.firstText.contains("read-only"))
    }

    @Test func testDataFactoryWritesJSONAndSwift() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let json = try await host.server.callTool("test_data_factory", ["name": .string("User")])
        #expect(!json.isToolError, "\(json.resultText)")
        #expect(json.structured?["path"] == "TestData/User.json" && json.structured?["kind"] == "json")
        #expect(exists(sample, "TestData/User.json"))
        #expect(sample.read("TestData/User.json").contains("\"id\": 1"))
        #expect(sample.read("TestData/User.json").contains("\"name\": \"Sample name\""))
        let again = try await host.server.callTool("test_data_factory", ["name": .string("User")])
        #expect(again.isToolError && again.firstText.contains("File already exists at 'TestData/User.json'. Pass overwrite='true' to replace it."))
        let over = try await host.server.callTool("test_data_factory", ["name": .string("User"), "overwrite": .string("true")])
        #expect(!over.isToolError, "\(over.resultText)")
        let swift = try await host.server.callTool("test_data_factory",
                                                  ["name": .string("Order"), "kind": .string("swift"),
                                                   "fields": .string("id:Int,total:Double,paid:Bool")])
        #expect(!swift.isToolError, "\(swift.resultText)")
        #expect(sample.read("TestData/Order.swift").contains("struct Order {"))
        #expect(sample.read("TestData/Order.swift").contains("static let sample = Order("))
        #expect(sample.read("TestData/Order.swift").contains("total: 3.14"))
        let badKind = try await host.server.callTool("test_data_factory", ["name": .string("X"), "kind": .string("yaml")])
        #expect(badKind.isToolError && badKind.firstText.contains("kind must be 'json' or 'swift'."))
        let badField = try await host.server.callTool("test_data_factory", ["name": .string("X"), "fields": .string("9bad:Int")])
        #expect(badField.isToolError && badField.firstText.contains("is not a valid Swift identifier"))
        let badName = try await host.server.callTool("test_data_factory", ["name": .string("9User")])
        #expect(badName.isToolError && badName.firstText.contains("is not a valid Swift identifier"))
        let traversal = try await host.server.callTool("test_data_factory", ["name": .string("X"), "path": .string("../Outside/")])
        #expect(traversal.isToolError && traversal.firstText.contains("must be inside the workspace"))
    }

    @Test func uiTestScaffoldCreatesLaunchTest() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("ui_test_scaffold", ["testName": .string("LoginUITests")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["path"] == "UITests/LoginUITests.swift")
        #expect(exists(sample, "UITests/LoginUITests.swift"))
        let body = sample.read("UITests/LoginUITests.swift")
        #expect(body.contains("final class LoginUITests: XCTestCase {"))
        #expect(body.contains("app = XCUIApplication()"))
        #expect(body.contains("func testLaunch() throws {"))
        #expect(body.contains("override func tearDownWithError() throws {"))
        let again = try await host.server.callTool("ui_test_scaffold", ["testName": .string("LoginUITests")])
        #expect(again.isToolError && again.firstText.contains("File already exists at 'UITests/LoginUITests.swift'."))
        let over = try await host.server.callTool("ui_test_scaffold",
                                                 ["testName": .string("LoginUITests"), "targetApp": .string("com.example.App"),
                                                  "overwrite": .string("true")])
        #expect(!over.isToolError && sample.read("UITests/LoginUITests.swift").contains("XCUIApplication(bundleIdentifier: \"com.example.App\")"))
        let badName = try await host.server.callTool("ui_test_scaffold", ["testName": .string("has space")])
        #expect(badName.isToolError && badName.firstText.contains("is not a valid Swift identifier"))
    }

    @Test func snapshotManageListsAndCleansUnreferenced() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Tests/Snapshots/__Snapshots__/MyView.1.png", "png-bytes")
        try writeFixture(sample, "Tests/Snapshots/__Snapshots__/OtherView.png", "png-bytes")
        try writeFixture(sample, "Tests/Snapshots/Ref.swift", "import XCTest\n// assertSnapshot(of: MyView)\n")
        let list = try await host.server.callTool("test_snapshot_manage", ["action": .string("list")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.structured?["count"] == 2)
        #expect(list.firstText.contains("Snapshot references: 2 file(s)"))
        #expect(list.firstText.contains("OtherView.png"))
        let noConfirm = try await host.server.callTool("test_snapshot_manage", ["action": .string("clean")])
        #expect(noConfirm.isToolError && noConfirm.firstText.contains("clean requires confirm='true'. No files were deleted."))
        #expect(exists(sample, "Tests/Snapshots/__Snapshots__/OtherView.png"))
        let clean = try await host.server.callTool("test_snapshot_manage", ["action": .string("clean"), "confirm": .string("true")])
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.structured?["deletedCount"] == 1 && clean.structured?["keptCount"] == 1)
        #expect(clean.firstText.contains("Snapshot clean: deleted 1 unreferenced file(s), kept 1."))
        #expect(!exists(sample, "Tests/Snapshots/__Snapshots__/OtherView.png"))
        #expect(exists(sample, "Tests/Snapshots/__Snapshots__/MyView.1.png"))
        let badAction = try await host.server.callTool("test_snapshot_manage", ["action": .string("prune")])
        #expect(badAction.isToolError && badAction.firstText.contains("action must be 'list' or 'clean'."))
    }

    @Test func testTargetAddInsertsPbxprojTarget() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Fake.xcodeproj/project.pbxproj", """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjects = {
        /* Begin PBXNativeTarget section */
        /* End PBXNativeTarget section */
        /* Begin PBXFileReference section */
        /* End PBXFileReference section */
        /* Begin PBXSourcesBuildPhase section */
        /* End PBXSourcesBuildPhase section */
        /* Begin PBXFrameworksBuildPhase section */
        /* End PBXFrameworksBuildPhase section */
        /* Begin XCBuildConfigurationList section */
        /* End XCBuildConfigurationList section */
        /* Begin XCBuildConfiguration section */
        /* End XCBuildConfiguration section */
        \t};
        \trootObject = 000000000000000000000001 /* Project object */;
        \ttargets = (
        \t);
        }
        """)
        let r = try await host.server.callTool("test_target_add", ["targetName": .string("MyTests")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["targetName"] == "MyTests" && r.structured?["type"] == "unit")
        #expect(r.structured?["testFile"] == "MyTests/MyTestsTests.swift")
        #expect(exists(sample, "MyTests/MyTestsTests.swift"))
        #expect(sample.read("MyTests/MyTestsTests.swift").contains("final class MyTestsTests: XCTestCase {"))
        #expect(sample.read("MyTests/MyTestsTests.swift").contains("XCTAssertEqual(1 + 1, 2)"))
        let pbxproj = sample.read("Fake.xcodeproj/project.pbxproj")
        #expect(pbxproj.contains("name = MyTests;"))
        #expect(pbxproj.contains("isa = PBXNativeTarget;"))
        #expect(pbxproj.contains("com.apple.product-type.bundle.unit-test"))
        #expect(pbxproj.contains("MyTests.xctest"))
        let dup = try await host.server.callTool("test_target_add", ["targetName": .string("MyTests")])
        #expect(dup.isToolError && dup.firstText.contains("A target named 'MyTests' already exists in project.pbxproj."))
        let badType = try await host.server.callTool("test_target_add", ["targetName": .string("Other"), "type": .string("integration")])
        #expect(badType.isToolError && badType.firstText.contains("type must be 'unit' or 'ui'."))
    }

    @Test func testTargetAddRefusesPbxprojWithoutAnchors() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Fake.xcodeproj/project.pbxproj", "{ objects = {}; }\n")
        let r = try await host.server.callTool("test_target_add", ["targetName": .string("MyTests")])
        #expect(r.isToolError && r.firstText.contains("is missing required anchor"))
        #expect(!exists(sample, "MyTests/MyTestsTests.swift"), "a missing anchor must write nothing, including the test file")
    }

    @Test func testTargetAddFailsWithoutXcodeproj() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("test_target_add", ["targetName": .string("MyTests")])
        #expect(r.isToolError && r.firstText.contains("No .xcodeproj found in the workspace root."))
    }

    // MARK: - Real build/test seam (needs a Swift toolchain)

    @Test func testRunSingleRunsOneDiscoveredTest() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("test_run_single", ["testId": .string("GreeterTests/testSalutation")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["status"] == "Passed" && r.structured?["testId"] == "GreeterTests/testSalutation")
        #expect(r.structured?["passed"] == 1 && r.structured?["failed"] == 0)
        #expect(r.structured?["tests"]?[0]?["name"] == "testSalutation")
        #expect(r.firstText.contains("Single test GreeterTests/testSalutation — Passed"))
        let unknown = try await host.server.callTool("test_run_single", ["testId": .string("GreeterTests/testNope")])
        #expect(unknown.isToolError && unknown.firstText.contains("was found in the sources"))
        let invalid = try await host.server.callTool("test_run_single", ["testId": .string("bad id")])
        #expect(invalid.isToolError && invalid.firstText.contains("is not valid"))
        let badDestination = try await host.server.callTool("test_run_single",
                                                           ["testId": .string("GreeterTests/testSalutation"),
                                                            "destination": .string("platform=macOS; rm -rf /")])
        #expect(badDestination.isToolError && badDestination.firstText.contains("destination contains characters that are not allowed."))
        let missing = try await host.server.callTool("test_run_single")
        #expect(missing.isToolError)
    }

    @Test func testCoverageReportRunsSuite() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("test_coverage_report")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["status"] == "Passed" && r.structured?["passed"] == 2 && r.structured?["failed"] == 0)
        #expect(r.firstText.contains("Test Coverage — Greeter / Greeter: Passed"))
        // Coverage is reported only when the scheme gathers it; the
        // Greeter package scheme does not enable it, so the honest
        // outcome is the plain "no coverage gathered" message — but
        // the assertion does not depend on that default.
        #expect(r.structured?["coverage"]?.string != nil)
        #expect(r.firstText.contains("No coverage data was gathered for this run.") || r.firstText.contains("Coverage: "))
    }

    @Test func compilerDiagnosticsCollectsRealBuildIssues() async throws {
        guard canBuildPackages else { return }
        let broken = try TempSample(breaking: true)
        defer { broken.remove() }
        let host = try await opened(broken, policy: .allow)
        let failed = try await host.server.callTool("compiler_diagnostics_engine")
        #expect(!failed.isToolError, "\(failed.resultText)")
        #expect(failed.structured?["buildFailed"] == true && failed.structured?["exitCode"] == 1)
        #expect((failed.structured?["error_count"]?.int ?? 0) >= 1)
        #expect(failed.firstText.contains("Compiler diagnostics collected (build FAILED, exit code 1)."))
        #expect(failed.structured?["errors"]?.string?.contains("salutaton") == true)
        // The `project` argument must name the open workspace.
        let wrongProject = try await host.server.callTool("compiler_diagnostics_engine",
                                                         ["project": .string("Nope.xcodeproj")])
        #expect(wrongProject.isToolError && wrongProject.firstText.contains("is not the open workspace"))
        let good = try TempSample()
        defer { good.remove() }
        let host2 = try await opened(good, policy: .allow)
        let ok = try await host2.server.callTool("compiler_diagnostics_engine")
        #expect(!ok.isToolError, "\(ok.resultText)")
        #expect(ok.structured?["buildFailed"] == false && ok.structured?["exitCode"] == 0)
        #expect(ok.firstText.contains("Compiler diagnostics collected (build succeeded)."))
    }
}
