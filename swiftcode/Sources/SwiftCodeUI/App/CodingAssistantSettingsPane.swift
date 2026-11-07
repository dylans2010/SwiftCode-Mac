import AppKit
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore
import SwiftCodeMCP

@MainActor
public final class CodingAssistantSettingsPane: SettingsPane {
    public static let paneTitle = "Coding Assistant"
    let services: CodingAssistantServices
    public private(set) var accountMessage = ""
    public private(set) var githubMessage = ""
    public private(set) var signInTask: Task<Void, Never>?
    public private(set) var githubValidationTask: Task<Void, Never>?

    public init(prefs: Preferences = .shared, services: CodingAssistantServices = .shared) {
        self.services = services
        super.init(Self.paneTitle, prefs: prefs)
    }

    var settings: AssistantSettings {
        get { prefs.codingAssistant }
        set { prefs.codingAssistant = newValue }
    }

    static let openAIAuthTitles: [AssistantSettings.OpenAIAuth: String] = [.chatGPT: "Sign in with ChatGPT", .apiKey: "API key"]

    override func build() {
        let s = settings
        heading("Model Provider")
        row("Use:", popUp(ProviderKind.allCases.map(\.displayName), selected: s.provider.displayName) { [weak self] title in
            guard let self, let k = ProviderKind.allCases.first(where: { $0.displayName == title }) else { return }
            settings.provider = k
        })
        note("Choose the model itself in the Coding Assistant pane's model menu.")

        heading("Model Routing")
        row("Routing:", popUp(AssistRoutingStrategy.allCases.map(\.displayName), selected: s.routingStrategy.displayName) { [weak self] title in
            guard let self, let r = AssistRoutingStrategy.allCases.first(where: { $0.displayName == title }) else { return }
            settings.routingStrategy = r
        })
        note("Provider default uses the model chosen above. App model catalog considers every eligible model from every provider when a turn fails over.")
        row("", check("Automatically switch models on failure", s.automaticallySwitchModels) { [weak self] on in self?.settings.automaticallySwitchModels = on })
        note("Off: a failed turn never silently substitutes another model — it waits on the selected model instead.")
        row("", check("Use provider models only", s.useProviderModelsOnly) { [weak self] on in self?.settings.useProviderModelsOnly = on })
        row("", check("Only use free models", s.onlyUseFreeModels) { [weak self] on in self?.settings.onlyUseFreeModels = on })
        row("", check("Use SwiftCode’s Cloud Model", s.useSwiftCodeCloudModel) { [weak self] on in self?.settings.useSwiftCodeCloudModel = on })
        note("The cloud model is eligible under every routing strategy and needs no API key or sign-in.")

        heading("Local Models")
        row("Ollama address:", field(s.ollamaURL, width: 260) { [weak self] v in self?.settings.ollamaURL = v.isEmpty ? OllamaProvider.defaultBaseURL : v })
        note("Ollama's API (default \(OllamaProvider.defaultBaseURL)). To add a model, run `ollama pull \(OllamaProvider.suggestedModel)` in Terminal.")
        row("llama.cpp address:", field(s.llamaCppURL, width: 260) { [weak self] v in
            self?.settings.llamaCppURL = v.isEmpty ? ChatCompletionsProvider.defaultBaseURL : v
        })
        row("llama.cpp API key:", secretRow(SecretAccount.llamaCppKey, placeholder: "Only if llama-server uses --api-key"))

        heading("OpenAI")
        row("Sign-in method:", popUp(AssistantSettings.OpenAIAuth.allCases.map { Self.openAIAuthTitles[$0]! },
                                     selected: Self.openAIAuthTitles[s.openAIAuth]!) { [weak self] title in
            guard let self, let a = Self.openAIAuthTitles.first(where: { $0.value == title })?.key else { return }
            settings.openAIAuth = a
            rebuild()
        })
        if s.openAIAuth == .chatGPT {
            row("Account:", accountRow())
            note("Uses OpenAI's sign-in for open-source apps: your browser opens OpenAI's page, and eligible requests use your ChatGPT plan (Plus or Pro). SwiftCode registers itself with OpenAI on the first sign-in; there is no client ID to enter. Tokens are kept in the keychain. Manage usage in ChatGPT settings.")
        } else {
            row("API key:", secretRow(SecretAccount.openAIKey, placeholder: "sk-…"))
            note("Requests are billed to the API key's organization. The key is kept in the keychain.")
        }
        row("OpenAI address:", field(s.openAIURL, width: 260) { [weak self] v in self?.settings.openAIURL = v.isEmpty ? OpenAIProvider.defaultBaseURL : v })

        heading("OpenRouter")
        row("API key:", secretRow(SecretAccount.openRouterKey, placeholder: "sk-or-…"))
        note("Requests are billed to the API key's organization. The key is kept in the keychain. Models are discovered live from OpenRouter — SwiftCode names none itself.")
        row("OpenRouter address:", field(s.openRouterURL, width: 260) { [weak self] v in self?.settings.openRouterURL = v.isEmpty ? OpenRouterProvider.defaultBaseURL : v })

        heading("OpenCode")
        row("OpenCode address:", field(s.openCodeURL, width: 260) { [weak self] v in self?.settings.openCodeURL = v.isEmpty ? OpenCodeProvider.defaultBaseURL : v })
        note("The local OpenCode server (default \(OpenCodeProvider.defaultBaseURL)). Start it with `opencode serve` in Terminal.")
        row("Agent name:", field(s.openCodeAgentName, width: 160) { [weak self] v in self?.settings.openCodeAgentName = v.isEmpty ? OpenCodeProvider.defaultAgentName : v })
        note("The OpenCode agent every session names. It must be configured server-side with every permission denied, so the server returns JSON tool requests for SwiftCode to run instead of executing tools itself.")

        heading("Hermes")
        let hermesFound = services.locator.find("hermes")
        let hermesStatus = NSTextField(labelWithString: hermesFound.map { "Found: \($0.path)" } ?? "Not found (`hermes`)")
        hermesStatus.textColor = hermesFound == nil ? .secondaryLabelColor : .labelColor
        hermesStatus.font = .systemFont(ofSize: 11)
        hermesStatus.lineBreakMode = .byTruncatingMiddle
        row("Hermes:", hermesStatus)
        note("The Hermes CLI agent, run one-shot per task. Install Hermes and sign in once by running `hermes setup` and `hermes model` in Terminal. Hermes runs its own tools; SwiftCode only observes.")

        heading("Assist with Meta")
        let museFound = services.locator.find("muse")
        let museStatus = NSTextField(labelWithString: museFound.map { "Found: \($0.path)" } ?? "Not found (`muse`)")
        museStatus.textColor = museFound == nil ? .secondaryLabelColor : .labelColor
        museStatus.font = .systemFont(ofSize: 11)
        museStatus.lineBreakMode = .byTruncatingMiddle
        row("Muse CLI:", museStatus)
        note("“Assist with Meta”, powered by the Muse Code CLI. Install the `muse` CLI and sign in once in Terminal. SwiftCode lists Meta’s models when the CLI is installed, and runs turns through the Muse Code bridge.")
        row("", check("Use Meta's Slash Commands", s.useMetaSlashCommands) { [weak self] on in self?.settings.useMetaSlashCommands = on })
        note("Type \"/\" on Assist to list and run all commands from Muse Code. Off: \"/…\" text is sent to the model as-is.")
        row("Meta turn timeout (seconds):", field(s.metaTurnTimeoutSeconds.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s.metaTurnTimeoutSeconds))" : "\(s.metaTurnTimeoutSeconds)", width: 80, placeholder: "300") { [weak self] v in
            guard let self else { return }
            if v.isEmpty {
                settings.metaTurnTimeoutSeconds = MetaAssistTurnExecutor.defaultTurnTimeout
            } else if let d = Double(v) {
                settings.metaTurnTimeoutSeconds = max(0, d)
            }
        })
        note("How long a Meta turn may run before it is cancelled (\(Int(MetaAssistTurnExecutor.defaultTurnTimeout)) seconds by default; 0 disables the timeout). A timed-out turn fails over to another model only when “Automatically switch models on failure” is on.")

        heading("Meta Other Models")
        row("", check("Use other models with Meta", s.metaUseOtherModels) { [weak self] on in self?.settings.metaUseOtherModels = on })
        note("Routes Meta turns through the model below instead of Meta's own, via the Meta proxy.")
        row("", check("Use SwiftCode's Cloud Model with Meta", s.metaUseCloudModelWithMeta) { [weak self] on in self?.settings.metaUseCloudModelWithMeta = on })
        row("Other model ID:", field(s.metaSelectedOtherModelID, width: 260, placeholder: "e.g. openai/gpt-4o") { [weak self] v in self?.settings.metaSelectedOtherModelID = v })
        row("Other model provider:", field(s.metaSelectedOtherModelProvider, width: 260, placeholder: "e.g. openai") { [weak self] v in self?.settings.metaSelectedOtherModelProvider = v })

        heading("Foundation Models")
        note("Apple's on-device model (macOS 26+, Apple Intelligence-capable Mac). No API key, no account, nothing to configure.")

        heading("SwiftCode Cloud")
        row("SwiftCode Cloud address:", field(s.scCloudURL, width: 260, placeholder: "No endpoint configured") { [weak self] v in self?.settings.scCloudURL = v })
        note("SwiftCode's own cloud model. No endpoint is shipped — enter a real one. The device identity used for fair-use metering is generated automatically and kept in the keychain.")

        heading("GitHub")
        row("Personal access token:", secretRow(SecretAccount.githubToken, placeholder: "ghp_…"))
        note("A personal access token for the GitHub tools (issues, pull requests, file reads). The token is kept in the keychain and is never shown again. Without a token, public repositories still work at GitHub's lower rate limit.")
        row("Account:", githubValidationRow())

        heading("Agent Tools")
        note("SwiftCode runs these tools in the workspace folder with their own editing turned off; in agent mode (below) they change files through SwiftCode's tools, each change reviewed by you. SwiftCode never reads their sign-in or settings. Sign in to each tool once in Terminal.")
        for agent in CLIAgentKind.allCases {
            let kind = agent.providerKind
            let found = services.locator.find(agent.executableName, override: s.toolPaths[kind.rawValue])
            let status = NSTextField(labelWithString: found.map { "Found: \($0.path)" } ?? "Not found (`\(agent.executableName)`)")
            status.textColor = found == nil ? .secondaryLabelColor : .labelColor
            status.font = .systemFont(ofSize: 11)
            status.lineBreakMode = .byTruncatingMiddle
            row("\(agent.displayName):", status)
            row("\(agent.displayName) path:", field(s.toolPaths[kind.rawValue] ?? "", width: 260, placeholder: "Search PATH and the usual folders") { [weak self] v in
                guard let self else { return }
                var t = settings
                t.toolPaths[kind.rawValue] = v.isEmpty ? nil : v
                settings = t
                rebuild()
            })
            row("\(agent.displayName) model:", field(s.model(for: kind) ?? "", width: 160, placeholder: "The tool's default") { [weak self] v in
                guard let self else { return }
                var t = settings
                t.setModel(v.isEmpty ? nil : v, for: kind)
                settings = t
            })
        }

        heading("ACP Agent")
        note("An agent that speaks the Agent Client Protocol, started with this command line in the workspace folder. Its messages, tool calls, plans and permission requests show in the Coding Assistant pane; its file reads and writes go through SwiftCode, and each write is a proposal you review.")
        row("Command:", field(s.acpCommand, width: 260, placeholder: "<agent> <arguments for its ACP mode>") { [weak self] v in
            self?.settings.acpCommand = v
            self?.rebuild()
        })
        let acp = ACPAgentProvider(command: s.acpCommand, locator: services.locator)
        let acpStatus = NSTextField(labelWithString: s.acpCommand.isEmpty ? "Not set" : (acp.executable.map { "Found: \($0.path)" } ?? "Not found"))
        acpStatus.font = .systemFont(ofSize: 11)
        acpStatus.textColor = acp.executable == nil ? .secondaryLabelColor : .labelColor
        row("", acpStatus)

        heading("Agent Mode")
        row("", check("Let agents use SwiftCode's tools and change files", s.agentMode) { [weak self] on in self?.settings.agentMode = on })
        note(Self.agentModeText)
        row("SwiftCode MCP server:", copyField(Self.mcpCommandLine()))
        row("Claude Code:", copyField("claude mcp add swiftcode -- \(Self.mcpCommandLine())"))
        row("Codex:", copyField("codex mcp add swiftcode -- \(Self.mcpCommandLine())"))
        note("Paste one of these into a terminal to give an agent you run yourself SwiftCode's tools (build, test, run, simulator screenshots, previews, String Catalogs). Add --allow-writes to let it change files; without it the server is read-only.")
        let install = ClosureButton(title: "Install in Workspace…", target: nil, action: nil)
        install.bezelStyle = .rounded
        install.onChange = { _ in
            let w = NSApp.orderedWindows.lazy.compactMap { $0.windowController as? WorkspaceWindowController }.first
            if let w { w.installSwiftCodeSkill(nil) } else { NSSound.beep() }
        }
        row("SwiftCode skill:", install)
        note("Writes a short skill file describing SwiftCode's tools and the build-and-run workflow into the front workspace (.claude/skills/swiftcode/SKILL.md and .agents/skills/swiftcode/SKILL.md), for agents that read skills.")

        heading("Context")
        row("Context limit (tokens):", number(s.contextLimit) { [weak self] n in self?.settings.contextLimit = max(1024, n) })
        row("", check("Send the current file", s.context.includeCurrentFile) { [weak self] on in self?.settings.context.includeCurrentFile = on })
        row("", check("Send the other open files", s.context.includeOpenFiles) { [weak self] on in self?.settings.context.includeOpenFiles = on })
        row("", check("Send the workspace's issues", s.context.includeIssues) { [weak self] on in self?.settings.context.includeIssues = on })

        heading("Output")
        row("Most output tokens:", optionalField(s.generation.maxOutputTokens.map(String.init), placeholder: "no limit") { [weak self] v in
            self?.settings.generation.maxOutputTokens = Int(v).flatMap { $0 > 0 ? $0 : nil }
        })
        row("Temperature:", optionalField(s.generation.temperature.map { String($0) }, placeholder: "server default") { [weak self] v in
            self?.settings.generation.temperature = Double(v)
        })
        row("Top P:", optionalField(s.generation.topP.map { String($0) }, placeholder: "server default") { [weak self] v in
            self?.settings.generation.topP = Double(v)
        })
        row("Top K:", optionalField(s.generation.topK.map(String.init), placeholder: "server default") { [weak self] v in
            self?.settings.generation.topK = Int(v)
        })
        row("Repeat penalty:", optionalField(s.generation.repeatPenalty.map { String($0) }, placeholder: "server default") { [weak self] v in
            self?.settings.generation.repeatPenalty = Double(v)
        })
        note("Empty fields are not sent: the server's own value applies. Top K and the repeat penalty are for Ollama and llama.cpp only.")

        heading("Privacy")
        note(Self.privacyText)
    }

    func optionalField(_ value: String?, placeholder: String, _ commit: @escaping (String) -> Void) -> NSTextField {
        let f = ClosureField(string: value ?? "")
        f.placeholderString = placeholder
        f.widthAnchor.constraint(equalToConstant: 110).isActive = true
        f.onCommit = { commit($0.stringValue.trimmingCharacters(in: .whitespaces)) }
        return f
    }

    static let agentModeText = """
    On: Claude Code and Codex get SwiftCode's MCP server (the workspace's build, test, run and project tools) and may change \
    files only through it; ACP agents get it too when they take MCP servers over HTTP. Each change shows in the \
    conversation as a proposal; the agent waits until you accept it (the file is saved) or reject it. The server listens \
    on 127.0.0.1 only, with a new token for each request. Off: agents only read and propose, as before.
    """

    public static func mcpCommandLine() -> String {
        let fm = FileManager.default
        var candidates: [String] = []
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates += [dir.appendingPathComponent("swiftcode").path, dir.deletingLastPathComponent().appendingPathComponent("Helpers/swiftcode").path]
        }
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/swiftcode" }
        let exe = candidates.first { fm.isExecutableFile(atPath: $0) } ?? "swiftcode"
        return (exe.contains(" ") ? "'\(exe)'" : exe) + " mcp"
    }

    func copyField(_ text: String) -> NSView {
        let f = NSTextField(string: text)
        f.isEditable = false
        f.isSelectable = true
        f.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        f.lineBreakMode = .byTruncatingMiddle
        f.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let copy = ClosureButton(title: "Copy", target: nil, action: nil)
        copy.bezelStyle = .rounded
        copy.onChange = { _ in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        let stack = NSStackView(views: [f, copy])
        stack.spacing = 6
        return stack
    }

    static let privacyText = """
    What is sent: your message, the attached file or selection, and, as allowed above, the current file (or the part of it \
    that fits), the other open files and the issue list, plus the earlier messages of the conversation. With Ollama or \
    llama.cpp this stays on the address you set (this Mac by default). With OpenAI it goes to OpenAI. With an agent tool \
    it goes to that tool, which may also read files in the workspace folder and sends what it reads to its own service. \
    Conversations are saved in SwiftCode's folder in Application Support, not in the workspace. Changes are only applied when \
    you accept them.
    """

    func field(_ value: String, width: CGFloat, placeholder: String = "", _ action: @escaping (String) -> Void) -> NSTextField {
        let f = ClosureField(string: value)
        f.placeholderString = placeholder
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        f.onCommit = { action($0.stringValue.trimmingCharacters(in: .whitespaces)) }
        return f
    }

    func secretRow(_ account: String, placeholder: String) -> NSView {
        let saved = try? services.store.read(account)
        let f = NSSecureTextField()
        f.placeholderString = saved == nil ? placeholder : "Saved in the keychain"
        f.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let save = ClosureButton(title: "Save", target: nil, action: nil)
        save.bezelStyle = .rounded
        save.onChange = { [weak self, weak f] _ in
            guard let self, let key = f?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
            do {
                try services.store.write(Data(key.utf8), for: account)
                accountMessage = "Key saved."
            } catch {
                accountMessage = error.localizedDescription
            }
            settingsChangedExternally()
            rebuild()
        }
        let remove = ClosureButton(title: "Remove", target: nil, action: nil)
        remove.bezelStyle = .rounded
        remove.isEnabled = saved != nil
        remove.onChange = { [weak self] _ in
            guard let self else { return }
            try? services.store.delete(account)
            accountMessage = "Key removed."
            settingsChangedExternally()
            rebuild()
        }
        let stack = NSStackView(views: [f, save, remove])
        stack.spacing = 6
        return stack
    }

    func settingsChangedExternally() {
        NotificationCenter.default.post(name: Self.credentialsDidChange, object: nil)
    }

    public static let credentialsDidChange = Notification.Name("SwiftCodeCodingAssistantCredentialsDidChange")

    func accountRow() -> NSView {
        let status = NSTextField(labelWithString: "Checking…")
        status.font = .systemFont(ofSize: 11)
        let button = ClosureButton(title: "Continue with ChatGPT", target: nil, action: nil)
        button.bezelStyle = .rounded
        let message = NSTextField(labelWithString: accountMessage)
        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        let account = services.account
        Task { [weak status, weak button] in
            let st = await account.status
            guard let status, let button else { return }
            switch st {
            case .signedOut:
                status.stringValue = "Not signed in"
                button.title = "Continue with ChatGPT"
            case .signedIn(let email, let plan):
                status.stringValue = "Signed in" + (email.map { " as \($0)" } ?? "") + (plan ? "" : " (plan usage not allowed)")
                button.title = "Sign Out"
            }
        }
        button.onChange = { [weak self] b in
            guard let self else { return }
            if b.title == "Sign Out" { signOut() } else { signIn() }
        }
        let stack = NSStackView(views: [status, button, message])
        stack.spacing = 8
        return stack
    }

    public func signIn() {
        accountMessage = "Continue in your browser…"
        rebuild()
        let account = services.account
        signInTask = Task { [weak self] in
            do {
                let t = try await account.signIn()
                guard let self else { return }
                accountMessage = t.hasPlanUsage ? "Signed in." : "Signed in, but plan usage was not allowed. Sign in again and allow it, or use an API key."
                if t.hasPlanUsage && !settings.shownPlanNotice {
                    settings.shownPlanNotice = true
                    showPlanNotice()
                }
            } catch {
                self?.accountMessage = CodingAssistantModel.describe(error)
            }
            self?.settingsChangedExternally()
            self?.rebuild()
        }
    }

    public func signOut() {
        let account = services.account
        signInTask = Task { [weak self] in
            let revoked = await account.signOut()
            self?.accountMessage = revoked ? "Signed out." : "Signed out on this Mac. SwiftCode could not confirm the revocation; disconnect SwiftCode in ChatGPT settings."
            self?.settingsChangedExternally()
            self?.rebuild()
        }
    }

    func githubValidationRow() -> NSView {
        let status = NSTextField(labelWithString: githubMessage)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        let button = ClosureButton(title: "Validate", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.onChange = { [weak self] _ in self?.validateGitHubToken() }
        let stack = NSStackView(views: [status, button])
        stack.spacing = 8
        return stack
    }

    public func validateGitHubToken() {
        githubMessage = "Checking…"
        rebuild()
        let token = services.store.readString(SecretAccount.githubToken)
        githubValidationTask = Task { [weak self] in
            let client = GitHubClient(tokenProvider: { token })
            do {
                let user = try await client.getAuthenticatedUser()
                self?.githubMessage = "Signed in as \(user.login)."
            } catch {
                self?.githubMessage = error.localizedDescription
            }
            self?.rebuild()
        }
    }

    func showPlanNotice() {
        guard let w = view.window, w.isVisible else { return }
        let a = NSAlert()
        a.messageText = "You're using your ChatGPT plan"
        a.informativeText = "Eligible requests from SwiftCode's coding assistant use your ChatGPT plan. You can manage usage in ChatGPT settings."
        a.addButton(withTitle: "Got it")
        a.beginSheetModal(for: w)
    }
}
