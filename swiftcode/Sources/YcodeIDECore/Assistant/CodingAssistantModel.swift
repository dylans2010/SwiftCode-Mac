import Foundation
import YcodeAssistant

@MainActor
public final class CodingAssistantModel {
    public enum Change: Equatable {
        case list
        case transcript(UUID)
        case status
    }

    public private(set) var conversations: [Conversation] = []
    public private(set) var groups: [ConversationGroup] = []
    public var selectedID: UUID? { didSet { if oldValue != selectedID { notify(.list) } } }
    public private(set) var availability: [ProviderKind: ProviderAvailability] = [:]
    public private(set) var isSurveying = false
    public var onChange: ((Change) -> Void)?
    private var observers: [(owner: Weak, f: (Change) -> Void)] = []
    final class Weak { weak var object: AnyObject?; init(_ o: AnyObject) { object = o } }

    public let prefs: Preferences
    public let services: CodingAssistantServices
    public let workspaceRoot: URL
    public var contextProvider: () -> WorkspaceContext = { WorkspaceContext() }
    public let archiveURL: URL?
    private var running: [UUID: Task<Void, Never>] = [:]
    public var agentAttachment: ((UUID) -> (AgentAttachment, () -> Void)?)?
    private var attachmentCleanups: [UUID: () -> Void] = [:]
    public var mcpToolIDsProvider: (() -> Set<String>)?
    public var metaSlashCommands = MetaSlashCommandManager()
    public let modelRouter = AssistModelRouter()
    public static let maxTurnFailovers = 2
    struct AgentEditKey: Hashable { var message: UUID; var block: Int }
    private var pendingAgentEdits: [AgentEditKey: (conversation: UUID, proposed: String, done: CheckedContinuation<Bool, Never>)] = [:]
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

    public func observe(owner: AnyObject, _ f: @escaping (Change) -> Void) {
        observers.append((Weak(owner), f))
    }

    func notify(_ change: Change) {
        onChange?(change)
        observers.removeAll { $0.owner.object == nil }
        for o in observers { o.f(change) }
    }

    public var library: ConversationLibrary { ConversationLibrary(conversations: conversations, groups: groups) }

    public static func archiveURL(forWorkspace url: URL) -> URL {
        let id = SHA256.hash(Data(url.standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftCode/Conversations/\(id).json")
    }

    public var selected: Conversation? { conversations.first { $0.id == selectedID } }
    public func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }
    public var settings: AssistantSettings { prefs.codingAssistant }

    public var providerKind: ProviderKind { settings.provider }

    public var modelID: String? {
        let chosen = settings.model(for: providerKind)
        if providerKind == .metaAssist, let chosen, !chosen.isEmpty { return chosen }
        let models = availability[providerKind]?.models ?? []
        if let chosen, models.isEmpty || models.contains(where: { $0.id == chosen }) { return chosen }
        return models.first?.id
    }

    public var modelName: String? {
        let id = modelID
        return availability[providerKind]?.models.first { $0.id == id }?.displayName ?? id
    }

    public var sourceLabel: String {
        guard let m = modelName, !m.isEmpty else { return providerKind.displayName }
        return "\(providerKind.displayName) · \(m)"
    }

    public var readyProviders: [ProviderKind] { ProviderKind.allCases.filter { availability[$0]?.isReady == true } }
    public var hasUsableBackend: Bool { !readyProviders.isEmpty }
    public var currentAvailability: ProviderAvailability? { availability[providerKind] }

    public var usesChatGPTPlan: Bool { providerKind == .openAI && settings.openAIAuth == .chatGPT }

    public func choose(_ kind: ProviderKind, model: String?) {
        var s = settings
        s.provider = kind
        if let model { s.setModel(model, for: kind) }
        prefs.codingAssistant = s
        notify(.status)
    }

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

    @discardableResult
    public func newConversation() -> Conversation {
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

    public func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        for i in conversations.indices where conversations[i].groupID == id { conversations[i].groupID = nil }
        notify(.list)
        save()
    }

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

    public var activeIDs: [UUID] { conversations.filter(\.isActive).map(\.id) }
    public func isRunning(_ id: UUID) -> Bool { running[id] != nil }
    public func response(_ id: UUID) -> Task<Void, Never>? { running[id] }

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

    @discardableResult
    public func send(_ text: String, attachments: [Attachment] = [], newConversationTitle: String? = nil, in target: UUID? = nil) -> UUID? {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
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
            let why = availability[kind]?.hint ?? "Choose a model in the model menu."
            finish(id, error: "No \(kind.displayName) model is available. " + why)
            return id
        }
        var provider = services.provider(kind, prefs: prefs)
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
                var window = self?.availability[attemptKind]?.models.first { $0.id == attemptModel }?.contextWindow
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

    public func stop(_ id: UUID) {
        running[id]?.cancel()
    }

    public func stopAll() { for id in Array(running.keys) { stop(id) } }

    public enum MetaSlashCommandHandling: Sendable, Equatable {
        case notACommand
        case inserted
        case handled(UUID)
    }

    @discardableResult
    public func handleMetaSlashCommand(_ text: String) -> MetaSlashCommandHandling {
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
        if metaSlashCommands.lastCapturedAt == nil { refreshMetaSlashCommands() }
        let (_, effect) = metaSlashCommands.executeCommand(command, argument: argument?.isEmpty == true ? nil : argument)
        guard let effect else { return .inserted }
        if case .insertText = effect { return .inserted }

        let knownModels = Set(MetaAssistProvider.fallbackModels.map(\.modelId))
            .union(availability[.metaAssist]?.models.map(\.id) ?? [])
        var outcome = MetaSlashCommandEffectApplier.apply(effect, settings: settings, knownModelIDs: knownModels)
        if case .startLogin = effect,
           let meta = services.provider(.metaAssist, prefs: prefs) as? MetaAssistProvider, meta.hasCredentials() {
            outcome.message = "Assist with Meta is already signed in."
        }
        if outcome.settings != settings {
            prefs.codingAssistant = outcome.settings
            notify(.status)
        }
        if case .setModel(let modelID) = effect {
            Task { try? await MetaAssistTurnExecutor.shared.switchModel(modelID: modelID) }
        }
        if outcome.clearsSession {
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

    private func refreshMetaSlashCommands() {
        guard let meta = services.provider(.metaAssist, prefs: prefs) as? MetaAssistProvider,
              let executable = meta.executableURL() else { return }
        Task { [weak self] in
            guard let self else { return }
            var manager = self.metaSlashCommands
            await manager.captureCommandsFromTerminal(executable: executable)
            self.metaSlashCommands = manager
        }
    }

    public func ensureSlashCommandsCaptured() {
        if metaSlashCommands.lastCapturedAt == nil { refreshMetaSlashCommands() }
    }

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

    func markCutOff(_ id: UUID) {
        update(id) { c in if let i = c.messages.indices.last { c.messages[i].isCutOff = true } }
        scheduleRefresh(id)
    }

    public static let continuePrompt = "Continue exactly where your last reply stopped. Do not repeat anything."

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

    public func resolve(message: UUID, in conversationID: UUID, proposal index: Int, _ r: ProposalResolution) {
        update(conversationID) { c in
            if let i = c.messages.firstIndex(where: { $0.id == message }) { c.messages[i].resolvedProposals[index] = r }
        }
        pendingAgentEdits.removeValue(forKey: AgentEditKey(message: message, block: index))?.done.resume(returning: r == .accepted)
        notify(.transcript(conversationID))
        save()
    }

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

    public func agentProposalText(message: UUID, block: Int) -> String? {
        pendingAgentEdits[AgentEditKey(message: message, block: block)]?.proposed
    }

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
        Self.saveQueue.async { try? ConversationArchive.save(snapshot, to: archiveURL) }
    }

    static let saveQueue = DispatchQueue(label: "dev.swiftcode.conversations", qos: .utility)

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
