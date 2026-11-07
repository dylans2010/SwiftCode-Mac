import Foundation
import Observation
import YcodeAssistant
import YcodeIDECore

@MainActor
@Observable
public final class ShellAssistantModel {
    @ObservationIgnored public weak var workspace: WorkspaceShellModel?

    public var isShown = false
    public private(set) var core: CodingAssistantModel?
    public private(set) var revision = 0
    public var draft = ""
    public private(set) var attachments: [Attachment] = []
    public var review: AssistantChangeReview?
    public var alertText: String?
    public private(set) var focusCount = 0
    public var isPromptShown = false
    public var promptDraft = ""
    public var renamingID: UUID?
    public var renameText = ""
    @ObservationIgnored public var onOpenSettings: (() -> Void)?
    @ObservationIgnored public var services: CodingAssistantServices?

    @ObservationIgnored private var lastSettings: AssistantSettings?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var previewCache: [String: AssistantChangePreview] = [:]
    @ObservationIgnored private var decidedDiffs: [String: AssistantChangeDiff] = [:]

    public static let credentialsDidChange = Notification.Name("SwiftCodeShellAssistantCredentialsDidChange")

    public init() {}

    @discardableResult
    public func ensure() -> CodingAssistantModel {
        if let core { return core }
        let services = services ?? CodingAssistantServices.shared
        let prefs = services.preferences ?? .shared
        let root = workspace?.assistantFolder ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let archive = IDEProcess.isTestProcess ? nil : workspace.map { CodingAssistantModel.archiveURL(forWorkspace: $0.session.model.url) }
        let m = CodingAssistantModel(workspaceRoot: root, archiveURL: archive, prefs: prefs, services: services)
        m.contextProvider = { [weak self] in self?.workspace?.assistantContext() ?? WorkspaceContext() }
        m.observe(owner: self) { [weak self] _ in self?.revision &+= 1 }
        core = m
        lastSettings = prefs.codingAssistant
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: Preferences.didChange, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.settingsChanged() }
            },
            center.addObserver(forName: Self.credentialsDidChange, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in _ = self?.core?.refreshAvailability() }
            },
        ]
        m.refreshAvailability()
        return m
    }

    private func settingsChanged() {
        guard let core else { return }
        let now = core.settings, before = lastSettings
        lastSettings = now
        guard now != before else { return }
        if now.ollamaURL != before?.ollamaURL || now.llamaCppURL != before?.llamaCppURL || now.openAIURL != before?.openAIURL
            || now.openAIAuth != before?.openAIAuth || now.toolPaths != before?.toolPaths || now.acpCommand != before?.acpCommand {
            core.refreshAvailability()
        } else {
            revision &+= 1
        }
    }

    public var outline: [ConversationLibrary.Node] { _ = revision; return core?.library.outline ?? [ConversationLibrary.Node.archive([])] }
    public var selectedID: UUID? { _ = revision; return core?.selectedID }
    public var selected: Conversation? { _ = revision; return core?.selected }
    public var groups: [ConversationGroup] { _ = revision; return core?.library.groups ?? [] }
    public var sourceLabel: String { _ = revision; return core?.sourceLabel ?? CodingAssistantModel.placeholderLabel }
    public var isSurveying: Bool { _ = revision; return core?.isSurveying ?? false }
    public var hasUsableBackend: Bool { _ = revision; return core?.hasUsableBackend ?? false }
    public var usesChatGPTPlan: Bool { _ = revision; return core?.usesChatGPTPlan ?? false }
    public var isResponding: Bool {
        _ = revision
        guard let core, let id = core.selectedID else { return false }
        return core.isRunning(id)
    }
    public var hasActiveConversations: Bool { _ = revision; return !(core?.activeIDs.isEmpty ?? true) }
    public var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding }

    public var status: AssistantStatus? {
        _ = revision
        guard let core else { return nil }
        if core.isSurveying && core.availability.isEmpty { return AssistantStatus(text: "Looking for models…", alternatives: [], checking: true) }
        guard let a = core.currentAvailability, !a.isReady else { return nil }
        if !core.hasUsableBackend { return AssistantStatus(text: AssistantBackends.noBackendText, alternatives: [], checking: false) }
        return AssistantStatus(text: "\(core.providerKind.displayName): " + (a.hint ?? "unavailable."),
                               alternatives: Array(core.readyProviders.prefix(3)), checking: false)
    }

    public var providerChoices: [AssistantProviderChoice] {
        _ = revision
        guard let core else { return [] }
        let currentModel = core.modelID ?? ""
        return ProviderKind.allCases.map { kind in
            let a = core.availability[kind]
            let models = a?.models ?? []
            let rows = models.isEmpty
                ? [AssistantProviderChoice.Model(id: nil, title: "Choose \(kind.displayName)", isCurrent: kind == core.providerKind)]
                : models.map { m in
                    AssistantProviderChoice.Model(id: m.id, title: m.displayName.isEmpty ? "Default" : m.displayName,
                                                  isCurrent: kind == core.providerKind && m.id == currentModel)
                }
            return AssistantProviderChoice(kind: kind, title: kind.displayName + Self.stateSuffix(a), isReady: a?.isReady == true, models: rows)
        }
    }

    public static func stateSuffix(_ a: ProviderAvailability?) -> String {
        switch a {
        case nil: " (checking…)"
        case .ready?: ""
        case .notRunning?: " (not running)"
        case .noModels?: " (no models)"
        case .notInstalled?: " (not installed)"
        case .signedOut?: " (not signed in)"
        case .failed?: " (unavailable)"
        }
    }

    public func show() {
        ensure()
        isShown = true
        workspace?.isNavigatorShown = true
    }

    public func newConversation() {
        show()
        core?.newConversation()
        focusCount &+= 1
    }

    public func togglePrompt() {
        ensure()
        isPromptShown.toggle()
    }

    @discardableResult
    public func sendPrompt() -> UUID? {
        let text = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        isPromptShown = false
        promptDraft = ""
        show()
        let core = ensure()
        return core.send(text, in: core.newConversation().id)
    }

    @discardableResult
    public func jumpToNextActive() -> Bool {
        guard let core, core.selectNextActive() != nil else { return false }
        show()
        return true
    }

    public func select(_ id: UUID) {
        ensure().selectedID = id
        renamingID = nil
    }

    public func openSettings() { onOpenSettings?() }
    public func checkAgain() { ensure().refreshAvailability() }
    public func choose(_ kind: ProviderKind, model: String?) { ensure().choose(kind, model: model) }

    public func newGroup() {
        let g = ensure().newGroup()
        beginRename(g.id, title: g.title)
    }

    public func beginRename(_ id: UUID, title: String) {
        renamingID = id
        renameText = title
    }

    public func commitRename() {
        guard let id = renamingID, let core else { return }
        renamingID = nil
        if core.library.groups.contains(where: { $0.id == id }) {
            core.renameGroup(id, to: renameText)
        } else {
            core.rename(id, to: renameText.trimmingCharacters(in: .whitespaces))
        }
    }

    public func delete(_ id: UUID) { core?.delete(id) }
    public func deleteGroup(_ id: UUID) { core?.deleteGroup(id) }
    public func setArchived(_ id: UUID, _ archived: Bool) { core?.setArchived(id, archived) }
    public func move(_ id: UUID, toGroup group: UUID?) { core?.move(id, toGroup: group) }

    public var attachmentChoices: (file: Attachment?, selection: Attachment?) {
        guard let ctx = workspace?.assistantContext() else { return (nil, nil) }
        let file = ctx.currentFile.map { Attachment(kind: .file, path: $0.path, text: $0.text) }
        let sel = ctx.selection.map { Attachment(kind: .selection, path: $0.path, startLine: $0.startLine, endLine: $0.endLine, text: $0.text) }
        return (file, sel)
    }

    public func attach(_ a: Attachment) {
        if !attachments.contains(a) { attachments.append(a) }
    }

    public func removeAttachment(_ a: Attachment) { attachments.removeAll { $0 == a } }

    @discardableResult
    public func send() -> UUID? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return nil }
        let id = ensure().send(text, attachments: attachments)
        if id != nil {
            draft = ""
            attachments = []
        }
        return id
    }

    public func stop() {
        guard let core, let id = core.selectedID else { return }
        core.stop(id)
    }

    public func continueReply(in id: UUID) { core?.continueReply(in: id) }

    public func canRun(_ tool: CodingTool) -> Bool {
        guard let w = workspace, let e = w.editor, e.readOnlyReason == nil else { return false }
        if let core, !core.availability.isEmpty, !core.hasUsableBackend { return false }
        return tool.applies(toPath: e.path, text: e.buffer.text)
    }

    @discardableResult
    public func run(_ tool: CodingTool) -> UUID? {
        guard canRun(tool) else { return nil }
        show()
        return core?.run(tool)
    }

    public func proposals(in message: ConversationMessage) -> [ChangeProposal] {
        guard message.role == .assistant else { return [] }
        return ChangeProposal.parse(message.text, target: message.target)
    }

    public func undecided(in message: ConversationMessage) -> [ChangeProposal] {
        proposals(in: message).filter { message.resolvedProposals[$0.blockIndex] == nil }
    }

    public func preview(_ p: ChangeProposal, in message: ConversationMessage) -> AssistantChangePreview {
        guard let w = workspace else { return .failed("No workspace is open.") }
        guard let path = w.assistantPath(p.path) else {
            return .failed("The proposal names a file outside the workspace (\(p.path)); it can't be applied.")
        }
        let original = w.assistantCurrentText(path)
        let key = "\(message.id) \(p.blockIndex) \(p.text.hashValue) \(original?.hashValue ?? 0)"
        if let cached = previewCache[key] { return cached }
        let proposed: String
        do {
            proposed = try ensure().agentProposalText(message: message.id, block: p.blockIndex) ?? p.apply(to: original, target: message.target)
        } catch {
            return .failed(error.localizedDescription)
        }
        let r = AssistantChangePreview.ready(AssistantChangeDiff(path: path, relativePath: p.path, original: original, proposed: proposed))
        if previewCache.count > 200 { previewCache = [:] }
        previewCache[key] = r
        return r
    }

    @discardableResult
    public func accept(_ p: ChangeProposal, message: ConversationMessage, conversation: UUID) -> Bool {
        guard message.resolvedProposals[p.blockIndex] == nil else { return false }
        guard case .ready(let diff) = preview(p, in: message), let w = workspace else {
            if case .failed(let why) = preview(p, in: message) { alertText = why }
            return false
        }
        let isAgent = core?.agentProposalText(message: message.id, block: p.blockIndex) != nil
        decidedDiffs["\(message.id) \(p.blockIndex)"] = diff
        var applied = false
        if let error = w.applyAssistantChange(diff, save: isAgent) { alertText = error } else { applied = true }
        core?.resolve(message: message.id, in: conversation, proposal: p.blockIndex, applied ? .accepted : .rejected)
        return applied
    }

    public func reject(_ p: ChangeProposal, message: ConversationMessage, conversation: UUID) {
        guard message.resolvedProposals[p.blockIndex] == nil else { return }
        if case .ready(let d) = preview(p, in: message) { decidedDiffs["\(message.id) \(p.blockIndex)"] = d }
        core?.resolve(message: message.id, in: conversation, proposal: p.blockIndex, .rejected)
    }

    public func acceptAll(in message: ConversationMessage, conversation: UUID) {
        for p in undecided(in: message) {
            guard let m = core?.conversation(conversation)?.messages.first(where: { $0.id == message.id }) else { return }
            accept(p, message: m, conversation: conversation)
        }
    }

    public func rejectAll(in message: ConversationMessage, conversation: UUID) {
        for p in undecided(in: message) { reject(p, message: message, conversation: conversation) }
    }

    public func decidedDiff(_ p: ChangeProposal, in message: ConversationMessage) -> AssistantChangeDiff? {
        decidedDiffs["\(message.id) \(p.blockIndex)"]
    }

    public func openReview(_ p: ChangeProposal, message: ConversationMessage, conversation: UUID) {
        if message.resolvedProposals[p.blockIndex] != nil, let d = decidedDiff(p, in: message) {
            review = AssistantChangeReview(conversation: conversation, message: message.id, proposal: p, diff: d,
                                           decided: message.resolvedProposals[p.blockIndex])
            return
        }
        switch preview(p, in: message) {
        case .failed(let why): alertText = why
        case .ready(let diff):
            review = AssistantChangeReview(conversation: conversation, message: message.id, proposal: p, diff: diff,
                                           decided: message.resolvedProposals[p.blockIndex])
        }
    }

    public func acceptReview() {
        guard let r = review else { return }
        review = nil
        guard let m = core?.conversation(r.conversation)?.messages.first(where: { $0.id == r.message }) else { return }
        accept(r.proposal, message: m, conversation: r.conversation)
    }

    public func rejectReview() {
        guard let r = review else { return }
        review = nil
        guard let m = core?.conversation(r.conversation)?.messages.first(where: { $0.id == r.message }) else { return }
        reject(r.proposal, message: m, conversation: r.conversation)
    }

    public static func proposalTitle(_ p: ChangeProposal) -> String {
        switch p.kind {
        case .wholeFile: "Proposed: \(p.path)"
        case .replaceSelection: "Proposed: replace the selection in \((p.path as NSString).lastPathComponent)"
        case .append: "Proposed: add to \((p.path as NSString).lastPathComponent)"
        }
    }
}

extension CodingAssistantModel {
    static let placeholderLabel = "Coding Assistant"
}

public struct AssistantStatus: Equatable, Sendable {
    public var text: String
    public var alternatives: [ProviderKind]
    public var checking: Bool
}

public struct AssistantProviderChoice: Equatable, Sendable, Identifiable {
    public struct Model: Equatable, Sendable {
        public var id: String?
        public var title: String
        public var isCurrent: Bool
    }
    public var kind: ProviderKind
    public var title: String
    public var isReady: Bool
    public var models: [Model]
    public var id: String { kind.rawValue }
}

public enum AssistantChangePreview: Equatable, Sendable {
    case ready(AssistantChangeDiff)
    case failed(String)
}

public struct AssistantChangeDiff: Equatable, Sendable {
    public var path: String
    public var relativePath: String
    public var original: String?
    public var proposed: String
    public let lines: [AssistantDiffLine]
    public let rows: [LineDiff.Row]
    public let added: Int
    public let removed: Int

    public init(path: String, relativePath: String, original: String?, proposed: String) {
        self.path = path
        self.relativePath = relativePath
        self.original = original
        self.proposed = proposed
        let ops = LineDiff.diff(LineDiff.lines(original ?? ""), LineDiff.lines(proposed))
        lines = AssistantDiffLine.unified(ops)
        rows = LineDiff.sideBySide(ops)
        added = ops.filter { if case .added = $0 { true } else { false } }.count
        removed = ops.filter { if case .removed = $0 { true } else { false } }.count
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var isNewFile: Bool { original == nil }

    public var title: String {
        isNewFile ? "Create \(relativePath)" : "Change \(name): +\(added) \u{2212}\(removed) lines"
    }

    public var currentTitle: String { "\(name) (Current)" }
    public var proposedTitle: String { "\(name) (Proposed)" }

    public static func == (a: Self, b: Self) -> Bool {
        a.path == b.path && a.original == b.original && a.proposed == b.proposed
    }
}

public struct AssistantDiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case context, added, removed, gap }
    public var kind: Kind
    public var old: Int?
    public var new: Int?
    public var text: String

    public static func unified(_ ops: [LineDiff.Op], context: Int = 3) -> [AssistantDiffLine] {
        var numbered: [AssistantDiffLine] = []
        var o = 0, n = 0
        for op in ops {
            switch op {
            case .same(let s): o += 1; n += 1; numbered.append(.init(kind: .context, old: o, new: n, text: s))
            case .removed(let s): o += 1; numbered.append(.init(kind: .removed, old: o, new: nil, text: s))
            case .added(let s): n += 1; numbered.append(.init(kind: .added, old: nil, new: n, text: s))
            }
        }
        let changed = numbered.indices.filter { numbered[$0].kind != .context }
        guard !changed.isEmpty else { return [] }
        var keep = Set<Int>()
        for c in changed { for k in max(0, c - context)...min(numbered.count - 1, c + context) { keep.insert(k) } }
        var out: [AssistantDiffLine] = []
        var last = -1
        for k in keep.sorted() {
            if last >= 0, k != last + 1 { out.append(.init(kind: .gap, old: nil, new: nil, text: "")) }
            out.append(numbered[k])
            last = k
        }
        return out
    }
}

public struct AssistantChangeReview: Identifiable, Equatable, Sendable {
    public var conversation: UUID
    public var message: UUID
    public var proposal: ChangeProposal
    public var diff: AssistantChangeDiff
    public var decided: ProposalResolution?
    public var id: String { "\(message) \(proposal.blockIndex)" }
    public var acceptTitle: String { diff.isNewFile ? "Create File" : "Accept" }
}

public enum AssistantInline {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var code = false
        public var bold = false
        public var italic = false
    }

    public static func runs(_ s: String) -> [Run] {
        var out: [Run] = []
        var i = s.startIndex
        var plain = ""
        var bold = false, italic = false
        func flush() {
            if !plain.isEmpty { out.append(Run(text: plain, bold: bold, italic: italic)) }
            plain = ""
        }
        while i < s.endIndex {
            let c = s[i]
            if c == "`", let end = s[s.index(after: i)...].firstIndex(of: "`") {
                flush()
                out.append(Run(text: String(s[s.index(after: i)..<end]), code: true))
                i = s.index(after: end)
                continue
            }
            if c == "*" || c == "_" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next] == c {
                    flush()
                    bold.toggle()
                    i = s.index(after: next)
                    continue
                }
                let before = i > s.startIndex ? s[s.index(before: i)] : " "
                let after = next < s.endIndex ? s[next] : " "
                if (italic && !before.isWhitespace) || (!italic && !after.isWhitespace && (before.isWhitespace || before.isPunctuation)) {
                    flush()
                    italic.toggle()
                    i = next
                    continue
                }
            }
            plain.append(c)
            i = s.index(after: i)
        }
        flush()
        return out
    }
}
