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
    @State private var showExecutionModeSheet = false
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
    @State private var isThinkingDropdownExpanded: Bool = false

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
    @State private var showAssistSettings = false

    // Create New App Wizard Sheet
    @State private var showCreateNewAppSheet = false


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

                Button {
                    showExecutionModeSheet = true
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

                // Agent Notes Trigger
                Button {
                    showAgentNotesSheet = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.body)
                        .foregroundStyle(AgentNotesManager.shared.currentNotesMarkdown.isEmpty ? .secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Inspect Execution Plan & Phase Matrix")

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

                // Assist Settings Trigger
                Button {
                    withAnimation(.spring()) {
                        showAssistSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(showAssistSettings ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Assist Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial)

            Divider()

            if showAssistSettings {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assist Configuration")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $enableCodeReview) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Autonomous Code Review Stage")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text("Verify all completed implementations using an independent AI reviewer stage before completing the task.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(12)
                .background(Color.secondary.opacity(0.04))
                .transition(.move(edge: .top).combined(with: .opacity))

                Divider()
            }

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

                            // Native Conversational Chat Bubbles
                            ForEach(filteredMessages) { message in
                                if let composio = message.composioExecution {
                                    AgentUseComposio(metadata: composio)
                                } else if let mcp = message.mcpExecution {
                                    AgentUseMCP(metadata: mcp)
                                } else {
                                    AssistChatBubble(message: message)
                                }
                            }

                            if let error = manager.lastError {
                                AssistInlineError(message: error)
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

                if !manager.logger.logs.isEmpty {
                    MiniLogFeed(logger: manager.logger)
                }

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
        .sheet(isPresented: $showExecutionModeSheet) {
            ExecutionModeSheet()
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            DiagnosticsSheet(manager: manager)
        }
        .sheet(isPresented: $showAgentNotesSheet) {
            AgentNotesInspectorView()
        }
        .sheet(isPresented: $showCreateNewAppSheet) {
            CreateNewAppWizardView()
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
            return "Thinking..."
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

    private var thinkingIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(.secondary)

                let displayText: String = {
                    if manager.isThinking {
                        return "Thinking (\(manager.thinkingDurationSeconds)s)..."
                    }
                    if !manager.currentActivityStatus.isEmpty && manager.currentActivityStatus != "Idle" {
                        return manager.currentActivityStatus
                    }
                    let sessionDesc = statusUserDescription(for: manager.agentSession.state.status)
                    if sessionDesc != "Idle" {
                        return sessionDesc
                    }
                    return "Thinking..."
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

                if !manager.activeThinkingText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isThinkingDropdownExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 11))
                            Text("Thoughts")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: isThinkingDropdownExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isThinkingDropdownExpanded ? "Collapse Thinking Progress" : "Show Thinking Progress")
                }
            }

            if isThinkingDropdownExpanded && !manager.activeThinkingText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Live Thoughts (\(manager.thinkingDurationSeconds)s)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        Text(manager.activeThinkingText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    .cornerRadius(6)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var processingIndicator: some View {
        if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
            if isAgentMode {
                if manager.messages.last?.role != .assistant {
                    thinkingIndicator
                }
            } else {
                chatTypingIndicator
            }
        }
    }

    private var chatTypingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
                .tint(.secondary)

            Text("Assist is typing")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                    Text(item.content)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(3)
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
                let event = NSApplication.shared.currentEvent
                let models = loadDynamicModels()
                let activeID = currentActiveModelID()
                ModelPopupMenuHelper.showMenu(event: event, models: models, activeModelID: activeID) { option in
                    selectModel(option)
                }
            } label: {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Choose Model")

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
                let placeholder = isBusy ? "Queue next message..." : "What should I build next?"
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
                        attachedFiles = []
                        inputText = ""
                        manager.interruptActiveSessionAndSend(content: text, attachments: files)
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

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !isProcessingFiles else { return }

        let filesToSend = attachedFiles
        attachedFiles = []
        inputText = ""

        if manager.isProcessing || bridgeManager.streamStatus == "Streaming" {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                manager.enqueueMessage(text, attachments: filesToSend)
            }
            return
        }

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

        Task {
            await ModelSessionManager.shared.switchModel(to: option.modelID)
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
        case .user: return Color.primary.opacity(0.06)
        case .assistant: return Color.secondary.opacity(0.06)
        case .system: return Color.secondary.opacity(0.08)
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 4) {
                Text(message.role == .user ? "You" : (message.role == .system ? "System" : "Assist"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                // 1. Native Live Activity Feed (Subtle, Compact, Streaming)
                if let activity = message.activityGroup, activity.hasContent {
                    AssistLiveActivityFeed(activityGroup: activity)
                }

                // 2. Thoughts Dropdown for message
                if let thoughts = message.thinkingContent, !thoughts.isEmpty {
                    ThinkingDisclosureView(thoughts: thoughts, duration: message.thinkingDuration)
                }

                // 3. Fallback Temporary Thinking Indicator (ONLY when empty assistant message with no activities yet)
                if message.role == .assistant && message.content.isEmpty && (message.activityGroup == nil || !message.activityGroup!.hasContent) {
                    AssistTemporaryThinkingView()
                }

                // 4. Streamed / Completed Assistant Markdown Message
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

                // 5. Expandable Activity Details (Files modified diffs, etc.)
                if let activity = message.activityGroup, !activity.files.isEmpty {
                    AssistActivityView(activityGroup: activity)
                        .padding(.top, 2)
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
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Live Activity Feed

private struct AssistLiveActivityFeed: View {
    let activityGroup: AssistActivityGroup
    @State private var isExpanded: Bool = false

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

// MARK: - Temporary Thinking View

private struct AssistTemporaryThinkingView: View {
    @ObservedObject private var manager = AssistManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 14, height: 14)
                .tint(.secondary)

            let label: String = {
                if manager.isThinking {
                    return "Thinking (\(manager.thinkingDurationSeconds)s)..."
                }
                if !manager.currentActivityStatus.isEmpty && manager.currentActivityStatus != "Idle" {
                    return manager.currentActivityStatus
                }
                return "Thinking..."
            }()

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thinking Disclosure View

private struct ThinkingDisclosureView: View {
    let thoughts: String
    let duration: TimeInterval?
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    let durationStr = duration.map { " (\(Int($0))s)" } ?? ""
                    Text("Thought\(durationStr)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    Text(thoughts)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
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
                            Text("Read-only conversational assistant")
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
                        Image(systemName: "cpu")
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
                    Text("Agent Execution Mode")
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

private struct AssistInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

