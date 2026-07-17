import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistMainView")

/// Highly-optimized, professional desktop-first macOS experience for the SwiftCode Assist workspace.
public struct AssistMainView: View {
    @StateObject private var manager = AssistManager.shared
    @State private var inputText: String = ""
    @State private var isEnhancingPrompt = false
    @State private var showDiagnosticsSheet = false
    @State private var showExecutionModeSheet = false
    @State private var showApprovalSheet = false
    @State private var searchConversationText = ""
    @State private var attachedFiles: [AgentFileContext] = []
    @State private var showingFilePickerSheet = false
    @State private var isProcessingFiles = false
    @State private var fetchedOpenRouterModels: [OpenRouterModel] = []

    // Codex Integration
    @Bindable private var bridgeManager = CodexBridgeManager.shared

    // Onboarding / Connection triggers
    @State private var showConnectCodex = false
    @State private var showingCodexSetup = false

    // Destructive Actions Approval Workflow
    @State private var pendingActionName: String = "Terminal Execution"
    @State private var pendingActionDetails: String = "rm -rf build/"
    @State private var alwaysAllowThisSession: Bool = false

    // Mode selection: Chat Mode (Read-Only) vs. Agent Mode (Autonomous)
    @AppStorage("com.swiftcode.assist.mode") private var isAgentMode = false

    // Glowing border pulse state for Apple Intelligence
    @State private var pulseGlow = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Button {
                    manager.clearChat()
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Clear Chat History (⌘K)")

                Spacer()

                // Execution Mode Button
                Button {
                    showExecutionModeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isAgentMode ? "cpu.fill" : "text.bubble.fill")
                            .foregroundStyle(isAgentMode ? .orange : .blue)
                        Text(isAgentMode ? "Agent Mode" : "Chat Mode")
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle Execution Mode")

                Spacer()

                // Diagnostics Trigger
                Button {
                    showDiagnosticsSheet = true
                } label: {
                    Image(systemName: "terminal.fill")
                        .font(.body)
                        .foregroundStyle((manager.isProcessing || bridgeManager.streamStatus == "Streaming") ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help("System Diagnostics")

                // Codex Setup Trigger
                Button {
                    showingCodexSetup = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Configure Codex CLI")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial)

            Divider()

            // Chat Messages scroll block
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search chats...", text: $searchConversationText)
                                .textFieldStyle(.plain)
                            if !searchConversationText.isEmpty {
                                Button {
                                    searchConversationText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        // Codex Onboarding Prompt
                        if showConnectCodex {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("Connect OpenAI Codex CLI", systemImage: "sparkles")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.orange)
                                        Spacer()
                                    }
                                    Text("Leverage the official OpenAI Codex CLI as SwiftCode's complete reasoning & backend agent engine.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        showingCodexSetup = true
                                    } label: {
                                        Text("Integrate Codex CLI")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                }
                                .padding(4)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                            .padding(.horizontal, 12)
                        }

                        // Chat bubbles
                        ForEach(filteredMessages) { message in
                            AssistChatBubble(message: message)
                        }

                        // Tool Timeline widget
                        if bridgeManager.activeToolName != "None" {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .tint(.orange)
                                        Text("Codex Tool Execution in Progress")
                                            .font(.caption.bold())
                                            .foregroundStyle(.orange)
                                        Spacer()
                                        Text(bridgeManager.activeToolName)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.12), in: Capsule())
                                    }
                                    Text(bridgeManager.activeToolDetails)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(4)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                            .padding(.horizontal, 12)
                        }

                        if isAgentMode {
                            TaskProgressView(agentSession: manager.agentSession)
                            ToolExecutionView(agentSession: manager.agentSession)
                            AgentTimelineView(agentSession: manager.agentSession)
                            AgentControlsView(agentSession: manager.agentSession)
                        }

                        if let error = manager.lastError {
                            AssistErrorBubble(error: error)
                        }

                        if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
                            thinkingIndicator
                        }
                    }
                    .padding(.bottom, 12)
                    .blur(radius: manager.takeoverReason != nil ? 8 : 0)
                    .overlay {
                        if let reason = manager.takeoverReason {
                            AssistUserTakeover(
                                reason: reason,
                                onResume: {
                                    manager.takeoverReason = nil
                                },
                                onAbort: {
                                    manager.takeoverReason = nil
                                    manager.clearChat()
                                }
                            )
                        }
                    }
                    .id("Bottom")
                }
                .onChange(of: manager.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("Bottom", anchor: .bottom) }
                }
            }

            Divider()

            // Terminal Execution Approval Overlay
            if let request = manager.pendingTerminalRequest {
                VStack(alignment: .leading, spacing: 14) {
                    let isDestructive = request.modifiesRepo || request.command.contains("rm ") || request.command.contains("git reset") || request.command.contains("git clean") || request.command.contains("delete") || request.command.contains("remove")

                    HStack(spacing: 8) {
                        Image(systemName: isDestructive ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                            .foregroundColor(isDestructive ? .red : .green)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDestructive ? "Destructive Terminal Request" : "Terminal Execution Request")
                                .font(.headline)
                            Text("Awaiting Developer Authorization")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(isDestructive ? "High Risk" : "Safe")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isDestructive ? Color.red.opacity(0.15) : Color.green.opacity(0.15), in: Capsule())
                            .foregroundColor(isDestructive ? .red : .green)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Command:")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Text(request.command)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            HStack {
                                Text("Working Directory:")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Text(request.workingDirectory)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            HStack {
                                Text("Explanation:")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Text(request.explanation)
                                    .font(.subheadline)
                            }

                            HStack {
                                Text("Impact Detail:")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Text(request.estimatedImpact)
                                    .font(.subheadline)
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if manager.terminalRunning || manager.terminalCompleted {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                if manager.terminalRunning {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .padding(.trailing, 4)
                                    Text("Executing Command...")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                } else {
                                    Image(systemName: manager.terminalExitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(manager.terminalExitCode == 0 ? .green : .red)
                                    Text(manager.terminalExitCode == 0 ? "Execution Succeeded (Exit code 0)" : "Execution Failed (Exit code \(manager.terminalExitCode ?? -1))")
                                        .font(.caption.bold())
                                        .foregroundColor(manager.terminalExitCode == 0 ? .green : .red)
                                }
                                Spacer()
                            }

                            ScrollView {
                                Text(manager.terminalLiveOutput.isEmpty ? "Initializing process stream..." : manager.terminalLiveOutput)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundColor(.white)
                                    .background(Color.black)
                            }
                            .frame(height: 120)
                            .cornerRadius(6)
                        }
                    }

                    HStack(spacing: 12) {
                        if !manager.terminalRunning && !manager.terminalCompleted {
                            Button {
                                manager.approveTerminalRequest()
                            } label: {
                                Label("Approve & Execute", systemImage: "play.fill")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(isDestructive ? .red : .green)

                            Button {
                                manager.denyTerminalRequest()
                            } label: {
                                Text("Deny Request")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        } else if manager.terminalRunning {
                            Button {
                                manager.cancelTerminalExecution()
                            } label: {
                                Label("Cancel Execution", systemImage: "stop.fill")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else if manager.terminalCompleted {
                            Button {
                                manager.pendingTerminalRequest = nil
                            } label: {
                                Text("Dismiss")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDestructive ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom))
            }

            // Bottom input controls
            VStack(spacing: 8) {
                if !attachedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachedFiles) { file in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Text(file.filename)
                                        .font(.caption)
                                    Button {
                                        attachedFiles.removeAll { $0.id == file.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 28)
                }

                if !manager.logger.logs.isEmpty {
                    MiniLogFeed(logger: manager.logger)
                }
                inputArea
            }
            .padding(12)
            .background(.thinMaterial)
        }
        .background(.windowBackground)
        .sheet(isPresented: $showingCodexSetup) {
            CodexSignInFlow()
        }
        .sheet(isPresented: $showExecutionModeSheet) {
            ExecutionModeSheet()
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            DiagnosticsSheet(manager: manager)
        }
        .task {
            await updateCodexButtonVisibility()
            await fetchOpenRouterModelsBackground()
        }
        .onChange(of: showingCodexSetup) { _, newValue in
            if !newValue {
                Task {
                    await updateCodexButtonVisibility()
                }
            }
        }
        .onChange(of: isEnhancingPrompt) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseGlow = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pulseGlow = false
                }
            }
        }
        .onChange(of: bridgeManager.activeToolName) { _, newTool in
            // Intercept potentially destructive actions
            if isAgentMode && !alwaysAllowThisSession {
                let destructive = ["command_execution", "file_change", "terminal", "delete", "remove"]
                if destructive.contains(newTool.lowercased()) {
                    pendingActionName = newTool
                    pendingActionDetails = bridgeManager.activeToolDetails
                    showApprovalSheet = true
                }
            }
        }
    }

    private func updateCodexButtonVisibility() async {
        let hasKey = !(KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cliDetected = bridgeManager.discoverCLIPath() != nil
        let completedSetup = UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup")

        showConnectCodex = !hasKey && (!cliDetected || !completedSetup)
    }

    private func fetchOpenRouterModelsBackground() async {
        do {
            let liveModels = try await OpenRouterService.shared.fetchModels()
            await MainActor.run {
                self.fetchedOpenRouterModels = liveModels
            }
        } catch {
            logger.warning("[fetchOpenRouterModelsBackground] Synchronous preset models fallback active.")
        }
    }

    private var filteredMessages: [AssistMessage] {
        let text = searchConversationText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return manager.messages }
        return manager.messages.filter { $0.content.lowercased().contains(text) }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(bridgeManager.activeToolName != "None" ? "Agent executing tools (\(bridgeManager.activeToolName))...." : "Planning next steps...")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)

                Text(bridgeManager.activeToolDetails.isEmpty ? "Awaiting stream..." : bridgeManager.activeToolDetails)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }

    private var inputArea: some View {
        HStack(spacing: 8) {
            Button {
                showingFilePickerSheet = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(7)
                    .background(Color.orange.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingFilePickerSheet) {
                AddFilesAgentContext(attachedFiles: $attachedFiles, isProcessingFiles: $isProcessingFiles)
            }
            .help("Attach Files to Context")

            // Dynamic model selector via native AppKit popup menu
            Button {
                let event = NSApplication.shared.currentEvent
                let models = loadDynamicModels()
                let activeID = currentActiveModelID()
                ModelPopupMenuHelper.showMenu(event: event, models: models, activeModelID: activeID) { option in
                    selectModel(option)
                }
            } label: {
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(7)
                    .background(Color.orange.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Choose Model for Assist Agent")

            Button {
                expandPrompt()
            } label: {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
            }
            .disabled(inputText.isEmpty || manager.isProcessing || bridgeManager.streamStatus == "Streaming" || isProcessingFiles)
            .help("Enhance prompt with Apple Intelligence")

            ZStack {
                TextField("What should I build next?", text: $inputText, axis: .vertical)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.regularMaterial)
                    )
                    .lineLimit(1...5)
                    .disabled(manager.isProcessing || isEnhancingPrompt || bridgeManager.streamStatus == "Streaming" || isProcessingFiles)
                    .onSubmit {
                        submitMessage()
                    }
            }
            .scaleEffect(isEnhancingPrompt ? 1.015 : 1.0)
            .overlay {
                if isEnhancingPrompt {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple, .pink, .orange],
                                startPoint: pulseGlow ? .topLeading : .bottomTrailing,
                                endPoint: pulseGlow ? .bottomTrailing : .topLeading
                            ),
                            lineWidth: 2
                        )
                        .shadow(
                            color: .purple.opacity(pulseGlow ? 0.6 : 0.2),
                            radius: pulseGlow ? 8 : 3
                        )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isEnhancingPrompt)

            Button(action: submitMessage) {
                Group {
                    if manager.isProcessing || bridgeManager.streamStatus == "Streaming" || isProcessingFiles {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                    }
                }
            }
            .disabled(inputText.isEmpty || manager.isProcessing || bridgeManager.streamStatus == "Streaming" || isProcessingFiles)
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.plain)
        }
    }

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !manager.isProcessing && bridgeManager.streamStatus != "Streaming" && !isProcessingFiles else { return }
        inputText = ""

        let filesToSend = attachedFiles
        attachedFiles = []

        Task {
            await manager.sendMessage(text, attachments: filesToSend)
        }
    }

    private func expandPrompt() {
        let currentPrompt = inputText
        guard !currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation {
            isEnhancingPrompt = true
        }
        Task {
            let enhancedPrompt = await PromptEnhancer.enhancePrompt(userInput: currentPrompt)
            await MainActor.run {
                inputText = enhancedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation {
                    isEnhancingPrompt = false
                }
            }
        }
    }

    private func loadDynamicModels() -> [DynamicModelOption] {
        var modelsList: [DynamicModelOption] = []

        // 1. Apple Foundation Models
        modelsList.append(DynamicModelOption(
            modelID: AppleFoundationModel.afm3Core.rawValue,
            name: "Apple AFM 3 Core",
            provider: "Apple Private on-device reasoning",
            status: "On-Device",
            isAvailable: true,
            category: .apple
        ))
        modelsList.append(DynamicModelOption(
            modelID: AppleFoundationModel.afm3CoreAdvanced.rawValue,
            name: "Apple AFM 3 Core Advanced",
            provider: "Apple Private on-device reasoning (voice)",
            status: "On-Device",
            isAvailable: true,
            category: .apple
        ))

        // 2. HuggingFace Local Models
        let localModels = OfflineModelManager.shared.installedModels
        for m in localModels {
            modelsList.append(DynamicModelOption(
                modelID: m.modelName,
                name: m.modelName,
                provider: "HuggingFace Local",
                status: "Downloaded",
                isAvailable: true,
                category: .local
            ))
        }

        // 3. Custom endpoint/link models
        if !AppSettings.shared.customModel.isEmpty {
            modelsList.append(DynamicModelOption(
                modelID: AppSettings.shared.customModel,
                name: "Custom (Endpoint)",
                provider: "Custom API Provider",
                status: "Cloud",
                isAvailable: true,
                category: .custom
            ))
        }

        // 4. OpenRouter Cloud Models (Fallback Presets or fetched)
        if !fetchedOpenRouterModels.isEmpty {
            for m in fetchedOpenRouterModels {
                modelsList.append(DynamicModelOption(
                    modelID: m.id,
                    name: m.name,
                    provider: "OpenRouter Cloud",
                    status: "Cloud",
                    isAvailable: true,
                    category: .openRouter
                ))
            }
        } else {
            let openRouterPresets = [
                ("openai/gpt-4o", "GPT-4o"),
                ("anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet"),
                ("google/gemini-2.5-pro", "Gemini 2.5 Pro"),
                ("meta-llama/llama-3-70b-instruct", "Llama 3 70B"),
                ("openai/gpt-4o-mini", "GPT-4o Mini")
            ]
            for preset in openRouterPresets {
                modelsList.append(DynamicModelOption(
                    modelID: preset.0,
                    name: preset.1,
                    provider: "OpenRouter Cloud",
                    status: "Cloud",
                    isAvailable: true,
                    category: .openRouter
                ))
            }
        }

        return modelsList
    }

    private func currentActiveModelID() -> String {
        if FoundationModels.shared.isEnabled {
            return FoundationModels.shared.selectedModel.rawValue
        }
        return AssistModelManager.shared.customModelID.isEmpty ? AppSettings.shared.selectedModel : AssistModelManager.shared.customModelID
    }

    private func selectModel(_ option: DynamicModelOption) {
        logger.log("[selectModel] Selecting model: \(option.modelID)")

        if option.category == .apple {
            FoundationModels.shared.isEnabled = true
            if let appleModel = AppleFoundationModel(rawValue: option.modelID) {
                FoundationModels.shared.selectedModel = appleModel
            }
        } else {
            FoundationModels.shared.isEnabled = false
            AppSettings.shared.selectedModel = option.modelID
            AssistModelManager.shared.customModelID = option.modelID
        }
    }
}

// MARK: - Subviews

private struct AssistChatBubble: View {
    let message: AssistMessage

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return Color.primary.opacity(0.08)
        case .assistant: return Color.secondary.opacity(0.08)
        case .system: return Color.blue.opacity(0.12)
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.crop.circle.fill" : (message.role == .system ? "info.circle.fill" : "sparkles"))
                    .font(.caption2)
                    .foregroundStyle(message.role == .user ? .blue : (message.role == .system ? .yellow : .orange))
                Text(message.role == .user ? "You" : (message.role == .system ? "System" : "Assist"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                MarkdownBlockListView(blocks: MarkdownParser.shared.parse(message.content))
                    .textSelection(.enabled)

                if let attachments = message.attachments, !attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ATTACHMENTS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)

                        ForEach(attachments) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.filename)
                                        .font(.caption.bold())
                                        .foregroundColor(.primary)
                                    Text("\(file.mimeType.uppercased()) • \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) • Attached")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - AppKit Popup Menu Helpers

@MainActor
final class ModelPopupMenuHelper {
    static func showMenu(event: NSEvent?, models: [DynamicModelOption], activeModelID: String, onSelect: @escaping (DynamicModelOption) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        var currentCategory: DynamicModelOption.ModelCategory? = nil

        for option in models {
            if option.category != currentCategory {
                if currentCategory != nil {
                    menu.addItem(NSMenuItem.separator())
                }
                currentCategory = option.category
                let headerItem = NSMenuItem(title: option.category.rawValue.uppercased(), action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                headerItem.font = .systemFont(ofSize: 10, weight: .bold)
                menu.addItem(headerItem)
            }

            let isSelected = (option.modelID == activeModelID)
            let title = isSelected ? "✓ \(option.name)" : "   \(option.name)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = option
            item.isEnabled = true
            item.target = ModelMenuTarget.shared
            item.action = #selector(ModelMenuTarget.itemSelected(_:))

            if isSelected {
                item.state = .on
            }

            menu.addItem(item)
        }

        ModelMenuTarget.shared.onSelect = onSelect

        if let event = event {
            NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}

@MainActor
private final class ModelMenuTarget: NSObject {
    static let shared = ModelMenuTarget()

    var onSelect: ((DynamicModelOption) -> Void)?

    @objc func itemSelected(_ sender: NSMenuItem) {
        if let option = sender.representedObject as? DynamicModelOption {
            onSelect?(option)
        }
    }
}
