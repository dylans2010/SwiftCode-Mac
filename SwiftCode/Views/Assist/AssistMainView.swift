import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistMainView")

/// Highly-optimized, native desktop-first macOS experience for the SwiftCode Assist conversation workspace.
public struct AssistMainView: View {
    @StateObject private var manager = AssistManager.shared
    @State private var inputText: String = ""
    @State private var isEnhancingPrompt = false
    @State private var showDiagnosticsSheet = false
    @State private var showAgentNotesSheet = false
    @State private var showArtifactsSheet = false
    @State private var showExecutionModeSheet = false
    @State private var showSDKModelProviderList = false
    @State private var showApprovalSheet = false
    @State private var searchConversationText = ""
    @State private var attachedFiles: [AgentFileContext] = []
    @State private var showingFilePickerSheet = false
    @State private var isProcessingFiles = false
    @State private var fetchedOpenRouterModels: [OpenRouterModel] = []

    // Message Queue State
    @State private var editingQueueId: UUID? = nil
    @State private var editingQueueText: String = ""
    @State private var isQueueExpanded: Bool = true

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

    // Execution Mode: Plan vs Autopilot
    @AppStorage("com.swiftcode.assist.executionMode") private var executionModeRaw: String = ExecutionMode.autopilot.rawValue

    // Assist Configuration
    @AppStorage("com.swiftcode.assist.enableCodeReview") private var enableCodeReview = true

    // Create New App Wizard Sheet
    @State private var showCreateNewAppSheet = false
    @State private var showConversationsSheet = false
    @State private var showReverseFillOut = false

    // Composer @ and / systems
    @State private var selectedExplicitSkills: [SkillDescriptor] = []
    @State private var selectedExplicitMCPServers: [String] = []
    @State private var selectedExplicitFiles: [AgentFileContext] = []
    @State private var composerTriggerMode: ComposerTriggerMode? = nil
    @State private var selectedMetaCommandForArgs: MetaSlashCommand? = nil
    @State private var showCustomModelPicker = false
    @State private var showSpeechUI = false
    @State private var discoveryService = AssistModelDiscoveryService.shared
    @ObservedObject private var googleAuth = GoogleAccountAuthService.shared
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Button {
                    searchConversationText = ""
                    attachedFiles = []
                    selectedExplicitSkills = []
                    selectedExplicitMCPServers = []
                    selectedExplicitFiles = []
                    editingQueueId = nil
                    editingQueueText = ""
                    manager.clearChat()
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Clear Chat History (⌘K)")

                Button {
                    showConversationsSheet = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Conversations History")

                Spacer()

                Button {
                    if [AssistModelProvider.openCode, .openRouter, .hermes].contains(AssistProviderSelection.persistedProvider) {
                        showSDKModelProviderList = true
                    } else {
                        showExecutionModeSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isAgentMode ? "cpu" : "text.bubble")
                            .font(.caption)
                        Text(isAgentMode ? "Agent" : "Chat")
                            .font(.caption.weight(.medium))
                    }
                }
                .buttonStyle(.borderless)
                .help("Toggle Execution Mode")

                executionModePopover

                Spacer()

                // Create New App Trigger
                Button {
                    showCreateNewAppSheet = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Create New App Wizard")

                // Workers Trigger (Native Assist Workers Entry)
                WorkersHeaderButton()

                // Real Execution Plan Trigger (Strictly hidden until a real execution plan exists)
                if !AgentNotesManager.shared.currentNotesMarkdown.isEmpty || TasksAIPlanner.shared.currentPlan != nil {
                    Button {
                        showAgentNotesSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.caption)
                            Text("Execution Plan")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Inspect Real Execution Plan & Phase Matrix")
                    .transition(.scale.combined(with: .opacity))
                }

                // Artifacts Trigger (native Markdown deliverable library)
                Button {
                    showArtifactsSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.richtext")
                            .font(.caption)
                        Text("Artifacts")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Browse Saved Artifacts")

                // Feedback Trigger
                AssistHeaderFeedbackButton()

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
                // Native macOS Conversation ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
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
                            .liquidGlass(style: .subtle, cornerRadius: 8)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                            // Native Conversational Chat Bubbles
                            // Notice messages (warnings/errors) render as their own
                            // tappable yellow/red cards, not plain bubbles.
                            ForEach(filteredMessages) { message in
                                if let composio = message.composioExecution {
                                    AgentUseComposio(metadata: composio)
                                } else if let mcp = message.mcpExecution {
                                    AgentUseMCP(metadata: mcp)
                                } else if message.noticeLevel != nil {
                                    AssistNoticeView(message: message)
                                } else {
                                    AssistChatBubble(message: message)
                                }
                            }

                            if let error = manager.lastError {
                                AssistInlineDiagnostic(
                                    message: error,
                                    severity: .error,
                                    date: manager.lastErrorDate,
                                    phase: manager.lastErrorPhase
                                )
                            }

                            if let warning = manager.lastWarning {
                                AssistInlineDiagnostic(
                                    message: warning,
                                    severity: .warning,
                                    date: manager.lastWarningDate,
                                    phase: manager.lastWarningPhase
                                )
                            }

                            processingIndicator
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
                                } else if manager.terminalExitCode == 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Execution Succeeded (Exit code 0)")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                } else {
                                    let exitCode = manager.terminalExitCode ?? -1
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text("Execution Failed (Exit code \(exitCode))")
                                        .font(.caption.bold())
                                        .foregroundColor(.red)
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

                WorkersOnAssistView()

                queuedMessagesView

                inputArea
            }
            .padding(12)
            .background(.thinMaterial)
        }
        .background(.windowBackground)
        .overlay {
            PlanUserAskView()
        }
        .sheet(isPresented: $showingCodexSetup) {
            CodexSignInFlow()
        }
        .sheet(isPresented: $showSDKModelProviderList) {
            SDKModelProviderList()
        }
        .sheet(isPresented: $showExecutionModeSheet) {
            ExecutionModeSheet()
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            DiagnosticsSheet(manager: manager)
        }
        .sheet(isPresented: $showAgentNotesSheet) {
            AgentNotesInspectorView()
        }
        .sheet(isPresented: $showArtifactsSheet) {
            AssistArtifactsView()
        }
        .sheet(isPresented: $showCreateNewAppSheet) {
            CreateNewAppWizardView()
        }
        .sheet(isPresented: $showConversationsSheet) {
            AssistConversationsSheet()
        }
        .alert("There was an issue on this request:", isPresented: $showEnhancementError, presenting: enhancementErrorMessage) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
        .task {
            await updateCodexButtonVisibility()
            await fetchOpenRouterModelsBackground()
            if discoveryService.discoveredModels.isEmpty {
                await discoveryService.discoverAllModels(forceRefresh: true)
            }
        }
        .onChange(of: showingCodexSetup) { _, newValue in
            if !newValue {
                Task {
                    await updateCodexButtonVisibility()
                }
            }
        }

        .onChange(of: bridgeManager.activeToolName) { _, newTool in
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

    private var executionModePopover: some View {
        Menu {
            ForEach(ExecutionMode.allCases, id: \.self) { mode in
                Button {
                    executionModeRaw = mode.rawValue
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if executionModeRaw == mode.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: executionModeRaw == "Plan" ? "list.bullet.rectangle" : "arrow.triangle.2.circlepath")
                    .font(.caption)
                Text(executionModeRaw)
                    .font(.caption.weight(.medium))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Execution Mode: \(executionModeRaw)")
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
            return "Preparing request…"
        case .analyzingRepository:
            return "Inspecting the project..."
        case .collectingContext:
            return "Reading relevant files..."
        case .planningReview:
            return "Reviewing the plan..."
        case .awaitingApproval:
            return "Waiting for your approval..."
        case .executingStrategy:
            return "Working on it..."
        case .selectingTools:
            return "Deciding how to proceed..."
        case .executingTools:
            return "Making changes..."
        case .reviewFailed:
            return "Reviewing the changes..."
        case .recovering:
            return "Fixing an issue..."
        case .generatingSummary:
            return "Wrapping up..."
        case .terminated:
            return "Done."
        case .initializing:
            return "Starting..."
        case .understandingRequest:
            return "Understanding the request..."
        case .gatheringContext:
            return "Inspecting the project..."
        case .planning:
            return "Determining the best approach..."
        case .selectingTool:
            return "Deciding how to proceed..."
        case .executingTool:
            return "Making changes..."
        case .waitingForUserApproval:
            return "Waiting for your approval..."
        case .updatingRepository:
            return "Applying changes..."
        case .inspectingResult:
            return "Checking the result..."
        case .validating:
            return "Verifying..."
        case .reviewing:
            return "Reviewing the implementation..."
        case .completing:
            return "Almost done..."
        case .finished, .completed:
            return "Done."
        case .failed:
            return "Something went wrong."
        case .cancelled:
            return "Cancelled."
        case .stalled:
            return "Taking longer than expected..."
        case .evaluatingGoalExpansion:
            return "Considering next steps..."
        case .transitioningToNextGoal:
            return "Moving to the next task..."
        default:
            return "Working..."
        }
    }

    private var activityStatusIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
                .tint(.secondary)

            let displayText: String = {
                if !manager.currentActivityStatus.isEmpty && manager.currentActivityStatus != "Idle" {
                    return manager.currentActivityStatus
                }
                let sessionDescription = statusUserDescription(for: manager.agentSession.state.status)
                return sessionDescription == "Idle" ? "Preparing request…" : sessionDescription
            }()

            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if bridgeManager.activeToolName != "None" {
                Text("· \(bridgeManager.activeToolName)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var processingIndicator: some View {
        if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
            let lastMessage = manager.messages.last
            let hasActiveToolActivity = lastMessage?.activityGroup?.tools.contains {
                $0.status == .pending || $0.status == .running || $0.status == .retrying
            } == true
            // Derive from the request phase (single source of truth), not
            // from string-matching the activity label.
            let isStreamingChatResponse = lastMessage?.role == .assistant &&
                lastMessage?.content.isEmpty == false && manager.requestPhase == .receivingResponse
            let isActivelyThinking = lastMessage?.role == .assistant &&
                (lastMessage?.thinkingContent?.isEmpty == false) && manager.requestPhase == .waitingForModel

            if !hasActiveToolActivity && !isStreamingChatResponse && !isActivelyThinking {
                activityStatusIndicator
            }
        }
    }

    // MARK: - Queued Messages View

    @ViewBuilder
    private var queuedMessagesView: some View {
        if !manager.queuedMessages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text("Queued Messages (\(manager.queuedMessages.count))")
                        .font(.system(size: 12, weight: .semibold))

                    Text("· will auto-send once active response completes")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isQueueExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isQueueExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isQueueExpanded ? "Collapse Queue" : "Expand Queue")

                    Button {
                        withAnimation {
                            manager.clearQueue()
                        }
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Clear All Queued Messages")
                }
                .padding(.horizontal, 4)

                // List
                if isQueueExpanded {
                    VStack(spacing: 6) {
                        ForEach(Array(manager.queuedMessages.enumerated()), id: \.element.id) { index, item in
                            queuedMessageRow(index: index, item: item)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func queuedMessageRow(index: Int, item: QueuedAssistMessage) -> some View {
        let isEditing = editingQueueId == item.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Index badge
                Text("#\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundColor(.accentColor)

                if isEditing {
                    TextField("Edit queued message...", text: $editingQueueText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .lineLimit(1...4)
                        .onSubmit {
                            saveEditedQueueItem(id: item.id)
                        }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.content)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let envelope = item.envelope {
                            let skillCount = envelope.explicitSkills.count
                            let mcpCount = envelope.explicitMCPServers.count
                            let fileCount = envelope.explicitFiles.count
                            if skillCount + mcpCount + fileCount > 0 {
                                HStack(spacing: 6) {
                                    if skillCount > 0 {
                                        Label("\(skillCount) skill\(skillCount == 1 ? "" : "s")", systemImage: "wand.and.stars")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    if mcpCount > 0 {
                                        Label("\(mcpCount) MCP", systemImage: "server.rack")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    if fileCount > 0 {
                                        Label("\(fileCount) file\(fileCount == 1 ? "" : "s")", systemImage: "doc")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else if !item.attachments.isEmpty {
                            Label("\(item.attachments.count) attachment\(item.attachments.count == 1 ? "" : "s")", systemImage: "paperclip")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    if isEditing {
                        Button {
                            saveEditedQueueItem(id: item.id)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Save Changes")

                        Button {
                            editingQueueId = nil
                            editingQueueText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel Editing")
                    } else {
                        Button {
                            manager.sendQueuedMessageNow(id: item.id)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                Text("Send Now")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Interrupt and Send Immediately")

                        Button {
                            editingQueueId = item.id
                            editingQueueText = item.content
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit Queued Message")

                        Button {
                            withAnimation {
                                manager.removeQueuedMessage(id: item.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Remove from Queue")
                    }
                }
            }

            if !item.attachments.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.attachments) { att in
                        HStack(spacing: 3) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text(att.filename)
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
    }

    private func saveEditedQueueItem(id: UUID) {
        manager.updateQueuedMessage(id: id, newContent: editingQueueText)
        editingQueueId = nil
        editingQueueText = ""
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Selected explicit context chips (@MCP, @Files, /Skills)
            AssistComposerChipsBar(
                selectedSkills: $selectedExplicitSkills,
                selectedMCPServers: $selectedExplicitMCPServers,
                selectedFiles: $selectedExplicitFiles,
                onRemoveSkill: { skill in
                    selectedExplicitSkills.removeAll(where: { $0.id == skill.id })
                },
                onRemoveMCP: { server in
                    selectedExplicitMCPServers.removeAll(where: { $0 == server })
                },
                onRemoveFile: { file in
                    selectedExplicitFiles.removeAll(where: { $0.id == file.id })
                }
            )

            HStack(spacing: 8) {
                Button {
                    showingFilePickerSheet = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .sheet(isPresented: $showingFilePickerSheet) {
                    AddFilesAgentContext(attachedFiles: $attachedFiles, isProcessingFiles: $isProcessingFiles)
                }
                .help("Attach Files to Context")

                Button {
                    showSpeechUI = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(showSpeechUI ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Voice Assistant Input")
                .popover(isPresented: $showSpeechUI, arrowEdge: .top) {
                    AssistSpeechUI(
                        onSend: { text in
                            Task {
                                await manager.sendMessage(text)
                            }
                        },
                        onInsert: { text in
                            if inputText.isEmpty {
                                inputText = text
                            } else {
                                inputText += " " + text
                            }
                        }
                    )
                }

                Button {
                    if [AssistModelProvider.openCode, .openRouter, .hermes].contains(AssistProviderSelection.persistedProvider) {
                        showSDKModelProviderList = true
                    } else {
                        showCustomModelPicker.toggle()
                    }
                } label: {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(showCustomModelPicker ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Choose Model")
                .popover(isPresented: $showCustomModelPicker, arrowEdge: .top) {
                    if settings.isMetaAssist {
                        MetaAssistModelsUI()
                            .frame(width: 480)
                            .padding()
                    } else if googleAuth.isAuthenticated && AppSettings.shared.assistModelRoutingStrategy == "default" {
                        AntigravityLimitsModelsUI(
                            selectedModelID: currentActiveModelID(),
                            onSelect: { selectedModelID in
                                let model = AssistModelRouter.shared.createSyntheticSDKModel(modelID: selectedModelID)
                                selectDiscoveredModel(model)
                                showCustomModelPicker = false
                            },
                            onDismiss: {
                                showCustomModelPicker = false
                            }
                        )
                    } else {
                        AssistCustomModelPickerPopover(
                            selectedModelID: currentActiveModelID(),
                            onSelect: { selectedModel in
                                selectDiscoveredModel(selectedModel)
                                showCustomModelPicker = false
                            },
                            onDismiss: {
                                showCustomModelPicker = false
                            }
                        )
                    }
                }

                Button {
                    expandPrompt()
                } label: {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isEnhancingPrompt ? .secondary : .primary)
                        .padding(7)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .disabled(isEnhancingPrompt || inputText.isEmpty || isProcessingFiles)
                .help("Enhance prompt with Apple Intelligence")

                ZStack {
                    let isBusy = manager.isProcessing || bridgeManager.streamStatus == "Streaming"
                    let placeholder = isBusy ? "Queue next message..." : "What should I build next? (Type @ for MCP/files, / for skills)"
                    TextField(placeholder, text: $inputText, axis: .vertical)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.regularMaterial)
                        )
                        .lineLimit(1...5)
                        .disabled(isEnhancingPrompt || isProcessingFiles)
                        .onSubmit {
                            submitMessage()
                        }
                        .onChange(of: inputText) { _, newValue in
                            updateComposerTrigger(for: newValue)
                        }
                }
                .overlay {
                    if isEnhancingPrompt {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isEnhancingPrompt)

                if isProcessingFiles {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                } else if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
                    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        // Send Now button (interrupts active turn and continues conversation immediately)
                        Button {
                            let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let files = attachedFiles
                            let envelope = AssistTaskEnvelope(
                                userMessage: text,
                                explicitSkills: selectedExplicitSkills,
                                explicitMCPServers: selectedExplicitMCPServers,
                                explicitFiles: selectedExplicitFiles + files,
                                reverseInvocation: ReverseCommandParser.parse(message: text)
                            )
                            attachedFiles = []
                            selectedExplicitSkills = []
                            selectedExplicitMCPServers = []
                            selectedExplicitFiles = []
                            inputText = ""
                            manager.interruptActiveSessionAndSend(content: text, attachments: files, envelope: envelope)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                Text("Send Now")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Interrupt current turn and send immediately")

                        // Queue button (queues message to send once current completes)
                        Button(action: submitMessage) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13))
                                Text("Queue")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Queue to send after current response completes (Return)")
                    }

                    Button(action: {
                        manager.stopCurrentSession()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop execution")
                } else {
                    Button(action: submitMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.plain)
                }
            }
        }
        .popover(isPresented: $showReverseFillOut, arrowEdge: .top) {
            ReverseFillOutView(
                isPresented: $showReverseFillOut,
                onInsert: { command in
                    inputText = command
                },
                onSubmit: { command in
                    inputText = command
                    submitMessage()
                }
            )
        }
        .overlay(alignment: .bottomLeading) {
            if let mode = composerTriggerMode {
                AssistComposerPopupView(
                    mode: mode,
                    onSelectSkill: { skill in selectSkill(skill) },
                    onSelectMCP: { server in selectMCP(server) },
                    onSelectFile: { url in selectFile(url) },
                    onSelectMetaCommand: { command, arg in selectMetaCommand(command, argument: arg) },
                    onRequestCommandArguments: { command in
                        selectedMetaCommandForArgs = command
                        composerTriggerMode = nil
                    },
                    onSelectReverse: { selectReverse() },
                    onDismiss: { composerTriggerMode = nil }
                )
                .padding(.bottom, 60)
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let command = selectedMetaCommandForArgs {
                MetaCommandArgumentPickerView(
                    command: command,
                    onSelect: { chosenArg in
                        selectMetaCommand(command, argument: chosenArg)
                        selectedMetaCommandForArgs = nil
                    },
                    onDismiss: {
                        selectedMetaCommandForArgs = nil
                    }
                )
                .padding(.bottom, 60)
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased() == "@reverse" {
            showReverseFillOut = true
            return
        }
        guard !text.isEmpty && !isProcessingFiles else { return }

        let filesToSend = attachedFiles
        // Parse @Reverse here so the structured invocation rides on the
        // envelope (provider paths, history) in addition to the text the
        // intent classifier routes on.
        let envelope = AssistTaskEnvelope(
            userMessage: text,
            explicitSkills: selectedExplicitSkills,
            explicitMCPServers: selectedExplicitMCPServers,
            explicitFiles: selectedExplicitFiles + filesToSend,
            reverseInvocation: ReverseCommandParser.parse(message: text)
        )
        attachedFiles = []
        selectedExplicitSkills = []
        selectedExplicitMCPServers = []
        selectedExplicitFiles = []
        inputText = ""

        if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                manager.enqueueMessage(text, attachments: filesToSend, envelope: envelope)
            }
            return
        }

        Task {
            await manager.sendMessage(text, attachments: filesToSend, envelope: envelope)
        }
    }

    private func updateComposerTrigger(for text: String) {
        guard let lastWord = text.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) else {
            composerTriggerMode = nil
            return
        }

        if lastWord.hasPrefix("@") {
            let query = String(lastWord.dropFirst())
            composerTriggerMode = .resource(query: query)
        } else if lastWord.hasPrefix("/") {
            let query = String(lastWord.dropFirst())
            if settings.isMetaAssist && settings.useMetaSlashCommands {
                composerTriggerMode = .metaCommand(query: query)
            } else {
                composerTriggerMode = .skill(query: query)
            }
        } else {
            composerTriggerMode = nil
        }
    }

    private func selectMetaCommand(_ command: MetaSlashCommand, argument: String?) {
        consumeTrailingToken(prefix: "/")
        composerTriggerMode = nil
        selectedMetaCommandForArgs = nil

        Task {
            let result = await MetaSlashCommandManager.shared.executeCommand(command, argument: argument)
            await MainActor.run {
                if result.hasPrefix("/") {
                    self.inputText = result
                } else {
                    logger.info("Meta slash command executed: \(result)")
                }
            }
        }
    }

    private func consumeTrailingToken(prefix: String) {
        var words = inputText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let last = words.last, last.hasPrefix(prefix) {
            words.removeLast()
            inputText = words.joined(separator: " ") + (words.isEmpty ? "" : " ")
        }
    }

    private func selectSkill(_ skill: SkillDescriptor) {
        if !selectedExplicitSkills.contains(where: { $0.id == skill.id }) {
            selectedExplicitSkills.append(skill)
        }
        consumeTrailingToken(prefix: "/")
        composerTriggerMode = nil
    }

    /// Opens the ReverseFillOutView popover so the user can configure
    /// target artifact, analysis operation, and investigation query via a Form.
    private func selectReverse() {
        consumeTrailingToken(prefix: "@")
        composerTriggerMode = nil
        showReverseFillOut = true
    }

    private func selectMCP(_ server: String) {
        if !selectedExplicitMCPServers.contains(server) {
            selectedExplicitMCPServers.append(server)
        }
        consumeTrailingToken(prefix: "@")
        composerTriggerMode = nil
    }

    private func selectFile(_ url: URL) {
        consumeTrailingToken(prefix: "@")
        composerTriggerMode = nil
        Task {
            if let fileCtx = try? await FileAgentHelper.processFile(at: url) {
                await MainActor.run {
                    if !selectedExplicitFiles.contains(where: { $0.filename == fileCtx.filename }) {
                        selectedExplicitFiles.append(fileCtx)
                    }
                }
            }
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
        }

        return modelsList
    }

    private func currentActiveModelID() -> String {
        if FoundationModels.shared.isEnabled {
            return FoundationModels.shared.selectedModel.rawValue
        }
        if !AppSettings.shared.selectedAssistModelID.isEmpty {
            return AppSettings.shared.selectedAssistModelID
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
            AppSettings.shared.selectedAssistModelID = option.modelID
            if AppSettings.shared.assistModelRoutingStrategy == "app_models" {
                AppSettings.shared.useSavedModels = true
            }
            AssistModelManager.shared.customModelID = option.modelID
        }

        Task {
            await ModelSessionManager.shared.switchModel(to: option.modelID)
            AssistManager.shared.resetActiveGoogleCloudSessionIfModelChanged(to: option.modelID)
        }
    }

    private func selectDiscoveredModel(_ model: AssistAvailableModel) {
        logger.log("[selectModel] Selecting model: \(model.modelIdentifier) from \(model.providerName)")

        if model.source == .appleFoundationModels || model.source == .appleFoundation || model.providerName == "Apple Foundation Models" {
            FoundationModels.shared.isEnabled = true
            if let appleModel = AppleFoundationModel(rawValue: model.modelIdentifier) {
                FoundationModels.shared.selectedModel = appleModel
            }
        } else {
            FoundationModels.shared.isEnabled = false
            AppSettings.shared.selectedModel = model.modelIdentifier
            AppSettings.shared.selectedAssistModelID = model.modelIdentifier
            if AppSettings.shared.assistModelRoutingStrategy == "app_models" {
                AppSettings.shared.useSavedModels = true
            }
            AssistModelManager.shared.customModelID = model.modelIdentifier
        }

        Task {
            await ModelSessionManager.shared.switchModel(to: model.modelIdentifier)
            AssistModelRouter.shared.currentRuntimeModel = model
            AssistManager.shared.resetActiveGoogleCloudSessionIfModelChanged(to: model.modelIdentifier)
        }
    }
}

// MARK: - Subviews

/// Warning/error notice message: yellow for warnings, red for errors.
/// Tappable to expand/collapse. When the notice carries a ServerErrorDetail,
/// a "(Server Error)" button opens a dialog showing the raw API exchange —
/// endpoint, status code, timestamp, verbatim response body — all copyable.
private struct AssistNoticeView: View {
    let message: AssistMessage
    @State private var expanded = false
    @State private var showingServerError = false

    private var isError: Bool { message.noticeLevel == .error }
    private var tint: Color { isError ? .red : .yellow }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .font(.system(size: 14))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.content)
                            .font(.system(size: 12))
                            .foregroundStyle(tint)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Text(expanded ? "Show less" : "Tap to expand")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if message.serverError != nil {
                    Button("(Server Error)") { showingServerError = true }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.35), lineWidth: 1))
        .sheet(isPresented: $showingServerError) {
            if let detail = message.serverError {
                ServerErrorDialog(detail: detail)
            }
        }
    }
}

/// Small dialog showing a model API error exactly as the server returned it.
/// Nothing here is hardcoded: endpoint, status code, timestamp, and the
/// verbatim response body all come from the live HTTP exchange.
private struct ServerErrorDialog: View {
    let detail: ServerErrorDetail
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Server Error", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy") { copyAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(copied)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Endpoint").font(.caption).foregroundStyle(.secondary)
                    Text(detail.endpoint)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Status").font(.caption).foregroundStyle(.secondary)
                    Text(detail.statusCode.map(String.init) ?? "No response")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Time").font(.caption).foregroundStyle(.secondary)
                    Text(detail.timestamp, format: .dateTime.hour().minute().second())
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                }
            }

            Divider()

            Text("Response body")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(detail.rawBody)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 380)
    }

    private func copyAll() {
        let text = """
            Endpoint: \(detail.endpoint)
            Status: \(detail.statusCode.map(String.init) ?? "No response")
            Time: \(detail.timestamp)
            Body:
            \(detail.rawBody)
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}

private struct AssistChatBubble: View {
    let message: AssistMessage
    @ObservedObject private var manager = AssistManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var sdkEventStore = SDKToolEventStore.shared

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return Color.primary.opacity(0.06)
        case .assistant: return Color.secondary.opacity(0.06)
        case .system: return Color.secondary.opacity(0.08)
        }
    }

    private var isCurrentlyThinking: Bool {
        message.role == .assistant &&
        message.id == manager.messages.last?.id &&
        manager.isProcessing &&
        message.content.isEmpty
    }

    @ViewBuilder
    var body: some View {
        let hasThinking = message.thinkingContent?.isEmpty == false
        let hasActivity = message.activityGroup?.hasContent == true
        let hasContent = !message.content.isEmpty
        let hasAttachments = message.attachments?.isEmpty == false
        let isMetaMessage = message.providerID == MetaAssistProvider.providerID || (settings.isMetaAssist && message.role == .assistant)

        if message.role == .assistant && !hasContent && !hasActivity && !hasThinking && !hasAttachments {
            EmptyView()
        } else {
            VStack(alignment: alignment, spacing: 6) {
                HStack(spacing: 4) {
                    Text(message.role == .user ? "You" : (message.role == .system ? "System" : "Assist"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                // 0. AssistInfoView at the top of user message when a slash/at command or envelope was used
                if message.role == .user {
                    AssistInfoView(envelope: message.envelope, messageText: message.content)
                }

                // 1. Inline collapsible thought inspector/disclosure, outside the main response bubble
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    MetaAssistThinkingUI(
                        thinkingContent: thinking,
                        duration: message.thinkingDuration,
                        isStreaming: isCurrentlyThinking
                    )
                }

                // 2. Main response bubble
                if hasContent || hasActivity || hasAttachments {

                VStack(alignment: .leading, spacing: 8) {
                    // Memory Save Card if save_to_memory or manage_memory executed
                    if let memoryTool = message.activityGroup?.tools.first(where: { $0.toolId == "save_to_memory" || $0.toolId == "manage_memory" }) {
                        AssistMemoryUI(
                            key: memoryTool.purpose.isEmpty ? "Context Stored in Memory" : memoryTool.purpose,
                            value: memoryTool.result.isEmpty ? "Saved to Application Support/SwiftCode/UserMemory.md" : memoryTool.result,
                            category: "Developer Memory"
                        )
                    }

                    // 1. Native Live Activity Feed (Default: MuseCallsNativeToolsUI)
                    if let activity = message.activityGroup, activity.hasContent {
                        MuseCallsNativeToolsUI(activityGroup: activity)
                    }

                    // 1b. SDK-backed tool activity. Shown only under the
                    // SDK run's own transcript message, with that run's
                    // session events. The provider view is chosen by the
                    // run's kind, and each event renders in exactly one
                    // provider view (see the views' provider filter).
                    if message.id == manager.agentSession.sdkMessageId,
                       let sdkSessionId = manager.agentSession.sdkSessionId,
                       let sdkKind = manager.agentSession.sdkSessionKind {
                        let sdkEvents = sdkEventStore.events(for: sdkSessionId)
                        if !sdkEvents.isEmpty {
                            switch sdkKind {
                            case .openRouter:
                                ORToolsUIView(events: sdkEvents)
                            case .hermes:
                                HermesToolsUIView(events: sdkEvents)
                            case .openCode:
                                OCToolsUIView(events: sdkEvents)
                            }
                        }
                    }

                    // 2. Streamed / Completed Assistant Markdown Message
                    if !message.content.isEmpty {
                        let blocks = MarkdownParser.shared.parse(message.content)
                        if blocks.isEmpty {
                            Text(message.content)
                                .font(.body)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        } else {
                            MarkdownBlockListView(blocks: blocks)
                                .textSelection(.enabled)
                        }
                    }

                    // 3. Expandable Activity Details (Files modified diffs, etc.)
                    if let activity = message.activityGroup, !activity.files.isEmpty {
                        if !isMetaMessage {
                            AssistActivityView(activityGroup: activity)
                                .padding(.top, 2)
                        }
                    }

                    if let attachments = message.attachments, !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(attachments) { file in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(file.filename)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                }

                if message.role == .assistant && !isCurrentlyThinking && (!message.content.isEmpty || message.activityGroup?.hasContent == true) {
                    AssistMessageActionBar(message: message)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
    }
}

// MARK: - Assist Message Action Bar (Copy, Retry, Feedback)

private struct AssistMessageActionBar: View {
    let message: AssistMessage
    @ObservedObject private var manager = AssistManager.shared
    @State private var isCopied: Bool = false
    @State private var didThumbsUp: Bool = false
    @State private var isGeneratingFeedback: Bool = false
    @State private var generatedFeedbackURL: URL? = nil
    @State private var feedbackError: String? = nil
    @State private var showFeedbackSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Copy Button
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(message.content, forType: .string)
                    AssistUserActionLog.record(.copied(messageID: message.id))
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Copy message content to clipboard")

                // Retry Button
                Button {
                    retryMessage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Retry")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(manager.isProcessing)
                .help("Regenerate response from preceding user prompt")

                // Thumbs-up Button (positive feedback — no package generated)
                Button {
                    AssistUserActionLog.record(.positiveFeedback(messageID: message.id))
                    AssistFeedbackVoteLog.recordPositive(
                        messageID: message.id,
                        modelId: message.modelId,
                        providerID: message.providerID,
                        conversationID: AssistConversationHistory.shared.activeConversationID
                    )
                    AssistFeedbackService.appendPositiveFeedbackEntry(
                        messageID: message.id,
                        modelId: message.modelId,
                        providerID: message.providerID,
                        conversationID: AssistConversationHistory.shared.activeConversationID,
                        contentPreview: String(message.content.prefix(300)),
                        toolCallCount: message.activityGroup?.tools.count
                    )
                    withAnimation(.easeInOut(duration: 0.2)) {
                        didThumbsUp = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            didThumbsUp = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didThumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Helpful")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(didThumbsUp ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Mark this response as helpful")

                // Feedback Button (thumbs-down: opens the feedback sheet)
                Button {
                    showFeedbackSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Feedback")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isGeneratingFeedback ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingFeedback)
                .help("Generate diagnostic files in Feedback Info for this response")

                // Open in Finder Button (when feedback is ready)
                if let url = generatedFeedbackURL {
                    Button {
                        AssistFeedbackService.shared.openInFinder(url: url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill.badge.gearshape")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Open in Finder")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                    .help("Open the generated Feedback Info package in macOS Finder")
                }
            }

            // Loading bar while generating feedback files
            if isGeneratingFeedback {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Generating diagnostic files in Feedback Info...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: 0.75)
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                }
                .padding(.top, 2)
                .transition(.opacity)
            } else if let error = feedbackError {
                Text("Feedback generation error: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
        .sheet(isPresented: $showFeedbackSheet) {
            AssistFeedbackSheet(message: message) { category, comment, severity in
                submitFeedback(category: category, comment: comment, severity: severity)
            }
        }
    }

    private func retryMessage() {
        guard !manager.isProcessing else { return }
        let retriedID = message.id
        let priorRegenerationCount = message.regenerationCount
        if let index = manager.messages.firstIndex(where: { $0.id == message.id }) {
            let previousMessages = manager.messages[..<index]
            if let lastUserMessage = previousMessages.last(where: { $0.role == .user }) {
                AssistUserActionLog.record(.retryRequested(messageID: retriedID))
                Task {
                    let knownIDs = Set(manager.messages.map { $0.id })
                    await manager.sendMessage(
                        lastUserMessage.content,
                        attachments: lastUserMessage.attachments ?? [],
                        envelope: lastUserMessage.envelope
                    )
                    await MainActor.run {
                        if let newMessage = manager.messages.last(where: { $0.role == .assistant && !knownIDs.contains($0.id) }),
                           let newIndex = manager.messages.firstIndex(where: { $0.id == newMessage.id }) {
                            var updated = manager.messages[newIndex]
                            updated.retryOfMessageID = retriedID
                            updated.regenerationCount = priorRegenerationCount + 1
                            manager.messages[newIndex] = updated
                        }
                    }
                }
            }
        }
    }

    private func submitFeedback(category: String, comment: String, severity: String) {
        AssistUserActionLog.record(.negativeFeedback(messageID: message.id))
        isGeneratingFeedback = true
        feedbackError = nil
        generatedFeedbackURL = nil

        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        AssistFeedbackVoteLog.recordNegative(
            messageID: message.id,
            category: category,
            comment: trimmedComment.isEmpty ? nil : trimmedComment,
            severity: severity
        )
        let reason = "User feedback: \(category) (severity: \(severity))"
        Task {
            do {
                let packageURL = try await AssistFeedbackService.shared.generateFeedbackPackage(
                    for: message,
                    reason: reason,
                    reasonCategory: category,
                    userComment: trimmedComment.isEmpty ? nil : trimmedComment
                )
                await MainActor.run {
                    self.generatedFeedbackURL = packageURL
                    self.isGeneratingFeedback = false
                }
            } catch {
                await MainActor.run {
                    self.feedbackError = error.localizedDescription
                    self.isGeneratingFeedback = false
                }
            }
        }
    }
}

// MARK: - Assist Feedback Sheet (thumbs-down: category + comment + severity)

private struct AssistFeedbackSheet: View {
    let message: AssistMessage
    var onSubmit: (String, String, String) -> Void

    @State private var selectedCategory: String = "Wrong code"
    @State private var comment: String = ""
    @State private var severity: String = "annoying"
    @Environment(\.dismiss) private var dismiss

    static let categories = [
        "Wrong code",
        "Hallucinated API",
        "Incomplete or truncated",
        "Too slow",
        "Tool failure",
        "Refused or apologized",
        "Bad formatting",
        "Other"
    ]
    static let severities = ["mild", "annoying", "blocking"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a problem with this response")
                .font(.headline)

            Text("What went wrong?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack {
                            Text(category)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCategory == category {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedCategory == category
                                ? Color.accentColor.opacity(0.12)
                                : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Severity")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Severity", selection: $severity) {
                ForEach(Self.severities, id: \.self) { level in
                    Text(level.capitalized).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text("Comment (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Add details about what went wrong…", text: $comment)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button("Send Feedback") {
                    onSubmit(selectedCategory, comment, severity)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Assist Header Feedback Button

private struct AssistHeaderFeedbackButton: View {
    @ObservedObject private var feedbackService = AssistFeedbackService.shared
    @State private var generatedURL: URL? = nil

    var body: some View {
        HStack(spacing: 6) {
            Button {
                Task {
                    do {
                        let url = try await feedbackService.generateFeedbackPackage(reason: "User initiated conversation feedback")
                        await MainActor.run {
                            self.generatedURL = url
                        }
                    } catch {
                        print("[AssistHeaderFeedbackButton] Error: \(error.localizedDescription)")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsdown")
                        .font(.body)
                    Text("Feedback")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(feedbackService.isGenerating ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(feedbackService.isGenerating)
            .help("Generate full session diagnostics package in Feedback Info")

            if feedbackService.isGenerating {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else if let url = generatedURL {
                Button {
                    feedbackService.openInFinder(url: url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill.badge.gearshape")
                            .font(.caption2)
                        Text("Open")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Open Feedback Info in Finder")
            }
        }
    }
}

// MARK: - Live Activity Feed

private struct AssistLiveActivityFeed: View {
    let activityGroup: AssistActivityGroup
    @State private var isExpanded: Bool = false
    @State private var expandedToolDetails: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let tools = activityGroup.tools
            let displayTools: [ToolActivityItem] = {
                if isExpanded || tools.count <= 4 {
                    return tools
                } else {
                    let first = tools.prefix(1)
                    let last = tools.suffix(3)
                    var combined: [ToolActivityItem] = Array(first)
                    for item in last {
                        if !combined.contains(where: { $0.id == item.id }) {
                            combined.append(item)
                        }
                    }
                    return combined
                }
            }()

            ForEach(displayTools) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if tool.status == .running {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: 14, height: 14)
                                .tint(.secondary)

                            Text(tool.displayLabel ?? tool.purpose)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } else if tool.status == .completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green.opacity(0.85))
                                .frame(width: 14, height: 14)

                            Text(tool.completedLabel ?? tool.purpose)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if tool.duration > 0 {
                                Text(String(format: "%.1fs", tool.duration))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        } else if tool.status == .failed {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 14, height: 14)

                            Text(tool.purpose)
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.9))
                                .lineLimit(1)
                        } else {
                            Image(systemName: "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, height: 14)

                            Text(tool.purpose)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if !tool.result.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if expandedToolDetails.contains(tool.id) {
                                        expandedToolDetails.remove(tool.id)
                                    } else {
                                        expandedToolDetails.insert(tool.id)
                                    }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(expandedToolDetails.contains(tool.id) ? "Hide Output" : "View Output")
                                        .font(.system(size: 9))
                                    Image(systemName: expandedToolDetails.contains(tool.id) ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if expandedToolDetails.contains(tool.id) && !tool.result.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Output (\(tool.toolId))")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(tool.result, forType: .string)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 8))
                                        Text("Copy")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(tool.result)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                                    .padding(6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .padding(.leading, 20)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                    }
                }
            }

            if tools.count > 4 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                        Text(isExpanded ? "Show fewer activities" : "Show \(tools.count - displayTools.count) more activities")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
                }
                .buttonStyle(.plain)
            }

            // Workers summary if any
            ForEach(activityGroup.workers) { worker in
                HStack(spacing: 6) {
                    if worker.status == .running {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 14, height: 14)
                        Text("\(worker.userFacingTitle)…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    } else if worker.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green.opacity(0.85))
                            .frame(width: 14, height: 14)
                        Text(worker.userFacingTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 14, height: 14)
                        Text("\(worker.userFacingTitle) failed")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                }
            }

            // Builds summary if any
            ForEach(activityGroup.builds) { build in
                HStack(spacing: 6) {
                    if build.status == .running {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 14, height: 14)
                        Text("Building project...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    } else if build.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green.opacity(0.85))
                            .frame(width: 14, height: 14)
                        Text("Build succeeded")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if build.status == .failed {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 14, height: 14)
                        Text("Build failed")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                }
            }

            // Tests summary if any
            ForEach(activityGroup.tests) { test in
                HStack(spacing: 6) {
                    if test.status == .running {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 14, height: 14)
                        Text("Running tests...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    } else if test.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green.opacity(0.85))
                            .frame(width: 14, height: 14)
                        Text("Tests passed (\(test.passedCount))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if test.status == .failed {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 14, height: 14)
                        Text("Tests failed (\(test.failedCount) failures)")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 2)
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

// MARK: - Execution Mode Sheet

struct ExecutionModeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("com.swiftcode.assist.mode") private var isAgentMode = false
    @AppStorage("com.swiftcode.assist.executionMode") private var executionModeRaw: String = ExecutionMode.autopilot.rawValue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Execution Mode")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .padding(.bottom, 8)

            VStack(spacing: 4) {
                Button {
                    isAgentMode = false
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chat Mode")
                                .font(.subheadline.weight(.medium))
                            Text("Chat with Assist with no tools.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !isAgentMode {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    isAgentMode = true
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book.and.wrench")
                            .font(.caption)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent Mode")
                                .font(.subheadline.weight(.medium))
                            Text("Autonomous agent that can build, test, and repair")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isAgentMode {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            if isAgentMode {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Mode")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    ForEach(ExecutionMode.allCases, id: \.self) { mode in
                        Button {
                            executionModeRaw = mode.rawValue
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: mode == .plan ? "list.bullet.rectangle" : "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.rawValue)
                                        .font(.subheadline.weight(.medium))
                                    Text(mode == .plan ? "Collaborative — asks user for key decisions" : "Fully autonomous — no user questions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if executionModeRaw == mode.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom)
        .frame(width: 360)
    }
}

// MARK: - SDK Model Provider List

/// Lists the models fetched live from the active SDK provider
/// (OpenCode, OpenRouter or Hermes). Nothing is hardcoded: the list
/// is whatever the provider reports, and the user's pick is stored
/// in `selectedAssistModelID`.
struct SDKModelProviderList: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var openCodeModels: [OpenCodeModel] = []
    @State private var openRouterModels: [OpenRouterModel] = []
    @State private var hermesModels: [HermesProvider.HermesDiscoveredModel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var provider: AssistModelProvider {
        AssistModelProvider(rawValue: AssistProviderSelection.persistedProvider.rawValue) ?? .openRouter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(provider.rawValue) Models")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(rows, id: \.id) { row in
                        Button {
                            settings.selectedAssistModelID = row.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(row.name)
                                    .font(.subheadline)
                                Spacer()
                                if settings.selectedAssistModelID == row.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay {
                    if rows.isEmpty {
                        Text("No models returned by \(provider.rawValue).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 420, height: 420)
        .task { await load() }
    }

    private var rows: [(id: String, name: String)] {
        switch provider {
        case .openCode:
            return openCodeModels.map { ($0.storedID, $0.displayName) }
        case .hermes:
            return hermesModels.map { ($0.storedID, $0.displayName) }
        default:
            return openRouterModels.map { ($0.id, $0.name) }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch provider {
            case .openCode:
                openCodeModels = try await OpenCodeClient.shared.fetchModels()
            case .hermes:
                hermesModels = try await HermesProvider.fetchModels()
            case .openRouter:
                openRouterModels = try await OpenRouterAssistProvider.fetchModels()
            default:
                errorMessage = "Model selection is available for OpenCode, OpenRouter and Hermes."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Diagnostics Sheet

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
                Label("Diagnostics", systemImage: "terminal")
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
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Active Runtime Metrics") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Execution Mode:")
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
                                TextField("Filter Logs", text: $searchText)
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

/// Expandable inline diagnostic for errors and warnings. The collapsed row
/// shows a one-line summary; expanding reveals the full message plus
/// diagnostic context (when it was recorded, which request phase was
/// active) and a copy button. Warnings render amber, errors red.
private struct AssistInlineDiagnostic: View {
    enum Severity {
        case error
        case warning
    }

    let message: String
    let severity: Severity
    let date: Date?
    let phase: AssistRequestPhase?

    @State private var isExpanded = false

    private var tint: Color {
        severity == .error ? .red : .orange
    }

    private var icon: String {
        severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var summary: String {
        let firstLine = message.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? (severity == .error ? "An error occurred." : "Warning.") : firstLine
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    if let date {
                        Label(date.formatted(date: .omitted, time: .standard), systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let phase {
                        Label(phase.statusText, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
        }
        .tint(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

private struct AssistInlineError: View {
    let message: String

    var body: some View {
        AssistInlineDiagnostic(message: message, severity: .error, date: nil, phase: nil)
    }
}

// MARK: - Custom Model Picker Popover (Section 2 "Available Models" Card Integration)

struct AssistCustomModelPickerPopover: View {
    let selectedModelID: String
    let onSelect: (AssistAvailableModel) -> Void
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var discoveryService = AssistModelDiscoveryService.shared

    private func modelColor(_ model: AssistAvailableModel) -> Color {
        if model.isCurrentlyRateLimited { return .orange }
        switch model.status {
        case .available:
            return model.supportsAgenticUse ? .green : .purple
        case .authRequired:
            return .yellow
        case .providerUnavailable:
            return .red
        case .unsupportedAgentic:
            return .purple
        case .rateLimited:
            return .orange
        case .configured:
            return .blue
        case .unavailable:
            return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Label("Available Models", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.purple)

                if discoveryService.isDiscovering {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }

                Spacer()

                Button {
                    Task {
                        await discoveryService.discoverAllModels(forceRefresh: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh Available Models")
                .disabled(discoveryService.isDiscovering)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            // Models List (Grouped by Provider exactly as in Available Models card)
            let groups = discoveryService.modelsByProvider
            if groups.isEmpty {
                VStack(spacing: 8) {
                    if discoveryService.isDiscovering {
                        ProgressView().scaleEffect(0.8)
                        Text("Discovering models across configured providers...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No models discovered.\nConfigure API keys or custom endpoints in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.providerName) { group in
                            let filteredModels = group.models.filter { model in
                                if searchText.isEmpty { return true }
                                let query = searchText.lowercased()
                                return model.displayName.lowercased().contains(query) ||
                                       model.modelIdentifier.lowercased().contains(query) ||
                                       model.providerName.lowercased().contains(query)
                            }

                            if !filteredModels.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Provider Header
                                    HStack {
                                        Text(group.providerName)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                        Spacer()
                                        Text("\(filteredModels.count)")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.top, 4)

                                    // Models in Provider
                                    ForEach(filteredModels) { model in
                                        AssistModelPickerRow(
                                            model: model,
                                            isSelected: selectedModelID == model.modelIdentifier,
                                            statusColor: modelColor(model),
                                            onSelect: {
                                                onSelect(model)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 320, height: 380)
        .task {
            if discoveryService.discoveredModels.isEmpty {
                await discoveryService.discoverAllModels()
            }
        }
    }
}

private struct AssistModelPickerRow: View {
    let model: AssistAvailableModel
    let isSelected: Bool
    let statusColor: Color
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(.primary)

                        if model.supportsToolCalling {
                            Text("Tools")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .cornerRadius(3)
                        }

                        if model.supportsVision {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                        if model.supportsSubagents {
                            Text("Subagents")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundStyle(.indigo)
                                .cornerRadius(3)
                        }
                    }

                    Text(model.modelIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

