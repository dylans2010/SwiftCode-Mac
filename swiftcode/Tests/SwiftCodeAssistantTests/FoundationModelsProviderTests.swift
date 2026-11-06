import Foundation
import Testing
@testable import SwiftCodeAssistant

/// Apple Foundation Models provider tests.
///
/// This environment has no FoundationModels framework (Linux), so these
/// tests assert the honest-unavailable path: no canned reply, no claimed
/// model, no credential concept. Anything that touches the real framework
/// lives behind `#if canImport(FoundationModels)` and only runs where the
/// framework exists — on a Mac with Apple Intelligence. No Swift toolchain
/// exists in this environment, so these tests have had static checks only;
/// `swift test` on a Mac is still pending.
@Suite struct FoundationModelsProviderTests {
    @Test func kindAndSingleModelMatchLegacysDefaultEntry() {
        let p = FoundationModelsProvider()
        #expect(p.kind == .foundationModels)
        // Legacy's default selection (AppleFoundationModel.afm3Core):
        // one model, not a list — the framework exposes a single system
        // model and there is no /models endpoint to discover more.
        #expect(FoundationModelsProvider.modelID == "AFM 3 Core")
        #expect(FoundationModelsProvider.modelDisplayName == "Apple AFM 3 Core (On-Device)")
    }

    @Test func availabilityIsHonestlyUnavailableWithoutTheFramework() async {
        let a = await FoundationModelsProvider().availability()
        guard case .notInstalled(let hint) = a else {
            Issue.record("expected notInstalled without the framework, got \(a)")
            return
        }
        #expect(hint.contains("Apple Foundation Models"))
        #expect(hint.contains("macOS 26"))
    }

    @Test func contextWindowIsUnknownWithoutTheFramework() async {
        let p = FoundationModelsProvider()
        #expect(await p.contextWindow(model: FoundationModelsProvider.modelID) == nil)
        #expect(await p.contextWindow(model: "anything-else") == nil)
    }

    @Test func sendFailsHonestlyInsteadOfAnsweringFromCannedText() async {
        let request = ChatRequest(
            model: FoundationModelsProvider.modelID,
            instructions: "Be brief.",
            messages: [ChatMessage(.user, "Hello")]
        )
        do {
            _ = try await collect(FoundationModelsProvider().send(request))
            Issue.record("expected send to fail without the framework")
        } catch let error as AssistantError {
            #expect(error.errorDescription?.contains("Apple Foundation Models") == true)
        }
    }

    @Test func sendRejectsAnEmptyRequest() async {
        do {
            _ = try await collect(FoundationModelsProvider().send(
                ChatRequest(model: nil, instructions: "", messages: [])))
            Issue.record("expected send to fail on an empty request")
        } catch let error as AssistantError {
            #expect(error == .failed("There is no message to send."))
        }
    }

    @Test func promptTextKeepsInstructionsOutAndTagsEarlierTurns() {
        let request = ChatRequest(
            model: nil,
            instructions: "System rules.",
            messages: [
                ChatMessage(.system, "Earlier context."),
                ChatMessage(.user, "First question."),
                ChatMessage(.assistant, "First answer."),
                ChatMessage(.user, "Follow-up?"),
            ]
        )
        let prompt = FoundationModelsProvider.promptText(request)
        #expect(!prompt.contains("System rules."))
        #expect(prompt.contains("<system>\nEarlier context.\n</system>"))
        #expect(prompt.contains("<user>\nFirst question.\n</user>"))
        #expect(prompt.contains("<assistant>\nFirst answer.\n</assistant>"))
        #expect(prompt.hasSuffix("Follow-up?"))
        #expect(FoundationModelsProvider.promptText(
            ChatRequest(model: nil, instructions: "", messages: [])) == "")
    }

    @Test func deltaEmitsOnlyTheNewSuffixOfCumulativeSnapshots() {
        #expect(FoundationModelsProvider.delta("Hello", after: "") == "Hello")
        #expect(FoundationModelsProvider.delta("Hello world", after: "Hello") == " world")
        #expect(FoundationModelsProvider.delta("Hello", after: "Hello") == nil)
        #expect(FoundationModelsProvider.delta("", after: "") == nil)
        // A snapshot that revises earlier text is returned whole rather
        // than silently dropped.
        #expect(FoundationModelsProvider.delta("Hi there", after: "Hello") == "Hi there")
    }

#if canImport(FoundationModels)
    /// Only runs where the framework exists (a Mac with the macOS 26
    /// SDK). It does not require Apple Intelligence to be enabled: it
    /// accepts either ready-with-the-single-model or an honestly
    /// unavailable state with a message naming the cause.
    @Test func availabilityOnFrameworkPlatformsIsReadyOrHonest() async {
        let a = await FoundationModelsProvider().availability()
        switch a {
        case .ready(let models):
            #expect(models.count == 1)
            #expect(models.first?.id == FoundationModelsProvider.modelID)
        case .notInstalled(let hint), .failed(let hint):
            #expect(!hint.isEmpty)
            #expect(hint.contains("Apple Foundation Models") || hint.contains("Apple Intelligence"))
        default:
            Issue.record("unexpected availability state: \(a)")
        }
    }
#endif
}
