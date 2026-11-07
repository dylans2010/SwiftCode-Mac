import AppKit
import SwiftCodeAssistant
import SwiftCodeIDECore
import SwiftCodeMCP

@MainActor
final class AgentModeHolder {
    var host: SwiftCodeMCPHost?
    var permissionResponder: ((String, [AgentAttachment.PermissionOption]) -> String?)?
    var extensionChangePresenter = ExtensionChangeReviewPresenter()
    var endpoints: [UUID: MCPHTTPTransport] = [:]
}

extension WorkspaceWindowController: SwiftCodeMCPHostDelegate {
    public var mcpHost: SwiftCodeMCPHost {
        if let h = agentModeHolder.host { return h }
        let h = SwiftCodeMCPHost(server: MCPServer(name: "swiftcode", version: MCPCommand.swiftcodeVersion, title: "SwiftCode"), session: session)
        h.delegate = self
        agentModeHolder.host = h
        let presenter = agentModeHolder.extensionChangePresenter
        h.server.writePolicy = .review { [weak presenter] change in
            await presenter?.review(change) ?? false
        }
        SwiftCodeSDKToolServerRegistry.current = h.server
        return h
    }

    public var extensionChangePresenter: ExtensionChangeReviewPresenter {
        agentModeHolder.extensionChangePresenter
    }

    public var agentPermissionResponder: ((String, [AgentAttachment.PermissionOption]) -> String?)? {
        get { agentModeHolder.permissionResponder }
        set { agentModeHolder.permissionResponder = newValue }
    }

    public var agentEndpoints: [UUID: String] { agentModeHolder.endpoints.mapValues(\.endpoint) }

    func installAgentMode(_ model: CodingAssistantModel) {
        model.agentAttachment = { [weak self, weak model] id in
            guard let self, let model else { return nil }
            return self.agentAttachment(for: id, model: model)
        }
    }

    func agentAttachment(for id: UUID, model: CodingAssistantModel) -> (AgentAttachment, () -> Void)? {
        let host = mcpHost
        host.remoteSimulator = RemoteSimulatorSettings.load(Preferences.shared.defaults)
        let base = host.server
        let server = MCPServer(name: base.name, version: base.version, title: base.title, instructions: base.instructions)
        server.tools = base.tools
        server.resources = base.resources
        server.prompts = base.prompts
        let propose: @Sendable (String, String?, String, String) async -> Bool = { [weak model] path, _, proposed, _ in
            await model?.proposeAgentChange(in: id, path: path, proposed: proposed) ?? false
        }
        server.writePolicy = .review { change in await propose(change.path, change.original, change.proposed, change.summary) }
        guard let transport = try? MCPHTTPTransport(server: server) else { return nil }
        agentModeHolder.endpoints[id] = transport
        let attachment = AgentAttachment(
            mcp: .init(url: transport.endpoint, token: transport.token),
            proposeChange: propose,
            requestPermission: { [weak self] title, options in await self?.askAgentPermission(title, options) },
            readFile: { [weak self] path in await self?.agentReadFile(path) })
        return (attachment, { [weak self] in
            transport.stop()
            self?.agentModeHolder.endpoints[id] = nil
        })
    }

    func agentReadFile(_ path: String) -> String? {
        mcpHostText(ofOpenFile: path) ?? (try? String(contentsOfFile: path, encoding: .utf8))
    }

    func askAgentPermission(_ title: String, _ options: [AgentAttachment.PermissionOption]) async -> String? {
        if let r = agentModeHolder.permissionResponder { return r(title, options) }
        guard let w = window, w.isVisible, !options.isEmpty else { return options.first { !$0.allows }?.id }
        let alert = NSAlert()
        alert.messageText = "The agent asks for permission"
        alert.informativeText = title
        let shown = Array(options.prefix(4))
        for o in shown { alert.addButton(withTitle: o.name) }
        let response = await alert.beginSheetModal(for: w)
        let i = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return shown.indices.contains(i) ? shown[i].id : nil
    }

    public func mcpHostText(ofOpenFile path: String) -> String? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return editorArea.allEditors.first { $0.fileURL?.standardizedFileURL == url }?.text
    }

    public func mcpHostSaveAll() {
        for e in editorArea.allEditors where e.isDirty { try? e.save() }
        try? session.model.saveProjects()
    }

    public func mcpHostDidWrite(_ path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else { return }
        for e in editorArea.allEditors where e.fileURL?.standardizedFileURL == url && !e.isDirty && e.text != disk {
            _ = e.replaceText(with: disk, actionName: "Agent Change")
            try? e.save()
        }
    }

    @objc public func installSwiftCodeSkill(_ sender: Any?) {
        let folder = workspaceFolder
        let paths = AgentSkill.paths.map { folder.appendingPathComponent($0).path }
        let write = { [weak self] in
            guard let self else { return }
            do {
                try AgentSkill.install(into: folder, tools: mcpHost.server.tools)
            } catch {
                presentAssistantAlert("SwiftCode could not write the skill: \(error.localizedDescription)")
            }
        }
        guard let w = window, w.isVisible else { write(); return }
        let alert = NSAlert()
        alert.messageText = "Install the SwiftCode skill in “\(session.model.displayName)”?"
        alert.informativeText = "Agents that read skills learn SwiftCode's tools and the build-and-run workflow from it. SwiftCode writes:\n" + paths.joined(separator: "\n")
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: w) { r in if r == .alertFirstButtonReturn { write() } }
    }
}
