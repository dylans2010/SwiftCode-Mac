import Foundation
import Testing
@testable import SwiftCodeAssistant

/// Gap-closure tests for the slash-command menu (specs/ide/
/// gap-closure-windows-artboards.md §1): the manager's search
/// and execution dispatcher, the popup's palette state, the
/// `useMetaSlashCommands` default, and the router's turn-failure
/// failover that the popup's `/model` host effect feeds into.
@Suite("Slash menu gap tests")
struct SlashMenuGapTests {
    // MARK: - Search

    @Test("Empty query returns the whole catalog")
    func searchEmptyReturnsAll() {
        let manager = MetaSlashCommandManager()
        #expect(manager.searchCommands(query: "") == manager.commands)
        #expect(!manager.commands.isEmpty)
    }

    @Test("The four host-effect commands are in the catalog")
    func effectCommandsPresent() {
        let manager = MetaSlashCommandManager()
        for id in ["effort", "model", "clear", "login"] {
            #expect(manager.searchCommands(query: "/\(id)").contains { $0.id == id }, "missing /\(id)")
        }
    }

    @Test("Search matches name, title, description, and category; a leading slash is ignored")
    func searchMatchesFields() {
        let manager = MetaSlashCommandManager()
        #expect(manager.searchCommands(query: "eff").contains { $0.id == "effort" })
        #expect(manager.searchCommands(query: "/model").contains { $0.id == "model" })
        #expect(manager.searchCommands(query: "zzz-no-such-command").isEmpty)
        #expect(manager.searchCommands(query: "session").contains { $0.id == "clear" })
    }

    // MARK: - Execution dispatcher

    @Test("Effect commands return Legacy's verbatim text and a host-side effect")
    func effectCommandsReturnVerbatimText() {
        let manager = MetaSlashCommandManager()
        let effort = manager.commands.first { $0.id == "effort" }!
        let (effortText, effortEffect) = manager.executeCommand(effort, argument: "high")
        #expect(effortText == "Meta reasoning effort set to 'high'.")
        #expect(effortEffect == .setReasoningEffort("high"))

        let model = manager.commands.first { $0.id == "model" }!
        let (modelText, modelEffect) = manager.executeCommand(model, argument: "opus")
        #expect(modelText == "Meta Assist model switched to 'opus'.")
        #expect(modelEffect == .setModel("opus"))

        let clear = manager.commands.first { $0.id == "clear" }!
        let (clearText, clearEffect) = manager.executeCommand(clear, argument: nil)
        #expect(clearText == "Cleared Assist session.")
        #expect(clearEffect == .clearSession)

        let login = manager.commands.first { $0.id == "login" }!
        let (loginText, loginEffect) = manager.executeCommand(login, argument: nil)
        #expect(loginText == "Starting Meta authentication flow...")
        #expect(loginEffect == .startLogin)
    }

    @Test("A command with no host-side effect inserts its text")
    func plainCommandInsertsText() {
        let manager = MetaSlashCommandManager()
        let plain = MetaSlashCommand(
            id: "review", name: "/review", title: "Review", description: "Review the diff",
            syntax: "/review", category: "General")
        let (bareText, bareEffect) = manager.executeCommand(plain, argument: nil)
        #expect(bareText == "/review")
        #expect(bareEffect == .insertText("/review"))
        let (argText, argEffect) = manager.executeCommand(plain, argument: "staged")
        #expect(argText == "/review staged")
        #expect(argEffect == .insertText("/review staged"))
    }

    // MARK: - Palette state

    @Test("Palette starts on the first match and wraps on move up/down")
    func paletteSelectionWraps() {
        var state = SlashCommandPaletteState(manager: MetaSlashCommandManager(), query: "")
        let count = state.filtered.count
        #expect(count > 1)
        #expect(state.selectedIndex == 0)
        state.moveUp()
        #expect(state.selectedIndex == count - 1)
        state.moveDown()
        #expect(state.selectedIndex == 0)
        state.moveDown()
        #expect(state.selectedIndex == 1)
    }

    @Test("Palette re-filters on a new query and clears the selection when nothing matches")
    func paletteRefilters() {
        var state = SlashCommandPaletteState(manager: MetaSlashCommandManager(), query: "")
        state.update(query: "eff")
        #expect(state.selected?.id == "effort")
        state.update(query: "zzz-no-such-command")
        #expect(state.filtered.isEmpty)
        #expect(state.selected == nil)
        #expect(state.commitText(argument: nil) == nil)
        #expect(state.shouldSendImmediately(argument: nil) == false)
    }

    @Test("Palette commit sends immediately only for host-effect commands")
    func paletteCommitSendImmediately() {
        var state = SlashCommandPaletteState(manager: MetaSlashCommandManager(), query: "eff")
        #expect(state.commitText(argument: "high") == "Meta reasoning effort set to 'high'.")
        #expect(state.shouldSendImmediately(argument: "high") == true)

        state.update(query: "clear")
        #expect(state.commitText(argument: nil) == "Cleared Assist session.")
        #expect(state.shouldSendImmediately(argument: nil) == true)

        // A plain command stays in the input for editing.
        let plainManager = MetaSlashCommandManager(commands: [
            MetaSlashCommand(
                id: "review", name: "/review", title: "Review", description: "Review the diff",
                syntax: "/review", category: "General"),
        ])
        var plain = SlashCommandPaletteState(manager: plainManager, query: "")
        #expect(plain.commitText(argument: nil) == "/review")
        #expect(plain.shouldSendImmediately(argument: nil) == false)
    }

    // MARK: - Defaults

    @Test("Slash commands are on by default")
    func slashCommandsOnByDefault() {
        #expect(AssistantSettings().useMetaSlashCommands == true)
    }

    // MARK: - Router failover (the /model host effect's other end)

    private func candidates() -> [AssistCandidateModel] {
        [
            AssistCandidateModel(id: "a-1", provider: .openRouter),
            AssistCandidateModel(id: "a-2", provider: .openRouter),
            AssistCandidateModel(id: "b-1", provider: .foundationModels),
        ]
    }

    @Test("Failover is off when auto-switch is off")
    func failoverOffWithoutAutoSwitch() async {
        let router = AssistModelRouter()
        let result = await router.handleTurnFailure(
            failedModel: candidates()[0],
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "429 Too Many Requests"]),
            completedTurnContent: "partial", executedToolsCount: 0,
            automaticallySwitchModels: false,
            eligibleCandidates: candidates())
        #expect(result == nil)
    }

    @Test("A 429 fails over to the next model and carries the partial output forward")
    func failoverOnRateLimit() async {
        let router = AssistModelRouter()
        let all = candidates()
        let result = await router.handleTurnFailure(
            failedModel: all[0],
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "429 Too Many Requests"]),
            completedTurnContent: "partial output", executedToolsCount: 2,
            automaticallySwitchModels: true,
            eligibleCandidates: all)
        #expect(result != nil)
        #expect(result?.nextModel.id == "a-2")
        #expect(result?.continuationPrompt.contains("partial output") == true)
    }

    @Test("A quota failure excludes the whole failed provider")
    func quotaFailureExcludesProvider() async {
        let router = AssistModelRouter()
        let all = candidates()
        let result = await router.handleTurnFailure(
            failedModel: all[0],
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "quota exceeded"]),
            completedTurnContent: "", executedToolsCount: 0,
            automaticallySwitchModels: true,
            eligibleCandidates: all)
        #expect(result?.nextModel.id == "b-1")
    }

    @Test("Failover returns nil when no eligible model remains")
    func failoverNilWhenNothingEligible() async {
        let router = AssistModelRouter()
        let result = await router.handleTurnFailure(
            failedModel: candidates()[0],
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "429 Too Many Requests"]),
            completedTurnContent: "", executedToolsCount: 0,
            automaticallySwitchModels: true,
            eligibleCandidates: [candidates()[0]])
        #expect(result == nil)
    }
}
