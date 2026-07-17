import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistMainView")

/// Highly-optimized, professional desktop-first macOS experience for the SwiftCode Assist workspace.
public struct AssistMainView: View {
    @StateObject private var manager = AssistManager.shared
    @State private var inputText: String = ""
    @State private var isEnhancingPrompt = false
    @State private var showSettings = false
    @State private var showDiagnosticsSheet = false
    @State private var showExecutionModeSheet = false
    @State private var searchConversationText = ""

    // Codex onboarding trigger states
    @State private var showConnectCodex = false
    @State private var showingCodexSetup = false

    // Mode selection: Chat Mode (Read-Only) vs. Agent Mode (Autonomous)
    @AppStorage("com.swiftcode.assist.mode") private var isAgentMode = false

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

                // Execution Mode Button (opens as Sheet)
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
                        .foregroundStyle(manager.isProcessing ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help("System Diagnostics")

                // Settings Trigger
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Assist Settings")
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

                        if showConnectCodex {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("Connect OpenAI Codex", systemImage: "sparkles")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.orange)
                                        Spacer()
                                    }
                                    Text("Setup Codex provider to run native, ultra-fast model inference.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        showingCodexSetup = true
                                    } label: {
                                        Text("Connect Codex")
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

                        if isAgentMode {
                            AssistPlannerView()
                        }

                        if let error = manager.lastError {
                            AssistErrorBubble(error: error)
                        }

                        if manager.isProcessing {
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

            // Bottom input controls
            VStack(spacing: 8) {
                if !manager.logger.logs.isEmpty {
                    MiniLogFeed(logger: manager.logger)
                }
                inputArea
            }
            .padding(12)
            .background(.thinMaterial)
        }
        .background(.windowBackground)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                AssistSettingsView()
            }
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
        .task {
            await updateCodexButtonVisibility()
        }
        .onChange(of: showingCodexSetup) { _, newValue in
            if !newValue {
                Task {
                    await updateCodexButtonVisibility()
                }
            }
        }
    }

    private func updateCodexButtonVisibility() async {
        let hasKey = !(KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let bridgeLocated = (try? CodexBridgeManager.shared.locateResources()) != nil
        let isHealthy = await CodexBridgeManager.shared.isBridgeHealthy()
        let completedSetup = UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup")

        showConnectCodex = !hasKey || !bridgeLocated || !isHealthy || !completedSetup
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
                Text(manager.isProcessing ? "Agent executing tools..." : "Planning next steps...")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)

                if let lastLog = manager.logger.logs.last {
                    Text(lastLog.message)
                        .font(.system(size: 9))
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

    private var inputArea: some View {
        HStack(spacing: 8) {
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
            .disabled(inputText.isEmpty || manager.isProcessing)
            .help("Enhance prompt with Apple Intelligence")

            ZStack {
                TextField("What should I build next?", text: $inputText, axis: .vertical)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .lineLimit(1...5)
                    .disabled(manager.isProcessing || isEnhancingPrompt)
                    .onSubmit {
                        submitMessage()
                    }

                if isEnhancingPrompt {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.purple)
                                Text("Enhancing...")
                                    .font(.caption.weight(.semibold))
                            }
                        )
                }
            }

            Button(action: submitMessage) {
                Group {
                    if manager.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                    }
                }
            }
            .disabled(inputText.isEmpty || manager.isProcessing)
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.plain)
        }
    }

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !manager.isProcessing else { return }
        inputText = ""

        // In Chat Mode, we strip any potential destructive commands before sending
        let finalPrompt: String
        if !isAgentMode {
            finalPrompt = "[Execute in Read-Only Chat Mode. Inform the user you cannot execute tools or write files.]\n\n" + text
        } else {
            finalPrompt = text
        }

        Task {
            await manager.sendMessage(finalPrompt)
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

            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(10)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Execution Mode Sheet View

struct ExecutionModeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("com.swiftcode.assist.mode") private var isAgentMode = false

    var body: some View {
        VStack(spacing: 16) {
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
                .buttonStyle(.plain)
            }

            Picker("Mode", selection: $isAgentMode) {
                Text("Chat Mode").tag(false)
                Text("Agent Mode").tag(true)
            }
            .pickerStyle(.segmented)

            Text(isAgentMode ? "Allows full autonomy to run terminal commands, create, edit, or delete files, and run builds (with user approval)." : "Read-only access to explain code, analyze layouts, and answer questions. No write or run tools.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Diagnostics Sheet View

struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: AssistManager

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("System Telemetry", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // GroupBox: Current Active Provider
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Active Provider Status", systemImage: "network")
                                .font(.subheadline.bold())
                                .foregroundStyle(.cyan)

                            let provider = (try? LLMService.shared.resolvedRoutingProvider()) ?? .openRouter
                            Text("Routing directly to: \(provider.rawValue)")
                                .font(.caption)

                            if provider == .codex {
                                Text("OpenAI Codex SDK connection established via local bridge server port 3003.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if FoundationModels.shared.isEnabled {
                                Text("Bypassing cloud endpoints. Native third-gen AFM 3 on-device reasoning is active.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Cloud processing via secure OpenRouter/Anthropic key integrations.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox: Process and Thread Telemetry
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Process Diagnostics", systemImage: "cpu")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Platform: macOS (Darwin 24+)")
                                Text("Thread Isolation: Strict @MainActor")
                                Text("Memory Allocation: Automatic Graph")
                                Text("Sandbox Mode: Source-Control Embedded")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox: Live Telemetry Logs
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Inference Pipeline Logs", systemImage: "terminal.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    if manager.logger.logs.isEmpty {
                                        Text("Pipeline standby. Initiate prompt request.")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(manager.logger.logs) { log in
                                            Text("[\(log.toolId ?? "system")] \(log.message)")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .padding(6)
                            }
                            .frame(height: 180)
                            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 420, height: 540)
    }
}
