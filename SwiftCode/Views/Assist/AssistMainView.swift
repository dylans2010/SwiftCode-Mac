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

    // Apple Intelligence Prompt Enhancement Alert
    @State private var showEnhancementError = false
    @State private var enhancementErrorMessage: String? = nil

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

    // Typing indicator pulse animation state
    @State private var typingIndicatorPulse = false

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

            if manager.messages.isEmpty {
                VStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Conversation",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        description: Text("Chat history cleared. Send a prompt to begin.")
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
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
                                CodeAssistUserView()
                                TaskProgressView(agentSession: manager.agentSession)
                                ToolExecutionView(agentSession: manager.agentSession)
                                AgentChangeSummaryView(agentSession: manager.agentSession)
                                AgentSummaryStatisticsView(agentSession: manager.agentSession)
                                AgentTimelineView(agentSession: manager.agentSession)
                                AgentControlsView(agentSession: manager.agentSession)
                            }

                            if let error = manager.lastError {
                                AssistErrorBubble(error: error)
                            }

                            if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
                                if isAgentMode {
                                    thinkingIndicator
                                } else {
                                    chatTypingIndicator
                                }
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
            }

            Divider()

            // Terminal Execution Approval Overlay
            if let request = manager.pendingTerminalRequest {
                let isDestructive = request.modifiesRepo || request.command.contains("rm ") || request.command.contains("git reset") || request.command.contains("git clean") || request.command.contains("delete") || request.command.contains("remove")

                VStack(alignment: .leading, spacing: 14) {
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
        .alert("There was an issue on this request:", isPresented: $showEnhancementError, presenting: enhancementErrorMessage) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
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

    private func statusUserDescription(for status: AgentSessionStatus) -> String {
        switch status {
        case .idle:
            return "Idle"
        case .receivingRequest:
            return "Receiving new request..."
        case .analyzingRepository:
            return "Analyzing the codebase..."
        case .collectingContext:
            return "Collecting code context..."
        case .planningReview:
            return "Reviewing execution plan..."
        case .awaitingApproval:
            return "Awaiting developer approval..."
        case .executingStrategy:
            return "Executing plan strategy..."
        case .selectingTools:
            return "Selecting available tools..."
        case .executingTools:
            return "Executing tools..."
        case .reviewFailed:
            return "Code review failed, retrying..."
        case .recovering:
            return "Recovering from error..."
        case .generatingSummary:
            return "Generating session summary..."
        case .terminated:
            return "Session terminated."
        case .initializing:
            return "Initializing session..."
        case .understandingRequest:
            return "Analyzing the repository..."
        case .gatheringContext:
            return "Reviewing project structure..."
        case .planning:
            return "Building execution strategy..."
        case .selectingTool:
            return "Selecting the best tool for the task..."
        case .executingTool:
            return "Updating project files..."
        case .waitingForUserApproval:
            return "Waiting for terminal execution approval..."
        case .updatingRepository:
            return "Applying repository updates..."
        case .inspectingResult:
            return "Reviewing action result..."
        case .validating:
            return "Running validation..."
        case .reviewing:
            return "Reviewing implementation quality..."
        case .completing:
            return "Preparing final response..."
        case .finished, .completed:
            return "Task completed successfully."
        case .failed:
            return "Task failed."
        case .cancelled:
            return "Task cancelled."
        case .stalled:
            return "Task execution stalled."
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusUserDescription(for: manager.agentSession.state.status))
                    .font(.caption.bold())
                    .foregroundStyle(.orange)

                if bridgeManager.activeToolName != "None" {
                    Text("Executing: \(bridgeManager.activeToolName)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }

    private var chatTypingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
                .tint(.blue)

            Text("Assist is typing")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .scaleEffect(typingIndicatorPulse ? 1.4 : 0.8)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: typingIndicatorPulse)
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .scaleEffect(typingIndicatorPulse ? 0.8 : 1.4)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.2), value: typingIndicatorPulse)
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .scaleEffect(typingIndicatorPulse ? 1.4 : 0.8)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.4), value: typingIndicatorPulse)
            }
            .onAppear {
                typingIndicatorPulse = true
            }

            Spacer()
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
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
            .disabled(isEnhancingPrompt || inputText.isEmpty || manager.isProcessing || bridgeManager.streamStatus == "Streaming" || isProcessingFiles)
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
        guard !isEnhancingPrompt else { return }
        let currentPrompt = inputText
        guard !currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        withAnimation {
            isEnhancingPrompt = true
        }

        Task {
            let activeModel = currentActiveModelID()
            let result = await PromptEnhancer.enhancePrompt(userInput: currentPrompt, modelID: activeModel)

            await MainActor.run {
                withAnimation {
                    isEnhancingPrompt = false
                }
                switch result {
                case .success(let enhancedPrompt):
                    inputText = enhancedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                case .failure(let error):
                    self.enhancementErrorMessage = error.localizedDescription
                    self.showEnhancementError = true
                }
            }
        }
    }

    private func loadDynamicModels() -> [DynamicModelOption] {
        var modelsList: [DynamicModelOption] = []
        let filter = AssistModelFilter.shared

        // 1. Apple Foundation Models
        if filter.isEnabled(AppleFoundationModel.afm3Core.rawValue) {
            modelsList.append(DynamicModelOption(
                modelID: AppleFoundationModel.afm3Core.rawValue,
                name: "Apple AFM 3 Core",
                provider: "Apple Private on-device reasoning",
                status: "On-Device",
                isAvailable: true,
                category: .apple
            ))
        }
        if filter.isEnabled(AppleFoundationModel.afm3CoreAdvanced.rawValue) {
            modelsList.append(DynamicModelOption(
                modelID: AppleFoundationModel.afm3CoreAdvanced.rawValue,
                name: "Apple AFM 3 Core Advanced",
                provider: "Apple Private on-device reasoning (voice)",
                status: "On-Device",
                isAvailable: true,
                category: .apple
            ))
        }

        // 2. HuggingFace Local Models
        let localModels = OfflineModelManager.shared.installedModels
        for m in localModels {
            if filter.isEnabled(m.modelName) {
                modelsList.append(DynamicModelOption(
                    modelID: m.modelName,
                    name: m.modelName,
                    provider: "HuggingFace Local",
                    status: "Downloaded",
                    isAvailable: true,
                    category: .local
                ))
            }
        }

        // 3. Custom endpoint/link models
        let customEndpoints = CustomEndpointManager.shared.endpoints
        for endpoint in customEndpoints {
            if endpoint.showInPopup {
                for m in endpoint.models {
                    if filter.isEnabled(m) {
                        modelsList.append(DynamicModelOption(
                            modelID: m,
                            name: "\(m) (\(endpoint.name))",
                            provider: endpoint.name,
                            status: endpoint.isLocal ? "Local" : "Cloud",
                            isAvailable: true,
                            category: .custom
                        ))
                    }
                }
            }
        }

        // 4. OpenRouter Cloud Models (Fallback Presets or fetched)
        if !fetchedOpenRouterModels.isEmpty {
            for m in fetchedOpenRouterModels {
                if filter.isEnabled(m.id) {
                    modelsList.append(DynamicModelOption(
                        modelID: m.id,
                        name: m.name,
                        provider: "OpenRouter Cloud",
                        status: "Cloud",
                        isAvailable: true,
                        category: .openRouter
                    ))
                }
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
                if filter.isEnabled(preset.0) {
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

        // Ensure a completely new URLSession is created via ModelSessionManager to avoid using cached connections or older models
        Task {
            await ModelSessionManager.shared.switchModel(to: option.modelID)
        }
    }
}

// MARK: - Agent Summary Statistics View

struct AgentSummaryStatisticsView: View {
    let agentSession: AssistAgentSession

    var body: some View {
        if let summary = agentSession.executionSummary {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .foregroundStyle(.orange)
                        Text("Execution Statistics Dashboard")
                            .font(.subheadline.bold())
                        Spacer()
                    }

                    Divider()

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        statCard(title: "Execution Duration", value: String(format: "%.1fs", summary.totalDuration), icon: "clock", color: .blue)
                        statCard(title: "Tool Executions", value: "\(summary.toolCallCount)", icon: "wrench.and.screwdriver", color: .orange)
                        statCard(title: "Files Affected", value: "\(summary.filesCreatedCount + summary.filesModifiedCount + summary.filesDeletedCount)", icon: "doc.fill", color: .green)
                        statCard(title: "Validation Passes", value: "\(summary.validationCount)", icon: "checkmark.shield", color: .purple)
                    }
                    .padding(.top, 4)
                }
                .padding(4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Agent Change Summary View

struct AgentChangeSummaryView: View {
    let agentSession: AssistAgentSession
    @State private var isExpanded = true

    var body: some View {
        let summary = agentSession.state.changeSummary
        let hasChanges = !summary.modifiedFiles.isEmpty ||
                          !summary.createdFiles.isEmpty ||
                          !summary.deletedFiles.isEmpty ||
                          !summary.renamedFiles.isEmpty ||
                          !summary.movedFiles.isEmpty ||
                          !summary.configChanges.isEmpty ||
                          !summary.toolActivities.isEmpty

        if !hasChanges {
            EmptyView()
        } else {
            GroupBox {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .padding(.vertical, 4)

                        if !summary.createdFiles.isEmpty {
                            changeSection(title: "Created Files", icon: "doc.badge.plus", color: .green, items: summary.createdFiles)
                        }

                        if !summary.modifiedFiles.isEmpty {
                            changeSection(title: "Modified Files", icon: "doc.badge.gearshape", color: .blue, items: summary.modifiedFiles)
                        }

                        if !summary.deletedFiles.isEmpty {
                            changeSection(title: "Deleted Files", icon: "doc.badge.ellipsis", color: .red, items: summary.deletedFiles)
                        }

                        if !summary.renamedFiles.isEmpty {
                            changeSection(title: "Renamed Files", icon: "pencil.and.outline", color: .purple, items: summary.renamedFiles)
                        }

                        if !summary.movedFiles.isEmpty {
                            changeSection(title: "Moved Files", icon: "arrow.right.doc.on.clipboard", color: .orange, items: summary.movedFiles)
                        }

                        if !summary.configChanges.isEmpty {
                            changeSection(title: "Project Configuration Changes", icon: "gearshape.2", color: .yellow, items: summary.configChanges)
                        }

                        if !summary.toolActivities.isEmpty {
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(summary.toolActivities) { activity in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(activity.toolId)
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(.orange)
                                                Spacer()
                                                Text(activity.timestamp, style: .time)
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(activity.purpose)
                                                .font(.caption2)
                                                .foregroundStyle(.primary)
                                            Text(activity.result)
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .padding(.vertical, 2)
                                        Divider()
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .foregroundStyle(.gray)
                                    Text("Tool Activity Log (\(summary.toolActivities.count))")
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "checklist.checked")
                            .foregroundStyle(.green)
                        Text("Repository Changes Summary")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                }
                .padding(4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        }
    }

    private func changeSection(title: String, icon: String, color: Color, items: [FileChangeItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.12), in: Capsule())
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.filename)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(.primary)
                        Text(item.details)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 2)
                }
            }
            Divider()
                .padding(.vertical, 2)
        }
    }
}

// MARK: - Execution Mode Sheet

struct ExecutionModeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("com.swiftcode.assist.mode") private var isAgentMode = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Select Execution Mode")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            VStack(spacing: 12) {
                // Chat Mode Button
                Button {
                    isAgentMode = false
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "text.bubble.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chat Mode")
                                .font(.subheadline.bold())
                            Text("A conversational assistant. Safe, read-only, and will not make autonomous changes to your project.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if !isAgentMode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Agent Mode Button
                Button {
                    isAgentMode = true
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cpu.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Agent Mode")
                                .font(.subheadline.bold())
                            Text("An autonomous software engineering agent. Can build, test, repair, and apply plans with your permission.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if isAgentMode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Diagnostics Sheet

struct UnifiedLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let source: String      // "Assist", "SwiftCode", "Deployment"
    let level: String       // "INFO", "WARN", "ERROR", "DEBUG", "SUCCESS"
    let category: String?   // Category or tool ID
    let message: String
}

struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: AssistManager
    @State private var searchText = ""
    @State private var selectedSeverity = "All"
    @State private var selectedProvider = "All"

    private let severities = ["All", "INFO", "WARN", "ERROR", "DEBUG", "SUCCESS"]
    private let providers = ["All", "OpenRouter", "OpenAI", "Anthropic", "Gemini", "Apple", "None"]

    private var filteredEventsGrouped: [String: [DiagnosticEvent]] {
        let events = DiagnosticEventBus.shared.events

        let filtered = events.filter { event in
            // Search text filter
            if !searchText.isEmpty {
                let term = searchText.lowercased()
                guard event.message.lowercased().contains(term) ||
                      event.component.lowercased().contains(term) ||
                      (event.errorDescription?.lowercased().contains(term) ?? false) else {
                    return false
                }
            }

            // Severity filter
            if selectedSeverity != "All" {
                guard event.severity == selectedSeverity else { return false }
            }

            // Provider filter
            if selectedProvider != "All" {
                guard event.provider.lowercased().contains(selectedProvider.lowercased()) else { return false }
            }

            return true
        }

        // Group by category, order most-recent-first (chronologically descending)
        let sorted = filtered.sorted { $0.timestamp > $1.timestamp }
        return Dictionary(grouping: sorted, by: { $0.category })
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "ERROR": return .red
        case "WARN": return .orange
        case "SUCCESS": return .green
        case "DEBUG": return .gray
        default: return .blue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("System Telemetry & Diagnostics", systemImage: "terminal.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            // Telemetry / Status Cards
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Active Engine Status") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Selected Model:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(manager.selectedModel.displayName)
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack {
                                Text("Active Tool ID:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(CodexBridgeManager.shared.activeToolName)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            HStack {
                                Text("Running State:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(manager.isProcessing ? "Processing (Active)" : "Idle")
                                    .foregroundColor(manager.isProcessing ? .green : .secondary)
                            }
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.horizontal)

                    GroupBox("Diagnostics Logs") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Recent Events")
                                    .font(.caption.bold())
                                Spacer()
                                Button("Clear All Logs") {
                                    DiagnosticEventBus.shared.clear()
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }

                            // Interactive Filters
                            HStack(spacing: 12) {
                                Picker("Severity:", selection: $selectedSeverity) {
                                    ForEach(severities, id: \.self) { sev in
                                        Text(sev).tag(sev)
                                    }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)

                                Picker("Provider:", selection: $selectedProvider) {
                                    ForEach(providers, id: \.self) { prov in
                                        Text(prov).tag(prov)
                                    }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                            }

                            // Unified Log Search Filter
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Filter logs...", text: $searchText)
                                    .textFieldStyle(.plain)
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.bottom, 4)

                            let grouped = filteredEventsGrouped
                            if grouped.isEmpty {
                                Text("No matching diagnostic events captured.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 8) {
                                        ForEach(grouped.keys.sorted(), id: \.self) { category in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(category.uppercased())
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.purple)
                                                    .padding(.top, 4)

                                                ForEach(grouped[category] ?? []) { event in
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text("[\(event.component)]")
                                                                .foregroundColor(.orange)
                                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                            Text("[\(event.severity)]")
                                                                .foregroundColor(severityColor(event.severity))
                                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                            Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                                                .font(.system(size: 9, design: .monospaced))
                                                                .foregroundColor(.secondary)
                                                            if event.provider != "None" {
                                                                Text("[\(event.provider)]")
                                                                    .font(.system(size: 9, design: .monospaced))
                                                                    .foregroundColor(.blue)
                                                            }
                                                        }
                                                        Text(event.message)
                                                            .font(.system(size: 10, design: .monospaced))
                                                            .foregroundColor(.primary)
                                                        if let desc = event.errorDescription {
                                                            Text(desc)
                                                                .font(.system(size: 9, design: .monospaced))
                                                                .foregroundColor(.secondary)
                                                                .padding(.leading, 8)
                                                        }
                                                    }
                                                    .padding(.bottom, 4)
                                                }
                                                Divider()
                                            }
                                        }
                                    }
                                }
                                .frame(height: 250)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .frame(width: 520, height: 550)
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
                let blocks = MarkdownParser.shared.parse(message.content)
                if blocks.isEmpty && !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else {
                    MarkdownBlockListView(blocks: blocks)
                        .textSelection(.enabled)
                }

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
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold)
                ]
                headerItem.attributedTitle = NSAttributedString(string: option.category.rawValue.uppercased(), attributes: attrs)
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
