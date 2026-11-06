import Foundation
import SwiftCodeAssistant

/// One workspace window's coding assistant: its conversations, the
/// responses streaming into them, and the back ends' states. Shared by
/// both IDEs: the macOS view (`CodingAssistantViewController`) and the
/// Linux pane (`ShellAssistantModel`) observe it through `onChange` and
/// `observe(owner:_:)`. See specs/ide/coding-assistant.md §4.
@MainActor
public final class CodingAssistantModel {
    public enum Change: Equatable {
        /// The conversation list or the selection changed.
        case list
        /// The conversation's transcript changed.
        case transcript(UUID)
        /// Back-end states, the chosen provider or model changed.
        case status
    }

    public private(set) var conversations: [Conversation] = []
    /// The conversation list's groups (reference-ui-6.md §9.2).
    public private(set) var groups: [ConversationGroup] = []
    public var selectedID: UUID? { didSet { if oldValue != selectedID { notify(.list) } } }
    public private(set) var availability: [ProviderKind: ProviderAvailability] = [:]
    public private(set) var isSurveying = false
    public var onChange: ((Change) -> Void)?
    /// Further observers (the pane, conversations shown in editors); an
    /// observer is dropped when its owner goes away.
    private var observers: [(owner: Weak, f: (Change) -> Void)] = []
    final class Weak { weak var object: AnyObject?; init(_ o: AnyObject) { object = o } }

    public let prefs: Preferences
    public let services: CodingAssistantServices
    /// The workspace folder: agent tools run here; proposal paths are
    /// relative to it.
    public let workspaceRoot: URL
    /// The current editor's context for each request.
    public var contextProvider: () -> WorkspaceContext = { WorkspaceContext() }
    /// Where conversations are saved (nil: not saved).
    public let archiveURL: URL?
    private var running: [UUID: Task<Void, Never>] = [:]
    /// Agent mode: makes the attachment (SwiftCode's MCP server, the proposal
    /// and permission hooks) for one request of a conversation, and what
    /// ends it. Set by the window; nil: no agent mode.
    public var agentAttachment: ((UUID) -> (AgentAttachment, () -> Void)?)?
    private var attachmentCleanups: [UUID: () -> Void] = [:]
    /// The live MCP tool catalogue for providers that normalize tool
    /// names against it (Wave 16: `MetaAssistProvider.knownToolIDs`).
    /// SwiftCodeIDECore cannot depend on SwiftCodeMCP, so the shell supplies
    /// the ids lazily — the macOS shell reads them off its MCP host
    /// (`Set(server.tools.map(\.name))` plus `MCPServer.toolAliases`
    /// keys); the Linux shell leaves this unset and the provider
    /// records unmapped names instead of claiming they exist.
    /// Nil means no catalogue: never invent ids.
    public var mcpToolIDsProvider: (() -> Set<String>)?
    /// Meta slash commands (Wave 17): the catalog the composer
    /// intercepts when Assist with Meta is the active provider.
    /// The `/` popup (`SlashCommandPopupController`) lists them
    /// from this catalog; a command typed without the popup is
    /// recognised when the sent text starts with a known command
    /// name (`/effort low`, `/clear`, …); anything else starting
    /// with `/` is sent to the model as-is. The terminal-skill
    /// capture runs once, on first use, so `muse skills list` is
    /// never spawned just for opening the pane.
    public var metaSlashCommands = MetaSlashCommandManager()
    /// The model router (Wave 15): failover decisions for a
    /// failed turn live here, not in `send`.
    public let modelRouter = AssistModelRouter()
    /// How many times a failed turn may fail over to another
    /// model (3 attempts in total, Wave 15 rules).
    public static let maxTurnFailovers = 2
    /// Agent changes waiting for review, by message and code-block index.
    struct AgentEditKey: Hashable { var message: UUID; var block: Int }
    private var pendingAgentEdits: [AgentEditKey: (conversation: UUID, proposed: String, done: CheckedContinuation<Bool, Never>)] = [:]
    /// Transcript refreshes are coalesced while text streams.
    private var pendingRefresh: Set<UUID> = []
    private var refreshScheduled = false

    public init(workspaceRoot: URL, archiveURL: URL?, prefs: Preferences = .shared, services: CodingAssistantServices = .shared) {
        self.workspaceRoot = workspaceRoot
        self.archiveURL = archiveURL
        self.prefs = prefs
        self.services = services
        let library = archiveURL.map(ConversationArchive.loadLibrary) ?? ConversationLibrary()
        conversations = library.conversations
        groups = library.groups
        selectedID = conversations.last { !$0.isArchived }?.id
    }

    /// Calls `f` with every change while `owner` exists.
    public func observe(owner: AnyObject, _ f: @escaping (Change) -> Void) {
        observers.append((Weak(owner), f))
    }

    func notify(_ change: Change) {
        onChange?(change)
        observers.removeAll { $0.owner.object == nil }
        for o in observers { o.f(change) }
    }

    /// The list as the pane shows it.
    public var library: ConversationLibrary { ConversationLibrary(conversations: conversations, groups: groups) }

    /// Conversations are kept with SwiftCode's user data, one file per
    /// workspace (never inside the workspace).
    public static func archiveURL(forWorkspace url: URL) -> URL {
        let id = SHA256.hash(Data(url.standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftCode/Conversations/\(id).json")
    }

    public var selected: Conversation? { conversations.first { $0.id == selectedID } }
    public func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }
    public var settings: AssistantSettings { prefs.codingAssistant }

    // MARK: Back ends

    /// The provider chosen in the pop-up (Settings ▸ Coding Assistant).
    public var providerKind: ProviderKind { settings.provider }

    /// The chosen model, or the provider's first.
    public var modelID: String? {
        let chosen = settings.model(for: providerKind)
        // Wave 17: a stored Meta model is used verbatim (Legacy:
        // `AppSettings.metaAssistModelID` was the provider's
        // model, empty meaning the default). The availability
        // list is a fallback catalog, not authoritative — the
        // bridge may offer models it lacks (`muse-swift-2.0` is
        // a `/model` choice but not in the catalog) — so a
        // stored Meta choice is never replaced by the first
        // discovered model. The provider fails honestly if the
        // host does not know the id.
        if providerKind == .metaAssist, let chosen, !chosen.isEmpty { return chosen }
        let models = availability[providerKind]?.models ?? []
        if let chosen, models.isEmpty || models.contains(where: { $0.id == chosen }) { return chosen }
        return models.first?.id
    }

    public var modelName: String? {
        let id = modelID
        return availability[providerKind]?.models.first { $0.id == id }?.displayName ?? id
    }

    /// "Ollama · qwen2.5-coder:latest".
    public var sourceLabel: String {
        guard let m = modelName, !m.isEmpty else { return providerKind.displayName }
        return "\(providerKind.displayName) · \(m)"
    }

    public var readyProviders: [ProviderKind] { ProviderKind.allCases.filter { availability[$0]?.isReady == true } }
    public var hasUsableBackend: Bool { !readyProviders.isEmpty }
    public var currentAvailability: ProviderAvailability? { availability[providerKind] }

    /// Uses the ChatGPT plan (the composer says so).
    public var usesChatGPTPlan: Bool { providerKind == .openAI && settings.openAIAuth == .chatGPT }

    public func choose(_ kind: ProviderKind, model: String?) {
        var s = settings
        s.provider = kind
        if let model { s.setModel(model, for: kind) }
        prefs.codingAssistant = s
        notify(.status)
    }

    /// Checks every back end again.
    @discardableResult
    public func refreshAvailability() -> Task<Void, Never> {
        isSurveying = true
        notify(.status)
        let services = services, prefs = prefs
        return Task { [weak self] in
            let result = await services.survey(prefs: prefs)
            guard let self else { return }
            availability = result
            isSurveying = false
            notify(.status)
        }
    }

    // MARK: Conversations

    @discardableResult
    public func newConversation() -> Conversation {
        // An untouched new conversation is reused.
        if let s = selected, s.messages.isEmpty { return s }
        let c = Conversation(provider: providerKind, model: modelID)
        conversations.append(c)
        selectedID = c.id
        notify(.list)
        save()
        return c
    }

    public func delete(_ id: UUID) {
        stop(id)
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = conversations.last { !$0.isArchived }?.id }
        notify(.list)
        save()
    }

    // MARK: Groups and the archive (reference-ui-6.md §9.2)

    /// Adds a group ("New Group", numbered when taken).
    @discardableResult
    public func newGroup(title: String? = nil) -> ConversationGroup {
        let g = ConversationGroup(title: title ?? library.unusedGroupTitle())
        groups.append(g)
        notify(.list)
        save()
        return g
    }

    public func renameGroup(_ id: UUID, to title: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let t = title.trimmingCharacters(in: .whitespaces)
        groups[i].title = t.isEmpty ? ConversationGroup.untitled : t
        notify(.list)
        save()
    }

    /// Deletes the group; its conversations move to the top level.
    public func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        for i in conversations.indices where conversations[i].groupID == id { conversations[i].groupID = nil }
        notify(.list)
        save()
    }

    /// Files the conversation in a group (nil: the top level); an archived
    /// conversation comes back out of the archive.
    public func move(_ id: UUID, toGroup group: UUID?) {
        update(id) { c in
            c.groupID = group
            c.isArchived = false
        }
        notify(.list)
        save()
    }

    public func setArchived(_ id: UUID, _ archived: Bool) {
        update(id) { $0.isArchived = archived }
        notify(.list)
        save()
    }

    public func rename(_ id: UUID, to title: String) {
        update(id) { $0.title = title.isEmpty ? Conversation.untitled : title }
        notify(.list)
        save()
    }

    /// Conversations whose response is streaming.
    public var activeIDs: [UUID] { conversations.filter(\.isActive).map(\.id) }
    public func isRunning(_ id: UUID) -> Bool { running[id] != nil }
    /// The task streaming the conversation's response (tests await it).
    public func response(_ id: UUID) -> Task<Void, Never>? { running[id] }

    /// Navigate ▸ Jump to Next Active Conversation: the next conversation
    /// (after the selected one, wrapping) with a response in progress.
    @discardableResult
    public func selectNextActive() -> UUID? {
        let active = conversations.filter(\.isActive)
        guard !active.isEmpty else { return nil }
        let order = conversations.map(\.id)
        let current = selectedID.flatMap { order.firstIndex(of: $0) } ?? -1
        let next = active.first { order.firstIndex(of: $0.id)! > current } ?? active[0]
        selectedID = next.id
        return next.id
    }

    func update(_ id: UUID, _ f: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        f(&conversations[i])
    }

    /// Sends a message in the selected conversation (a new one if none) and
    /// streams the answer. Returns the conversation's ID.
    @discardableResult
    public func send(_ text: String, attachments: [Attachment] = [], newConversationTitle: String? = nil, in target: UUID? = nil) -> UUID? {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        // Wave 17: a Meta slash command typed at the composer is
        // intercepted here — the only place slash commands enter
        // the host (the `/` popup commits through here too; see
        // `handleMetaSlashCommand`). `.inserted` leaves the text
        // in the input for editing, `.handled` posts the effect's
        // result, and anything else is sent to the model as-is.
        switch handleMetaSlashCommand(prompt) {
        case .notACommand:
            break
        case .inserted:
            return nil
        case .handled(let id):
            return id
        }
        var id = target.flatMap { conversation($0)?.id } ?? selected.map(\.id) ?? newConversation().id
        if newConversationTitle != nil {
            id = newConversation().id
        }
        guard !isRunning(id) else { return nil }
        let context = contextProvider()
        let kind = providerKind, model = modelID
        let history = conversation(id)?.history ?? []
        update(id) { c in
            if c.messages.isEmpty { c.title = newConversationTitle ?? Conversation.title(fromPrompt: prompt) }
            c.provider = kind
            c.model = model
            c.messages.append(ConversationMessage(role: .user, text: prompt, attachments: attachments))
            c.messages.append(ConversationMessage(role: .assistant, text: "", source: sourceLabel, isComplete: false,
                                                  target: context.proposalTarget))
        }
        if model == nil && kind.cliAgent == nil {
            // Nothing to send to: say why instead of failing at the server.
            let why = availability[kind]?.hint ?? "Choose a model in the model menu."
            finish(id, error: "No \(kind.displayName) model is available. " + why)
            return id
        }
        var provider = services.provider(kind, prefs: prefs)
        // Wave 16: Meta normalizes tool names against SwiftCode's MCP
        // catalogue. The provider cannot fetch it itself
        // (SwiftCodeAssistant cannot depend on SwiftCodeMCP), so the shell
        // injects it here when it supplied one. Without it the
        // provider records names unmapped rather than claiming them.
        if var meta = provider as? MetaAssistProvider, let ids = mcpToolIDsProvider?() {
            meta.knownToolIDs = ids
            provider = meta
        }
        var instructions = PromptBuilder.instructions
        if settings.agentMode, let attachable = provider as? AgentAttachable, let (attachment, cleanup) = agentAttachment?(id) {
            let attached = attachable.attaching(attachment)
            if (attached as? AgentAttachable)?.isAttached == true {
                provider = attached
                instructions = PromptBuilder.agentInstructions
                attachmentCleanups[id] = cleanup
                if kind == .metaAssist {
                    // Wave 16: the "SwiftCode's tools are attached" line
                    // overclaims for Meta — the Muse host runs its own
                    // tools and SwiftCode cannot intercept its file edits,
                    // so they are not reviewed as proposals.
                    appendActivity(id, "Agent mode: Meta runs its own tools in the Muse host; SwiftCode's tools are named, not executed, and its file edits are not reviewed as proposals")
                } else {
                    appendActivity(id, "Agent mode: SwiftCode's tools are attached; each change is a proposal you review")
                }
            } else {
                cleanup()
            }
        }
        let limit = settings.contextLimit, options = settings.context, root = workspaceRoot, generation = settings.generation
        running[id] = Task { [weak self] in
            // Wave 17, Slice B: the other-model mode switch. Legacy
            // checked `otherModelsWithMetaSDK ||
            // swiftCodeCloudWithMetaSDK` at turn time in
            // `MetaAssistProvider.executeTurn` and started the local
            // proxy there, passing its URL as `--base-url`. SwiftCode
            // does the same here, where the provider is built: when
            // Meta is the provider and either toggle is on, the
            // proxy starts for the resolved other model and the
            // provider's `proxyBaseURL` tracks the running proxy's
            // real URL; the turn's model becomes the resolved other
            // model (the proxy's catalog serves exactly that one).
            // When mode is off — or the provider is not Meta — a
            // running proxy stops. A start failure (missing `muse`
            // binary, no bindable port) fails this turn honestly:
            // it is caught below and shown, never silently run on
            // Meta's own models.
            var effectiveProvider = provider
            var effectiveModel = model
            do {
                if kind == .metaAssist, let metaProvider = provider as? MetaAssistProvider, let self {
                    if MuseOtherModelsProxyController.isOtherModelModeEnabled(
                        otherModelsWithMetaSDK: self.settings.metaUseOtherModels,
                        swiftCodeCloudWithMetaSDK: self.settings.metaUseCloudModelWithMeta)
                    {
                        let discovered = self.discoveredCandidates()
                        let resolution = MuseOtherModelsBridge.resolveActiveModel(
                            selectedOtherModelID: self.settings.metaSelectedOtherModelID,
                            selectedOtherModelProvider: self.settings.metaSelectedOtherModelProvider,
                            generalModelID: model ?? "",
                            discovered: discovered,
                            customEndpoints: [],
                            cloudModelIDs: [],
                            onlyUseFree: self.settings.onlyUseFreeModels)
                        let backends = self.services.backends(self.prefs)
                        let streamChat: MuseLocalProxyServer.StreamChat = { streamModelID, messages, systemPrompt in
                            AsyncThrowingStream { continuation in
                                let task = Task {
                                    do {
                                        let streamProvider = backends.provider(forModelID: streamModelID)
                                        let chatRequest = ChatRequest(
                                            model: streamModelID, instructions: systemPrompt, messages: messages,
                                            workingDirectory: nil, generation: .assistantDefault)
                                        for try await event in streamProvider.send(chatRequest) {
                                            if case .text(let delta) = event { continuation.yield(delta) }
                                            if case .finished = event { break }
                                        }
                                        continuation.finish()
                                    } catch {
                                        continuation.finish(throwing: error)
                                    }
                                }
                                continuation.onTermination = { _ in task.cancel() }
                            }
                        }
                        let url = try await MuseOtherModelsProxyController.shared.enable(
                            resolution: resolution, executable: metaProvider.executableURL(), streamChat: streamChat)
                        var updated = metaProvider
                        updated.proxyBaseURL = url.absoluteString
                        effectiveProvider = updated
                        effectiveModel = resolution.modelID
                        self.appendActivity(id, "Other-model mode: \(resolution.displayName) via local proxy")
                    } else {
                        await MuseOtherModelsProxyController.shared.disable()
                    }
                } else {
                    await MuseOtherModelsProxyController.shared.disable()
                }
            } catch {
                let stopped = Task.isCancelled || error is CancellationError || HTTPCancellation.matches(error)
                self?.finish(id, error: stopped ? "Stopped." : Self.describe(error))
                return
            }
            // Gap closure: router failover (Wave 15 rules). A
            // failed turn retries on the next eligible model, at
            // most `maxTurnFailovers` times, only when
            // "Automatically switch models" is on and only when
            // the turn has a model to exclude (CLI-agent turns
            // have none). While other-model mode is on the proxy
            // serves exactly one model, so a failover would
            // misroute and is skipped. The partial text stays in
            // the transcript; the continuation prompt carries it
            // to the next model, and the conversation's recorded
            // model follows the switch.
            let otherModelMode: Bool = {
                guard let self else { return false }
                return kind == .metaAssist && MuseOtherModelsProxyController.isOtherModelModeEnabled(
                    otherModelsWithMetaSDK: self.settings.metaUseOtherModels,
                    swiftCodeCloudWithMetaSDK: self.settings.metaUseCloudModelWithMeta)
            }()
            var attemptPrompt = prompt
            var attemptProvider = effectiveProvider
            var attemptModel = effectiveModel
            var attemptKind = kind
            var failovers = 0
            while true {
                var window = availability[attemptKind]?.models.first { $0.id == attemptModel }?.contextWindow
                if window == nil, let attemptModel { window = await attemptProvider.contextWindow(model: attemptModel) }
                let budget = min(limit, window ?? limit)
                let built = PromptBuilder.build(history: history, prompt: attemptPrompt, attachments: attachments, context: context,
                                                options: options, contextTokens: budget, instructions: instructions)
                let request = ChatRequest(model: attemptModel, instructions: built.instructions, messages: built.messages,
                                          contextTokens: attemptKind == .ollama ? budget : nil, workingDirectory: root, generation: generation)
                if !built.omitted.isEmpty {
                    self?.appendActivity(id, "Left out to fit the context: " + built.omitted.joined(separator: ", "))
                }
                var partial = ""
                do {
                    for try await event in attemptProvider.send(request) {
                        guard let self else { return }
                        switch event {
                        case .text(let t):
                            appendText(id, t)
                            partial += t
                        case .activity(let a): appendActivity(id, a)
                        case .truncated: markCutOff(id)
                        case .finished: break
                        }
                    }
                    // A cancelled stream ends without an error.
                    self?.finish(id, error: Task.isCancelled ? "Stopped." : nil)
                    return
                } catch {
                    let stopped = Task.isCancelled || error is CancellationError || HTTPCancellation.matches(error)
                    guard !stopped else {
                        self?.finish(id, error: "Stopped.")
                        return
                    }
                    guard failovers < Self.maxTurnFailovers,
                          let failedID = attemptModel,
                          !otherModelMode else {
                        self?.finish(id, error: Self.describe(error))
                        return
                    }
                    guard let self else { return }
                    guard settings.automaticallySwitchModels else {
                        // Never silently substitute when auto-switch
                        // is off: the turn waits on the selected
                        // model, and the error says so.
                        self.finish(id, error: Self.describe(error))
                        return
                    }
                    let failed = AssistCandidateModel(
                        id: failedID, displayName: failedID, provider: attemptKind,
                        modelIdentifier: failedID, contextWindow: window ?? 128_000)
                    let discovered = self.discoveredCandidates()
                    let eligible = await modelRouter.eligibleCandidates(
                        from: discovered, strategy: settings.routingStrategy,
                        useProviderModelsOnly: settings.useProviderModelsOnly,
                        useCloudModel: settings.useSwiftCodeCloudModel)
                    guard let (nextModel, handoff) = await modelRouter.handleTurnFailure(
                        failedModel: failed, error: error, completedTurnContent: partial,
                        executedToolsCount: 0, objective: prompt,
                        automaticallySwitchModels: settings.automaticallySwitchModels,
                        eligibleCandidates: eligible) else {
                        self.finish(id, error: Self.describe(error))
                        return
                    }
                    failovers += 1
                    appendActivity(id, "“\(failed.displayName)” failed (\(AssistModelRouter.classify(error: error).rawValue)); switching to \(nextModel.displayName)")
                    var nextProvider = services.backends(prefs).provider(forModelID: nextModel.id)
                    if var meta = nextProvider as? MetaAssistProvider, let ids = mcpToolIDsProvider?() {
                        meta.knownToolIDs = ids
                        nextProvider = meta
                    }
                    // Agent mode re-attaches on the new provider
                    // (the old attachment is cleaned up first).
                    if settings.agentMode, let attachable = nextProvider as? AgentAttachable {
                        attachmentCleanups.removeValue(forKey: id)?()
                        if let (attachment, cleanup) = agentAttachment?(id) {
                            let attached = attachable.attaching(attachment)
                            if (attached as? AgentAttachable)?.isAttached == true {
                                nextProvider = attached
                                attachmentCleanups[id] = cleanup
                            } else {
                                cleanup()
                            }
                        }
                    }
                    update(id) { c in
                        c.model = nextModel.id
                        c.provider = nextModel.provider
                    }
                    notify(.status)
                    attemptProvider = nextProvider
                    attemptModel = nextModel.id
                    attemptKind = nextModel.provider
                    attemptPrompt = handoff + "\n\nOriginal request:\n" + prompt
                }
            }
        }
        notify(.list)
        notify(.transcript(id))
        return id
    }

    /// Stops the conversation's response (the stop button).
    public func stop(_ id: UUID) {
        running[id]?.cancel()
    }

    public func stopAll() { for id in Array(running.keys) { stop(id) } }

    // MARK: Meta slash commands (Wave 17)

    /// What intercepting a typed slash command produced.
    public enum MetaSlashCommandHandling: Sendable, Equatable {
        /// Not a Meta slash command: send the text normally.
        case notACommand
        /// The command text belongs back in the input (Legacy:
        /// `executeCommand` returned the command string for the
        /// composer to keep). The caller keeps the field.
        case inserted
        /// The effect was applied and its result posted in this
        /// conversation.
        case handled(UUID)
    }

    /// Intercepts a Meta slash command typed at the composer.
    /// Only when Assist with Meta is the active provider, and
    /// only when the first token is a known command name
    /// (built-in or captured terminal skill): anything else —
    /// including `/usr/bin/...` paths — is sent to the model
    /// as-is, exactly as Legacy's popup only offered known
    /// commands. Effect commands (`/effort`, `/model`, `/clear`,
    /// `/login`) are applied through
    /// `MetaSlashCommandEffectApplier` and the result is posted
    /// as an assistant message; other commands (including
    /// terminal skills and commands without their argument, like
    /// a bare `/effort`) are left in the input, as Legacy put
    /// the command string back into the composer.
    @discardableResult
    public func handleMetaSlashCommand(_ text: String) -> MetaSlashCommandHandling {
        // Gap closure: the toggle gates the typed-command
        // intercept too, not just the `/` popup. When it is off,
        // `/…` text is sent to the model as-is.
        guard settings.useMetaSlashCommands else { return .notACommand }
        guard providerKind == .metaAssist else { return .notACommand }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return .notACommand }
        let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) ?? trimmed.endIndex
        let name = String(trimmed[..<firstSpace]).lowercased()
        guard let command = metaSlashCommands.commands.first(where: { $0.name.lowercased() == name }) else {
            return .notACommand
        }
        let argument = firstSpace < trimmed.endIndex
            ? String(trimmed[trimmed.index(after: firstSpace)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        // Terminal skills join the catalog on first use, so the
        // next command can match them; the built-ins match at
        // once. Fire-and-forget: a missing binary or a failed
        // capture leaves the built-ins untouched.
        if metaSlashCommands.lastCapturedAt == nil { refreshMetaSlashCommands() }
        let (_, effect) = metaSlashCommands.executeCommand(command, argument: argument?.isEmpty == true ? nil : argument)
        guard let effect else { return .inserted }
        if case .insertText = effect { return .inserted }

        let knownModels = Set(MetaAssistProvider.fallbackModels.map(\.modelId))
            .union(availability[.metaAssist]?.models.map(\.id) ?? [])
        var outcome = MetaSlashCommandEffectApplier.apply(effect, settings: settings, knownModelIDs: knownModels)
        if case .startLogin = effect,
           let meta = services.provider(.metaAssist, prefs: prefs) as? MetaAssistProvider, meta.hasCredentials() {
            // Already signed in: the instruction would be a lie.
            outcome.message = "Assist with Meta is already signed in."
        }
        if outcome.settings != settings {
            prefs.codingAssistant = outcome.settings
            notify(.status)
        }
        if case .setModel(let modelID) = effect {
            // A live session keeps its model until told
            // otherwise; the next turn uses the stored one.
            Task { try? await MetaAssistTurnExecutor.shared.switchModel(modelID: modelID) }
        }
        if outcome.clearsSession {
            // Legacy `clearChat`: cancel the active work first,
            // then clear. The old conversation stays in the
            // library — SwiftCode never deletes a transcript
            // implicitly — and the result is posted in the fresh
            // one.
            let runningID = selectedID
            if let runningID { stop(runningID) }
            Task {
                await MetaAssistTurnExecutor.shared.cancelTurn()
                await MetaAssistTurnExecutor.shared.resetSession()
            }
            let fresh = newConversation()
            postSlashCommandResult(commandText: trimmed, result: outcome.message, in: fresh.id)
            return .handled(fresh.id)
        }
        let id = selected.map(\.id) ?? newConversation().id
        postSlashCommandResult(commandText: trimmed, result: outcome.message, in: id)
        return .handled(id)
    }

    /// Captures terminal skills (`muse skills list`) into the
    /// slash-command catalog, once. A missing binary leaves the
    /// built-ins untouched.
    private func refreshMetaSlashCommands() {
        guard let meta = services.provider(.metaAssist, prefs: prefs) as? MetaAssistProvider,
              let executable = meta.executableURL() else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.metaSlashCommands.captureCommandsFromTerminal(executable: executable)
        }
    }

    /// Triggers the once-only terminal-skill capture (the `/`
    /// popup calls this when it opens, so skills join the list).
    public func ensureSlashCommandsCaptured() {
        if metaSlashCommands.lastCapturedAt == nil { refreshMetaSlashCommands() }
    }

    /// Every model the availability survey knows, as router
    /// candidates. The failover path and the other-model proxy
    /// resolution share this list.
    func discoveredCandidates() -> [AssistCandidateModel] {
        var discovered: [AssistCandidateModel] = []
        for (kind, avail) in availability {
            for info in avail.models {
                discovered.append(AssistCandidateModel(
                    id: info.id, displayName: info.displayName, provider: kind,
                    modelIdentifier: info.id, contextWindow: info.contextWindow ?? 128_000))
            }
        }
        return discovered
    }

    /// Posts a slash command and its effect's result as a
    /// completed user/assistant pair, so the effect is visible
    /// in the transcript (Legacy only logged it).
    private func postSlashCommandResult(commandText: String, result: String, in id: UUID) {
        update(id) { c in
            if c.messages.isEmpty { c.title = Conversation.title(fromPrompt: commandText) }
            c.provider = providerKind
            c.model = modelID
            c.messages.append(ConversationMessage(role: .user, text: commandText))
            c.messages.append(ConversationMessage(role: .assistant, text: result, source: sourceLabel, isComplete: true))
        }
        notify(.list)
        notify(.transcript(id))
        save()
    }

    /// The coding tools (Editor ▸ Show Coding Tools): a new conversation
    /// with the tool's prompt and the selection or file attached.
    @discardableResult
    public func run(_ tool: CodingTool) -> UUID? {
        let ctx = contextProvider()
        guard let file = ctx.currentFile else { return nil }
        var attachments: [Attachment] = []
        let name = (file.path as NSString).lastPathComponent
        var title = "\(tool.title) \(name)"
        if let s = ctx.selection, !s.text.isEmpty {
            attachments.append(Attachment(kind: .selection, path: s.path, startLine: s.startLine, endLine: s.endLine, text: s.text))
            title = "\(tool.title) \(attachments[0].label)"
        } else {
            attachments.append(Attachment(kind: .file, path: file.path, text: file.text))
        }
        return send(tool.prompt(path: file.path, hasSelection: ctx.selection.map { !$0.text.isEmpty } ?? false),
                    attachments: attachments, newConversationTitle: title)
    }

    func appendText(_ id: UUID, _ t: String) {
        update(id) { c in if let i = c.messages.indices.last { c.messages[i].text += t } }
        scheduleRefresh(id)
    }

    /// The reply stopped at the output limit (Settings ▸ Coding Assistant ▸
    /// Most output tokens): the transcript says so and offers Continue.
    func markCutOff(_ id: UUID) {
        update(id) { c in if let i = c.messages.indices.last { c.messages[i].isCutOff = true } }
        scheduleRefresh(id)
    }

    /// The prompt Continue sends after a cut-off reply.
    public static let continuePrompt = "Continue exactly where your last reply stopped. Do not repeat anything."

    /// Continue: asks the model to go on after a cut-off reply.
    @discardableResult
    public func continueReply(in id: UUID) -> UUID? {
        guard conversation(id)?.messages.last?.isCutOff == true, !isRunning(id) else { return nil }
        return send(Self.continuePrompt, in: id)
    }

    func appendActivity(_ id: UUID, _ a: String) {
        update(id) { c in if let i = c.messages.indices.last { c.messages[i].activity.append(a) } }
        scheduleRefresh(id)
    }

    func finish(_ id: UUID, error: String?) {
        running[id] = nil
        attachmentCleanups.removeValue(forKey: id)?()
        // Changes still waiting when the response ends are not applied.
        for (key, p) in pendingAgentEdits where p.conversation == id {
            pendingAgentEdits[key] = nil
            p.done.resume(returning: false)
        }
        update(id) { c in
            guard let i = c.messages.indices.last, c.messages[i].role == .assistant else { return }
            c.messages[i].isComplete = true
            c.messages[i].error = error
        }
        pendingRefresh.remove(id)
        notify(.transcript(id))
        notify(.list)
        save()
    }

    /// Marks a proposal accepted or rejected (an agent waiting for it is
    /// answered).
    public func resolve(message: UUID, in conversationID: UUID, proposal index: Int, _ r: ProposalResolution) {
        update(conversationID) { c in
            if let i = c.messages.firstIndex(where: { $0.id == message }) { c.messages[i].resolvedProposals[index] = r }
        }
        pendingAgentEdits.removeValue(forKey: AgentEditKey(message: message, block: index))?.done.resume(returning: r == .accepted)
        notify(.transcript(conversationID))
        save()
    }

    // MARK: Agent mode

    /// An agent's change as a proposal in the conversation's running
    /// response: a `file=` block the user reviews like any other. Returns
    /// once they decide: true when it was accepted (and saved). Paths
    /// outside the workspace folder are refused.
    public func proposeAgentChange(in id: UUID, path: String, proposed: String) async -> Bool {
        let rootPath = workspaceRoot.standardizedFileURL.path
        let real = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let rel = [rootPath, real].lazy.compactMap({ r -> String? in
            let prefix = r.hasSuffix("/") ? r : r + "/"
            return p.hasPrefix(prefix) ? String(p.dropFirst(prefix.count)) : nil
        }).first, !rel.isEmpty, !rel.contains(" "),
              let c = conversation(id), let mi = c.messages.indices.last, c.messages[mi].role == .assistant else { return false }
        var text = c.messages[mi].text
        if case .code(_, _, false)? = MarkdownBlocks.parse(text).last { text += "\n```" }
        let fence = proposed.contains("```") ? "~~~~" : "```"
        let body = proposed.hasSuffix("\n") ? String(proposed.dropLast()) : proposed
        let block = (text.isEmpty ? "" : "\n\n") + "\(fence)\(Self.language(forPath: rel)) file=\(rel)\n\(body)\n\(fence)\n\n"
        let newText = text + block
        let index = MarkdownBlocks.parse(newText).filter { if case .code = $0 { true } else { false } }.count - 1
        let messageID = c.messages[mi].id
        update(id) { $0.messages[mi].text = newText }
        notify(.transcript(id))
        return await withCheckedContinuation { done in
            pendingAgentEdits[AgentEditKey(message: messageID, block: index)] = (id, proposed, done)
        }
    }

    /// The exact text of an agent's change waiting for review (the review
    /// shows and applies it as given).
    public func agentProposalText(message: UUID, block: Int) -> String? {
        pendingAgentEdits[AgentEditKey(message: message, block: block)]?.proposed
    }

    /// Agent changes waiting for review (tests).
    public var pendingAgentChangeCount: Int { pendingAgentEdits.count }

    static func language(forPath p: String) -> String {
        switch (p as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "m", "mm", "h": "objc"
        case "c": "c"
        case "cpp", "cc", "hpp": "cpp"
        case "json", "xcstrings": "json"
        case "md": "markdown"
        case "plist", "xml", "xcscheme", "storyboard", "xib": "xml"
        case "sh": "sh"
        case "py": "python"
        default: "text"
        }
    }

    private func scheduleRefresh(_ id: UUID) {
        pendingRefresh.insert(id)
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshScheduled = false
                let ids = self.pendingRefresh
                self.pendingRefresh = []
                for id in ids { self.notify(.transcript(id)) }
            }
        }
    }

    func save() {
        guard let archiveURL else { return }
        let snapshot = library
        // One queue, in order: a later snapshot is never overwritten by an
        // earlier one.
        Self.saveQueue.async { try? ConversationArchive.save(snapshot, to: archiveURL) }
    }

    static let saveQueue = DispatchQueue(label: "dev.swiftcode.conversations", qos: .utility)

    /// The text shown for a failed response.
    public static func describe(_ error: Error) -> String {
        if let e = error as? AssistantError {
            return [e.errorDescription, e.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        }
        return error.localizedDescription
    }
}

enum HTTPCancellation {
    static func matches(_ e: Error) -> Bool { HTTP.isCancellation(e) }
}
