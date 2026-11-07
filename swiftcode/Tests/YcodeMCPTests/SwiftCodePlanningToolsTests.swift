import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodePlanningToolsTests {
    static let wave4IDs = ["execution_plan", "intel_autofix", "intel_breakdown_task", "intel_explain_code",
                           "intel_generate_tests", "intel_plan_task", "plan-AskUser", "report_to_user"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        host.server.tools += host.planningTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    @Test func toolsAreListedWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.planningTools
        #expect(tools.count == 8, "expected 8 Wave 4 tools, got \(tools.map(\.name))")
        #expect(tools.map(\.name).sorted() == Self.wave4IDs.sorted())
        let expectedRequired: [String: [String]] = [
            "execution_plan": ["objective", "mode"], "intel_plan_task": ["task"], "intel_breakdown_task": ["planId"],
            "intel_autofix": [], "intel_explain_code": ["path"], "intel_generate_tests": ["path"],
            "plan-AskUser": ["question", "allowsMultipleAnswers", "choices"], "report_to_user": ["summary"],
        ]
        for tool in tools {
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            switch tool.name {
            case "execution_plan", "intel_autofix", "intel_generate_tests":
                #expect(!tool.annotations.readOnly && tool.writes, "\(tool.name) must be a write tool")
                #expect(tool.annotations.idempotent, "\(tool.name) must be idempotent")
            default:
                #expect(tool.annotations.readOnly && !tool.writes, "\(tool.name) must be read-only")
            }
            #expect(!tool.annotations.destructive, "\(tool.name) must not be marked destructive")
        }
        let sample = try TempSample()
        defer { sample.remove() }
        let servedHost = try await opened(sample)
        let served = servedHost.server.tools.map(\.name)
        for id in Self.wave4IDs { #expect(served.contains(id), "\(id) is not installed on the server") }
        #expect(served.filter { $0 == "plan-AskUser" }.count == 1, "plan-AskUser must be served exactly once")
    }

    @Test func planTaskAndBreakdownRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let planned = try await host.server.callTool("intel_plan_task", ["task": .string("Add a farewell method, update the docs, run the tests")])
        #expect(!planned.isToolError, "\(planned.resultText)")
        let planId = planned.structured?["planId"]?.string
        #expect(planId != nil && !planId!.isEmpty)
        let steps = planned.structured?["steps"]?.string ?? ""
        #expect(steps.contains("1. Add a farewell method"))
        #expect(steps.contains("2. update the docs"))
        #expect(steps.contains("3. run the tests"))
        #expect(planned.resultText.hasPrefix("Plan generated for task: Add a farewell method, update the docs, run the tests"))

        let planned2 = try await host.server.callTool("intel_plan_task", ["task": .string("Something else")])
        #expect(planned2.structured?["planId"]?.string != planId)

        let broken = try await host.server.callTool("intel_breakdown_task", ["planId": .string(planId!)])
        #expect(!broken.isToolError, "\(broken.resultText)")
        let breakdown = broken.structured?["breakdown"]?.string ?? ""
        #expect(breakdown.contains("1. Add a farewell method"))
        #expect(breakdown.contains("- Define acceptance criteria for: 1. Add a farewell method"))
        #expect(breakdown.contains("- Implement and self-review: 1. Add a farewell method"))
        #expect(broken.resultText.hasPrefix("Task breakdown completed for plan \(planId!)"))

        let unknown = try await host.server.callTool("intel_breakdown_task", ["planId": .string("no-such-plan")])
        #expect(unknown.isToolError && unknown.firstText == "No stored plan found for planId: no-such-plan")

        let plain = try await host.server.callTool("intel_plan_task", ["task": .string("do the thing")])
        #expect(!plain.isToolError)
        #expect((plain.structured?["steps"]?.string ?? "").contains("1. do the thing"))
    }

    @Test func explainCodeIsHonestStaticAnalysis() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let explained = try await host.server.callTool("intel_explain_code", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(!explained.isToolError, "\(explained.resultText)")
        #expect(explained.resultText.hasPrefix("Static analysis for Sources/Greeter/Greeter.swift"))
        let explanation = explained.structured?["explanation"]?.string ?? ""
        #expect(explanation.contains("Static analysis of Sources/Greeter/Greeter.swift"))
        #expect(explanation.contains("no LLM explanation is available"))
        #expect(explanation.contains("struct Greeter"))
        #expect(explanation.contains("greeting"))
        #expect(explanation.contains("Lines: "))

        let missing = try await host.server.callTool("intel_explain_code", ["path": .string("Sources/Greeter/Nope.swift")])
        #expect(missing.isToolError && missing.resultText.contains("Failed to explain Sources/Greeter/Nope.swift"))
    }

    @Test func generateTestsWritesStubsThroughTheGate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let generated = try await host.server.callTool("intel_generate_tests", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(!generated.isToolError, "\(generated.resultText)")
        #expect(generated.resultText.hasPrefix("Tests generated for Sources/Greeter/Greeter.swift with 2 test methods"))
        #expect(generated.structured?["test_path"]?.string == "Tests/GreeterTests.swift")
        #expect(generated.structured?["test_count"]?.int == 2)
        #expect(generated.structured?["types_count"]?.int == 1)
        #expect(generated.structured?["functions_count"]?.int == 1)
        let stub = sample.read("Tests/GreeterTests.swift")
        #expect(stub.contains("import XCTest"))
        #expect(stub.contains("@testable import Greeter"), "module is derived from Sources/<Module>, not Legacy's hardcoded SwiftCode")
        #expect(stub.contains("final class GreeterTests: XCTestCase"))
        #expect(stub.contains("func testGreeter_Initialization()"))
        #expect(stub.contains("func test_greeting()"))
        #expect(stub.contains("func testPerformance()"))
        #expect(stub.contains("TODO: Test greeting behavior"))

        let custom = try await host.server.callTool("intel_generate_tests",
                                                    ["path": .string("Sources/Greeter/Greeter.swift"),
                                                     "testPath": .string("Tests/CustomTests.swift")])
        #expect(!custom.isToolError, "\(custom.resultText)")
        #expect(exists(sample, "Tests/CustomTests.swift"))

        let refusedSample = try TempSample()
        defer { refusedSample.remove() }
        let refusedHost = try await opened(refusedSample, policy: .readOnly)
        let refused = try await refusedHost.server.callTool("intel_generate_tests", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(refused.isToolError && refused.resultText.contains("read-only"))
        #expect(!exists(refusedSample, "Tests/GreeterTests.swift"))

        let missing = try await host.server.callTool("intel_generate_tests", ["path": .string("Sources/Greeter/Nope.swift")])
        #expect(missing.isToolError && missing.resultText.contains("Failed generating tests for Sources/Greeter/Nope.swift"))
    }

    @Test func autoFixAlwaysFailsHonestlyAndWritesNothing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let before = sample.read("Sources/Greeter/Greeter.swift")
        let fixed = try await host.server.callTool("intel_autofix", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(fixed.isToolError)
        #expect(fixed.resultText.contains("LLM"), "the failure must name the missing LLM provider")
        #expect(fixed.resultText.contains("lint"), "the failure must name the missing lint diagnostics")
        #expect(sample.read("Sources/Greeter/Greeter.swift") == before, "nothing was changed")
        #expect(!exists(sample, "Tests/GreeterTests.swift"))
    }

    @Test func executionPlanWritesAgentNotesThroughTheGate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let planned = try await host.server.callTool("execution_plan",
                                                     ["objective": .string("Add a farewell method to Greeter"),
                                                      "mode": .string("plan"),
                                                      "relevantFiles": .array([.string("Sources/Greeter/Greeter.swift")])])
        #expect(!planned.isToolError, "\(planned.resultText)")
        #expect(planned.resultText.contains("Execution Plan generated for: Add a farewell method to Greeter"))
        #expect(planned.resultText.contains("Mode: Plan"))
        #expect(planned.resultText.contains("Plan written to: agent_notes.md"))
        #expect(planned.structured?["planFile"]?.string == "agent_notes.md")
        #expect(planned.structured?["mode"]?.string == "Plan")
        #expect(planned.structured?["stepCount"]?.int == 4, "read + search + build (Package.swift) + test")
        #expect(planned.structured?["relevantFileCount"]?.int == 4)
        #expect(planned.structured?["workerCount"]?.int == 0)
        let notes = sample.read("agent_notes.md")
        #expect(notes.contains("# Execution Plan"))
        #expect(notes.contains("## Objective\nAdd a farewell method to Greeter"))
        #expect(notes.contains("## Execution Mode\nPlan"))
        #expect(notes.contains("## Relevant Files"))
        #expect(notes.contains("- Sources/Greeter/Greeter.swift"))
        #expect(notes.contains("- Tests/GreeterTests/GreeterTests.swift"))
        #expect(notes.contains("### Step 1: Read all relevant files to understand current implementation"))
        #expect(notes.contains("- Tool: `file_read`"))
        #expect(notes.contains("- Tool: `search_text`"))
        #expect(notes.contains("- Tool: `project_build`"))
        #expect(notes.contains("- Tool: `project_test`"))
        #expect(notes.contains("## Verification Requirements"))
        #expect(notes.contains("- Build must pass: swift build"))
        #expect(notes.contains("## Completion Criteria"))
        #expect(notes.contains("- [ ] Project builds without errors"))
        #expect(notes.contains("- [ ] All tests pass"))
        #expect(notes.contains("- [ ] User decisions incorporated into plan"), "Plan mode adds the user-decisions criterion")
        #expect(notes.contains("*Plan generated by execution_plan tool."))

        let auto = try await host.server.callTool("execution_plan",
                                                  ["objective": .string("Add a farewell method to Greeter"),
                                                   "mode": .string("autopilot")])
        #expect(!auto.isToolError, "\(auto.resultText)")
        #expect(auto.structured?["mode"]?.string == "Autopilot")
        #expect(!sample.read("agent_notes.md").contains("User decisions incorporated into plan"))

        let lower = try await host.server.callTool("execution_plan",
                                                   ["objective": .string("Add a farewell method to Greeter"),
                                                    "mode": .string("plan")])
        #expect(lower.structured?["mode"]?.string == "Plan")

        let refusedSample = try TempSample()
        defer { refusedSample.remove() }
        let refusedHost = try await opened(refusedSample, policy: .readOnly)
        let refused = try await refusedHost.server.callTool("execution_plan",
                                                            ["objective": .string("Add a farewell method to Greeter"),
                                                             "mode": .string("plan")])
        #expect(refused.isToolError && refused.resultText.contains("read-only"))
        #expect(!exists(refusedSample, "agent_notes.md"))

        let missing = try await host.server.callTool("execution_plan", ["mode": .string("plan")])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"objective\""))
    }

    @Test func askUserReturnsAPendingHandoffAndNeverWaits() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let asked = try await host.server.callTool("plan-AskUser",
                                                   ["question": .string("Which persistence layer should the feature use?"),
                                                    "allowsMultipleAnswers": .bool(false),
                                                    "choices": .array([
                                                        .object(["choice": .string("SwiftData"), "assistRecommended": .bool(true)]),
                                                        .object(["choice": .string("SQLite"), "assistRecommended": .bool(false)]),
                                                    ]),
                                                    "userSpecification": .bool(false)])
        #expect(!asked.isToolError, "\(asked.resultText)")
        let questionId = asked.structured?["questionId"]?.string
        #expect(questionId != nil && !questionId!.isEmpty)
        #expect(asked.structured?["status"]?.string == "pending", "no answer exists yet — the caller must present the question")
        #expect(asked.structured?["question"]?.string == "Which persistence layer should the feature use?")
        #expect(asked.structured?["allowsMultipleAnswers"]?.bool == false)
        #expect(asked.structured?["userSpecification"]?.bool == false)
        let choices = asked.structured?["choices"]?.array ?? []
        #expect(choices.count == 2)
        #expect(choices[0]["choice"]?.string == "SwiftData")
        #expect(choices[0]["assistRecommended"]?.bool == true)
        #expect(choices[1]["choice"]?.string == "SQLite")
        #expect(asked.resultText.contains("Which persistence layer should the feature use?"))
        #expect(asked.resultText.contains("SwiftData (recommended)"))
        #expect(asked.resultText.contains("does not wait for an answer"))

        let freeform = try await host.server.callTool("plan-AskUser",
                                                      ["question": .string("What should the feature be called?"),
                                                       "allowsMultipleAnswers": .bool(false),
                                                       "choices": .array([]),
                                                       "userSpecification": .bool(true)])
        #expect(!freeform.isToolError, "\(freeform.resultText)")
        #expect(freeform.resultText.contains("free-form answer"))

        let noChoices = try await host.server.callTool("plan-AskUser",
                                                       ["question": .string("Pick one."),
                                                        "allowsMultipleAnswers": .bool(false),
                                                        "choices": .array([]),
                                                        "userSpecification": .bool(false)])
        #expect(noChoices.isToolError && noChoices.firstText == "At least one choice is required when userSpecification is false.")

        let empty = try await host.server.callTool("plan-AskUser",
                                                   ["question": .string(""),
                                                    "allowsMultipleAnswers": .bool(false),
                                                    "choices": .array([.object(["choice": .string("A"), "assistRecommended": .bool(false)])]),
                                                    "userSpecification": .bool(false)])
        #expect(empty.isToolError && empty.resultText.contains("Missing required argument: 'question'"))
    }

    @Test func reportToUserNormalizesMarkdown() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let reported = try await host.server.callTool("report_to_user",
                                                      ["summary": .string("Done \\*all\\* of it. Want me to apply the fixes?"),
                                                       "status": .string("verified"),
                                                       "filesModified": .array([.string("Sources/Greeter/Greeter.swift"),
                                                                                .string("Tests/GreeterTests.swift")]),
                                                       "verification": .string("swift build: clean. swift test: 3 passed.")])
        #expect(!reported.isToolError, "\(reported.resultText)")
        #expect(reported.structured?["status"]?.string == "verified")
        #expect(reported.structured?["filesCount"]?.int == 2)
        #expect(reported.structured?["renderedLength"]?.int == (reported["content"]?.array?.first?["text"]?.string?.count ?? -1), "renderedLength is the length of the report text (first block), not of the whole result")
        #expect(reported.resultText.contains("Done *all* of it."), "escaped asterisks are un-escaped")
        #expect(!reported.resultText.contains("Want me to apply the fixes?"), "trailing prompt question is stripped")
        #expect(!reported.resultText.contains("\\*"))
        #expect(reported.resultText.contains("**Modified Files:**"))
        #expect(reported.resultText.contains("- `Sources/Greeter/Greeter.swift`"))
        #expect(reported.resultText.contains("- `Tests/GreeterTests.swift`"))
        #expect(reported.resultText.contains("**Verification:**\nswift build: clean. swift test: 3 passed."))

        let wrapped = try await host.server.callTool("report_to_user",
                                                     ["summary": .string("```json\n{\"summary\": \"Wrapped report.\"}\n```")])
        #expect(!wrapped.isToolError, "\(wrapped.resultText)")
        #expect(wrapped.resultText.hasPrefix("Wrapped report."))
        #expect(!wrapped.resultText.contains("```json"))
        #expect(wrapped.structured?["status"]?.string == "completed", "status defaults to completed")

        let leaked = try await host.server.callTool("report_to_user",
                                                    ["summary": .string("Fixed via use_workers in a batch.")])
        #expect(leaked.resultText.contains("parallel workers"))
        #expect(!leaked.resultText.contains("use_workers"))
    }
}
