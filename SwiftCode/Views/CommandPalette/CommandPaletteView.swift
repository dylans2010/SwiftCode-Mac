import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.CommandPalette", category: "CommandPaletteView")

@MainActor
struct CommandPaletteView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: CommandCategory = .all

    // "Ask" AI feature states
    @State private var askQuestionText = ""
    @State private var aiResponseText = ""
    @State private var isAsking = false
    @State private var askError: String? = nil

    let onAction: (CommandAction) -> Void

    enum CommandCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case ask = "Ask AI"
        case files = "Files & Nav"
        case git = "Git"
        case ai = "AI Tools"
        case build = "Build / Sign"
        case devTools = "Developer Tools"
        case settings = "Settings"

        var id: String { rawValue }
    }

    enum CommandAction: String, CaseIterable, Identifiable {
        // Files & Nav
        case createFile = "Create File"
        case createFolder = "Create Folder"
        case searchProject = "Global Code Search"
        case goToLine = "Go To Line"
        case openSymbolNav = "Symbol Navigator"
        case openSystemOutline = "System Outline / Symbols"
        case openMinimap = "Minimap Settings"

        // Git
        case gitCommit = "Git Commit Changes"
        case gitPull = "Git Pull"
        case gitPush = "Git Push"
        case gitCheckout = "Git Checkout Branch"
        case gitNewBranch = "Git Create New Branch"
        case openDiffViewer = "Diff Viewer"

        // AI Tools
        case runAgent = "Run AI Agent"
        case aiCodeReview = "AI Code Review"
        case aiComplexity = "AI Complexity Analyzer"

        // Build / Sign
        case runBuild = "Run Project Build"
        case openXcodeBuildSettings = "Xcode Build Settings"
        case openXcodeBuildLogs = "Xcode Build Logs"
        case appleSigning = "Apple Developer Account & Signing"

        // Developer Tools (Newly Added)
        case devHTTPStatus = "HTTP Status Code Lookup"
        case devJSONFormatter = "JSON Formatter"
        case devBase64 = "Base64 Converter"
        case devJWTDecoder = "JWT Decoder"
        case devPasswordGen = "Password Generator"
        case devRegExTester = "RegEx Tester"
        case devUUIDGen = "UUID Generator"
        case devURLEncoder = "URL/Percent Encoder"
        case devMarkdownPreview = "Markdown Previewer"
        case devDeviceInfo = "Developer Device Info"

        // Settings / Tools
        case openSettings = "Open App Settings"
        case openProjectSettings = "Project Settings"
        case installDependency = "Manage Dependencies"
        case openPluginManager = "Plugin Manager"
        case openExtensionMarketplace = "Extension Marketplace"
        case customizeToolbar = "Customize Toolbar"

        var id: String { rawValue }

        var category: CommandCategory {
            switch self {
            case .createFile, .createFolder, .searchProject, .goToLine, .openSymbolNav, .openSystemOutline, .openMinimap:
                return .files
            case .gitCommit, .gitPull, .gitPush, .gitCheckout, .gitNewBranch, .openDiffViewer:
                return .git
            case .runAgent, .aiCodeReview, .aiComplexity:
                return .ai
            case .runBuild, .openXcodeBuildSettings, .openXcodeBuildLogs, .appleSigning:
                return .build
            case .devHTTPStatus, .devJSONFormatter, .devBase64, .devJWTDecoder, .devPasswordGen, .devRegExTester, .devUUIDGen, .devURLEncoder, .devMarkdownPreview, .devDeviceInfo:
                return .devTools
            case .openSettings, .openProjectSettings, .installDependency, .openPluginManager, .openExtensionMarketplace, .customizeToolbar:
                return .settings
            }
        }

        var icon: String {
            switch self {
            case .createFile: return "doc.badge.plus"
            case .createFolder: return "folder.badge.plus"
            case .searchProject: return "magnifyingglass"
            case .goToLine: return "arrow.right.to.line"
            case .openSymbolNav: return "list.bullet.indent"
            case .openSystemOutline: return "align.horizontal.left"
            case .openMinimap: return "map.fill"

            case .gitCommit: return "checkmark.circle"
            case .gitPull: return "arrow.down.circle"
            case .gitPush: return "arrow.up.circle"
            case .gitCheckout: return "arrow.branch"
            case .gitNewBranch: return "plus.circle"
            case .openDiffViewer: return "arrow.left.arrow.right"

            case .runAgent: return "sparkles"
            case .aiCodeReview: return "text.badge.checkmark"
            case .aiComplexity: return "chart.bar.xaxis"

            case .runBuild: return "hammer.fill"
            case .openXcodeBuildSettings: return "gearshape.2"
            case .openXcodeBuildLogs: return "doc.text.magnifyingglass"
            case .appleSigning: return "key"

            case .devHTTPStatus: return "network"
            case .devJSONFormatter: return "curlybraces"
            case .devBase64: return "arrow.left.and.right.square"
            case .devJWTDecoder: return "lock.shield"
            case .devPasswordGen: return "key"
            case .devRegExTester: return "checklist"
            case .devUUIDGen: return "barcode"
            case .devURLEncoder: return "link.badge.plus"
            case .devMarkdownPreview: return "doc.richtext"
            case .devDeviceInfo: return "desktopcomputer"

            case .openSettings: return "gearshape.fill"
            case .openProjectSettings: return "gearshape"
            case .installDependency: return "shippingbox.fill"
            case .openPluginManager: return "cpu"
            case .openExtensionMarketplace: return "puzzlepiece.extension"
            case .customizeToolbar: return "slider.horizontal.3"
            }
        }

        var shortcut: String {
            switch self {
            case .createFile: return "⌘N"
            case .searchProject: return "⌘⇧F"
            case .runBuild: return "⌘B"
            case .goToLine: return "⌘G"
            case .openSettings: return "⌘,"
            case .runAgent: return "⌘⇧A"
            default: return ""
            }
        }
    }

    var filteredCommands: [CommandAction] {
        var cmds = CommandAction.allCases

        if selectedCategory != .all && selectedCategory != .ask {
            cmds = cmds.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            cmds = cmds.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
        }

        return cmds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search & Filter Category Bar
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: selectedCategory == .ask ? "sparkles" : "terminal.fill")
                            .foregroundStyle(.orange)
                        TextField(selectedCategory == .ask ? "Ask the AI a coding question..." : "Type a command...", text: $searchText)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)

                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CommandCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider().opacity(0.3)

                if selectedCategory == .ask {
                    askAIPane
                } else {
                    commandsListPane
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Command Palette")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Ask AI Pane

    private var askAIPane: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask AI")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Inquire about Swift, Apple SDKs, algorithms, or refactoring strategies using the default AI model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top)

            VStack(spacing: 12) {
                TextEditor(text: $askQuestionText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .placeholder(when: askQuestionText.isEmpty) {
                        Text("Type your question here (e.g. 'How do I center a div in SwiftUI?')")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.all, 8)
                    }

                HStack {
                    if isAsking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        performAskRequest()
                    } label: {
                        Text("Submit Question")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAsking)
                }
            }
            .padding(.horizontal)

            Divider().opacity(0.2)

            if let error = askError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if aiResponseText.isEmpty {
                        Text("No response yet. Ask a question to see the result streamed here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        Text(aiResponseText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .padding([.horizontal, .bottom])
        }
    }

    private func mapCommandToToolID(_ cmd: CommandAction) -> String? {
        switch cmd {
        case .searchProject: return "code_search"
        case .goToLine: return "go_to_line"
        case .openSymbolNav: return "symbol_navigator"
        case .openSystemOutline: return "symbol_outline"
        case .openMinimap: return "minimap_settings"
        case .openXcodeBuildSettings: return "xcode_build_settings"
        case .openXcodeBuildLogs: return "xcode_build_logs"
        case .appleSigning: return "apple_developer_account"
        case .openSettings: return "settings"
        case .openProjectSettings: return "project_settings"
        case .installDependency: return "dependency_manager"
        case .openPluginManager: return "plugin_manager"
        case .openExtensionMarketplace: return "extension_marketplace"
        case .customizeToolbar: return "toolbar_customization"
        case .runAgent: return "ai_code_gen"
        case .aiCodeReview: return "code_review"
        case .aiComplexity: return "complexity_analyzer"
        case .runBuild: return "build_status"
        case .gitCommit: return "source_control"
        case .gitPull: return "source_control"
        case .gitPush: return "source_control"
        case .gitCheckout: return "source_control"
        case .gitNewBranch: return "source_control"
        case .openDiffViewer: return "diff_viewer"
        default: return nil
        }
    }

    private var commandsListPane: some View {
        List(filteredCommands) { command in
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onAction(command)
                }
            } label: {
                HStack {
                    Image(systemName: command.icon)
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text(command.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    if !command.shortcut.isEmpty {
                        Text(command.shortcut)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if let toolID = mapCommandToToolID(command) {
                    ToolbarSettings.shared.togglePin(id: toolID)
                    logger.info("Toggled pin for tool: \(toolID)")
                }
            })
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - AI Action

    private func performAskRequest() {
        guard !askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isAsking = true
        askError = nil
        aiResponseText = ""

        let query = askQuestionText
        let model = AppSettings.shared.selectedModel

        Task {
            do {
                let userMsg = AIMessage(role: .user, content: query)
                let request = AIAssistantRequest(model: model, messages: [userMsg])
                let stream = try await OpenRouterClient.shared.streamChatCompletion(request: request)

                for try await chunk in stream {
                    aiResponseText += chunk
                }
            } catch {
                logger.error("Command palette Ask failure: \(error.localizedDescription)")
                askError = "Error: \(error.localizedDescription)"
            }
            isAsking = false
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .topLeading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
