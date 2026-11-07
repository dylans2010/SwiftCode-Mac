import AppKit
import SwiftCodeAssistant
import SwiftCodeBuild
import SwiftCodeIDECore
import SwiftCodeMCP

final class CodingAssistantHolder: NSObject, NSPopoverDelegate {
    var controller: CodingAssistantViewController?
    var tokens: [NSObjectProtocol] = []
    var lastSettings: AssistantSettings?
    weak var review: ProposalReviewController?
    var prompt: NewConversationPromptController?
    var popover: NSPopover?

    func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            prompt = nil
            popover = nil
        }
    }
}

extension WorkspaceWindowController {
    public var workspaceFolder: URL {
        (session.model.kind == .package ? session.model.url : session.model.url.deletingLastPathComponent()).standardizedFileURL
    }

    public var codingAssistant: CodingAssistantViewController {
        if let c = codingAssistantHolder.controller { return c }
        let services = CodingAssistantServices.shared
        let prefs = services.preferences ?? .shared
        let model = CodingAssistantModel(workspaceRoot: workspaceFolder,
                                         archiveURL: Self.isTestProcess ? nil : CodingAssistantModel.archiveURL(forWorkspace: session.model.url),
                                         prefs: prefs, services: services)
        model.contextProvider = { [weak self] in self?.codingAssistantContext() ?? WorkspaceContext() }
        model.mcpToolIDsProvider = { [weak self] in
            guard let host = self?.mcpHost else { return [] }
            return Set(host.server.tools.map(\.name)).union(MCPServer.toolAliases.keys)
        }
        installAgentMode(model)
        let c = CodingAssistantViewController(model: model)
        c.onReviewProposal = { [weak self] p, m, conversation in self?.reviewProposal(p, message: m, conversation: conversation) }
        c.onOpenSettings = { SettingsWindowController.shared.show(pane: CodingAssistantSettingsPane.paneTitle) }
        c.attachmentSource = { [weak self] in self?.currentAttachments() ?? (nil, nil) }
        codingAssistantHolder.controller = c
        navigator.assistantContent = c.view
        codingAssistantHolder.lastSettings = prefs.codingAssistant
        let center = NotificationCenter.default
        codingAssistantHolder.tokens = [
            center.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.codingAssistantSettingsChanged() }
            },
            center.addObserver(forName: CodingAssistantSettingsPane.credentialsDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.codingAssistantHolder.controller?.model.refreshAvailability() }
            },
        ]
        model.refreshAvailability()
        return c
    }

    public var codingAssistantModel: CodingAssistantModel { codingAssistant.model }

    func codingAssistantSettingsChanged() {
        guard let c = codingAssistantHolder.controller else { return }
        let now = c.model.prefs.codingAssistant
        let before = codingAssistantHolder.lastSettings
        codingAssistantHolder.lastSettings = now
        guard now != before else { return }
        if now.ollamaURL != before?.ollamaURL || now.llamaCppURL != before?.llamaCppURL || now.openAIURL != before?.openAIURL
            || now.openAIAuth != before?.openAIAuth || now.toolPaths != before?.toolPaths {
            c.model.refreshAvailability()
        } else {
            c.apply(.status)
        }
    }

    func revealCodingAssistant() {
        if navigatorItem.isCollapsed || !navigator.showsCodingAssistant { setLeftPane(codingAssistant: true) }
    }

    @objc public func newConversation(_ sender: Any?) {
        revealCodingAssistant()
        codingAssistant.model.newConversation()
        codingAssistant.focusMessageField()
    }

    @objc public func newConversationInNewTab(_ sender: Any?) {
        let id = codingAssistant.model.newConversation().id
        let e = editorArea.newTab()
        showConversation(id, in: e)
        editorArea.reloadTabBar()
    }

    @objc public func newConversationInEditorPane(_ sender: Any?) {
        let id = codingAssistant.model.newConversation().id
        let t = editorArea.tab
        let panes = t.editors.filter { $0 !== t.assistant }
        let next: SourceEditorController
        if panes.count > 1, let i = panes.firstIndex(where: { $0 === t.focusedEditor }) {
            next = panes[(i + 1) % panes.count]
        } else {
            next = editorArea.split(sideBySide: true)
        }
        editorArea.focus(next)
        showConversation(id, in: next)
    }

    @discardableResult
    public func showConversation(_ id: UUID, in e: SourceEditorController) -> ConversationView {
        let model = codingAssistant.model
        let v = ConversationView(model: model, conversation: id)
        v.onReviewProposal = { [weak self] p, m, conversation in self?.reviewProposal(p, message: m, conversation: conversation) }
        v.onOpenSettings = { SettingsWindowController.shared.show(pane: CodingAssistantSettingsPane.paneTitle) }
        v.attachmentSource = { [weak self] in self?.currentAttachments() ?? (nil, nil) }
        let title = model.conversation(id)?.title ?? Conversation.untitled
        e.showText("", title: title)
        e.showAuxiliary(v, path: Self.conversationPath(title))
        v.onTitleChange = { [weak self, weak e, weak v] t in
            guard let self, let e, let v, e.auxiliary === v else { return }
            e.pathComponents = Self.conversationPath(t)
            editorArea.reloadTabBar()
        }
        updateWindowTitle()
        if window?.isVisible == true { window?.makeFirstResponder(v.messageView) }
        return v
    }

    static func conversationPath(_ title: String) -> [(String, String)] {
        [("Conversations", "bubble.left.and.bubble.right"), (title, "bubble.left")]
    }

    @objc public func toggleNewConversationPrompt(_ sender: Any?) {
        if codingAssistantHolder.prompt != nil { closeNewConversationPrompt(); return }
        let model = codingAssistant.model
        let c = NewConversationPromptController(model: model)
        c.attachmentSource = { [weak self] in self?.currentAttachments() ?? (nil, nil) }
        c.onOpenSettings = { SettingsWindowController.shared.show(pane: CodingAssistantSettingsPane.paneTitle) }
        c.onCancel = { [weak self] in self?.closeNewConversationPrompt() }
        c.onSend = { [weak self] text, attachments in self?.startConversation(prompt: text, attachments: attachments) }
        codingAssistantHolder.prompt = c
        _ = c.view
        guard window?.isVisible == true,
              let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.newConversationID }) else { return }
        let p = NSPopover()
        p.contentViewController = c
        p.contentSize = NewConversationPromptController.size
        p.behavior = .transient
        p.delegate = codingAssistantHolder
        codingAssistantHolder.popover = p
        p.show(relativeTo: item)
    }

    public var newConversationPrompt: NewConversationPromptController? { codingAssistantHolder.prompt }

    public func closeNewConversationPrompt() {
        let p = codingAssistantHolder.popover
        codingAssistantHolder.prompt = nil
        codingAssistantHolder.popover = nil
        p?.close()
    }

    @discardableResult
    public func startConversation(prompt: String, attachments: [Attachment] = []) -> UUID? {
        closeNewConversationPrompt()
        revealCodingAssistant()
        let model = codingAssistant.model
        let id = model.newConversation().id
        return model.send(prompt, attachments: attachments, in: id)
    }

    @objc public func jumpToNextActiveConversation(_ sender: Any?) {
        guard codingAssistant.model.selectNextActive() != nil else { return NSSound.beep() }
        revealCodingAssistant()
    }

    @objc public func codingToolExplain(_ sender: Any?) { runCodingTool(.explain) }
    @objc public func codingToolDocument(_ sender: Any?) { runCodingTool(.document) }
    @objc public func codingToolGeneratePlayground(_ sender: Any?) { runCodingTool(.generatePlayground) }
    @objc public func codingToolGeneratePreview(_ sender: Any?) { runCodingTool(.generatePreview) }

    @discardableResult
    public func runCodingTool(_ tool: CodingTool) -> UUID? {
        guard canRunCodingTool(tool) else { NSSound.beep(); return nil }
        revealCodingAssistant()
        return codingAssistant.model.run(tool)
    }

    public func canRunCodingTool(_ tool: CodingTool) -> Bool {
        guard let url = editor.fileURL, editor.textView.isEditable else { return false }
        if let m = codingAssistantHolder.controller?.model, !m.availability.isEmpty, !m.hasUsableBackend { return false }
        return tool.applies(toPath: url.path, text: editor.text)
    }

    func validateCodingAssistantItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(newConversation(_:)), #selector(newConversationInNewTab(_:)), #selector(newConversationInEditorPane(_:)),
             #selector(toggleNewConversationPrompt(_:)):
            return true
        case #selector(filterInNavigator(_:)): return shownLeftPane != .codingAssistant
        case #selector(jumpToNextActiveConversation(_:)):
            return codingAssistantHolder.controller.map { !$0.model.activeIDs.isEmpty } ?? false
        case #selector(codingToolExplain(_:)): return canRunCodingTool(.explain)
        case #selector(codingToolDocument(_:)): return canRunCodingTool(.document)
        case #selector(codingToolGeneratePlayground(_:)): return canRunCodingTool(.generatePlayground)
        case #selector(codingToolGeneratePreview(_:)): return canRunCodingTool(.generatePreview)
        default: return nil
        }
    }

    func relativePath(_ url: URL) -> String {
        let root = workspaceFolder.path.hasSuffix("/") ? workspaceFolder.path : workspaceFolder.path + "/"
        let p = url.standardizedFileURL.path
        return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : p
    }

    public func codingAssistantContext() -> WorkspaceContext {
        var ctx = WorkspaceContext(workspaceName: session.model.displayName)
        let e = editor
        if let url = e.fileURL {
            let text = e.text
            let path = relativePath(url)
            ctx.currentFile = .init(path: path, text: text)
            let sel = e.textView.selectedRange()
            let index = LineIndex(text)
            ctx.caretLine = index.line(at: sel.location)
            if sel.length > 0, NSMaxRange(sel) <= (text as NSString).length {
                let s = (text as NSString).substring(with: sel)
                let endOffset = max(sel.location, NSMaxRange(sel) - 1)
                ctx.selection = .init(path: path, startLine: index.line(at: sel.location), endLine: index.line(at: endOffset), text: s,
                                      location: sel.location, length: sel.length)
            }
        }
        var seen = Set(ctx.currentFile.map { [$0.path] } ?? [])
        for other in editorArea.allEditors where other !== e {
            guard let url = other.fileURL else { continue }
            let path = relativePath(url)
            if seen.insert(path).inserted { ctx.openFiles.append(.init(path: path, text: other.text)) }
        }
        ctx.issues = session.displayedIssues.prefix(100).map { d in
            WorkspaceContext.Issue(severity: d.severity.rawValue, message: d.message, path: d.location.map { relativePath(URL(fileURLWithPath: $0.file)) },
                                   line: d.location?.line)
        }
        return ctx
    }

    func currentAttachments() -> (file: Attachment?, selection: Attachment?) {
        let ctx = codingAssistantContext()
        let file = ctx.currentFile.map { Attachment(kind: .file, path: $0.path, text: $0.text) }
        let sel = ctx.selection.map { Attachment(kind: .selection, path: $0.path, startLine: $0.startLine, endLine: $0.endLine, text: $0.text) }
        return (file, sel)
    }

    func proposalURL(_ p: ChangeProposal) -> URL? {
        let url = workspaceFolder.appendingPathComponent(p.path).standardizedFileURL
        let root = workspaceFolder.path.hasSuffix("/") ? workspaceFolder.path : workspaceFolder.path + "/"
        return url.path.hasPrefix(root) ? url : nil
    }

    func currentText(of url: URL) -> String? {
        if let e = editorArea.allEditors.first(where: { $0.fileURL?.standardizedFileURL == url }) { return e.text }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    @discardableResult
    public func reviewProposal(_ p: ChangeProposal, message: ConversationMessage, conversation: UUID) -> ProposalReviewController? {
        guard let url = proposalURL(p) else {
            presentAssistantAlert("The proposal names a file outside the workspace (\(p.path)); it was not applied.")
            return nil
        }
        let original = currentText(of: url)
        let agentText = codingAssistant.model.agentProposalText(message: message.id, block: p.blockIndex)
        let proposed: String
        do {
            proposed = try agentText ?? p.apply(to: original, target: message.target)
        } catch {
            presentAssistantAlert(error.localizedDescription)
            return nil
        }
        let review = ProposalReviewController(proposal: p, original: original, proposed: proposed)
        review.onDecision = { [weak self] ok in
            guard let self else { return }
            var applied = ok && applyProposal(url: url, original: original, proposed: proposed)
            if applied, agentText != nil, let e = editorArea.allEditors.first(where: { $0.fileURL?.standardizedFileURL == url }) {
                do { try e.save() } catch {
                    presentAssistantAlert("SwiftCode could not save \(url.lastPathComponent): \(error.localizedDescription)")
                    applied = false
                }
            }
            codingAssistant.model.resolve(message: message.id, in: conversation, proposal: p.blockIndex, applied ? .accepted : .rejected)
        }
        codingAssistantHolder.review = review
        if let content = window?.contentViewController, window?.isVisible == true {
            content.presentAsSheet(review)
        } else {
            _ = review.view
        }
        return review
    }

    public var proposalReview: ProposalReviewController? { codingAssistantHolder.review }

    func applyProposal(url: URL, original: String?, proposed: String) -> Bool {
        if original == nil {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try proposed.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                presentAssistantAlert("SwiftCode could not create \(url.lastPathComponent): \(error.localizedDescription)")
                return false
            }
            open(path: url.path, line: nil)
            return true
        }
        if editor.fileURL?.standardizedFileURL != url { open(path: url.path, line: nil) }
        guard editor.fileURL?.standardizedFileURL == url else { return false }
        return editor.replaceText(with: proposed, actionName: "Apply Coding Assistant Change") || editor.text == proposed
    }

    func presentAssistantAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "The change can't be applied"
        alert.informativeText = text
        if let w = window, w.isVisible { alert.beginSheetModal(for: w) } else { NSSound.beep() }
    }
}
