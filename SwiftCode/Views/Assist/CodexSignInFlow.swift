import SwiftUI
import AppKit

@MainActor
public struct CodexSignInFlow: View {
    @Environment(\.dismiss) private var dismiss

    // Setup state
    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var isRunningSequence: Bool = false
    @State private var currentStage: CodexStartupStage? = nil
    @State private var stageDescription: String = ""
    @State private var sequenceError: String? = nil
    @State private var sequenceSuccess: Bool = false

    // Testing state
    @State private var isTesting: Bool = false
    @State private var testPrompt: String = "Respond with \"Codex connection successful.\""
    @State private var testResponse: String = ""
    @State private var testDuration: TimeInterval = 0
    @State private var testStatus: String = "Standby"
    @State private var testError: String? = nil
    @State private var testWarnings: [String] = []

    // Reference to managers
    @Bindable private var bridgeManager = CodexBridgeManager.shared

    public init() {}

    private var hasStoredKey: Bool {
        !(KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI Codex Onboarding")
                        .font(.title2.bold())
                    Text("Complete setup to register Codex as a native assistant provider.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Stage Status Banner
                    if isRunningSequence, let stage = currentStage {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .padding(.trailing, 4)
                                    Text("Active Stage: \(stage.rawValue)")
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                }
                                Text(stageDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    if let error = sequenceError {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "xmark.octagon.fill")
                                        .foregroundColor(.red)
                                    Text("Setup Failed")
                                        .font(.headline)
                                        .foregroundStyle(.red)
                                }
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Divider()

                                Text("Recovery Suggestions:")
                                    .font(.caption.bold())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• Verify that your OpenAI API Key has access to the gpt-4o and gpt-5-codex models.")
                                    Text("• Ensure Node.js runtime is installed on your Mac by running 'node -v' in your terminal.")
                                    Text("• Check your network connections and try launching the bridge again.")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Section 1: OpenAI Authentication
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("OpenAI Authentication", systemImage: "key.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                                if hasStoredKey {
                                    Text("Key Stored in Keychain")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                }
                            }

                            HStack {
                                Group {
                                    if showKey {
                                        TextField("Enter OpenAI API Key (sk-...)", text: $apiKey)
                                    } else {
                                        SecureField("Enter OpenAI API Key (sk-...)", text: $apiKey)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .fontDesign(.monospaced)

                                Button {
                                    showKey.toggle()
                                } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                                .help(showKey ? "Hide API Key" : "Show API Key")

                                Button("Paste") {
                                    if let string = NSPasteboard.general.string(forType: .string) {
                                        apiKey = string.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }
                                .buttonStyle(.bordered)

                                Button("Clear") {
                                    apiKey = ""
                                }
                                .buttonStyle(.bordered)
                                .disabled(apiKey.isEmpty)
                            }

                            HStack {
                                Button("Save Key") {
                                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        KeychainService.shared.set(trimmed, forKey: KeychainService.codexUserAPIKey)
                                        KeychainService.shared.set(trimmed, forKey: "openai_api_key")
                                        apiKey = ""
                                        bridgeManager.appendLog("API Key manually saved to Keychain.")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Validate Key") {
                                    Task {
                                        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let success = await bridgeManager.validateAPIKey(trimmed)
                                        if success {
                                            bridgeManager.appendLog("Key manually validated successfully.")
                                        } else {
                                            bridgeManager.appendLog("Key manual validation failed.")
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 2: Bridge Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Bridge Status", systemImage: "network")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(statusColor(bridgeManager.bridgeStatus))
                                        .frame(width: 8, height: 8)
                                    Text(bridgeManager.bridgeStatus.rawValue)
                                        .font(.caption.bold())
                                        .foregroundColor(statusColor(bridgeManager.bridgeStatus))
                                }
                            }

                            HStack {
                                Text("Local Port: \(3003)")
                                Spacer()
                                Text("PID: \(bridgeManager.bridgePID.map { String($0) } ?? "N/A")")
                                Spacer()
                                if let launchTime = bridgeManager.launchTime {
                                    Text("Uptime: \(String(format: "%.1f", Date().timeIntervalSince(launchTime)))s")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 3: Connection Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Connection Pipeline Status", systemImage: "bolt.horizontal.fill")
                                .font(.headline)
                                .foregroundColor(.green)

                            VStack(spacing: 8) {
                                statusRow(title: "API Key Configured", value: hasStoredKey ? "Ready" : "Missing", isOk: hasStoredKey)
                                statusRow(title: "Bridge Server Connected", value: bridgeManager.bridgeStatus == .running ? "Online" : "Offline", isOk: bridgeManager.bridgeStatus == .running)
                                statusRow(title: "Codex SDK Initialized", value: bridgeManager.bridgeStatus == .running ? "Loaded" : "Not Loaded", isOk: bridgeManager.bridgeStatus == .running)
                                statusRow(title: "Inference Provider", value: bridgeManager.bridgeStatus == .running ? "Active" : "Standby", isOk: bridgeManager.bridgeStatus == .running)
                                statusRow(title: "Stream Session Integrity", value: bridgeManager.streamStatus == "Streaming" ? "Active Stream" : "Standby", isOk: true)
                                statusRow(title: "Current Selected Model", value: bridgeManager.currentModel, isOk: true)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 4: Diagnostics Console
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Diagnostics Console Logs", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                                Button("Clear Logs") {
                                    bridgeManager.liveLogs.removeAll()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if bridgeManager.liveLogs.isEmpty {
                                            Text("Standby. Start the onboarding sequence to populate logs.")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(bridgeManager.liveLogs, id: \.self) { log in
                                                Text(log)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                    .padding(8)
                                }
                                .frame(height: 160)
                                .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                .onChange(of: bridgeManager.liveLogs.count) { _, _ in
                                    if let last = bridgeManager.liveLogs.last {
                                        proxy.scrollTo(last, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 5: Test Codex
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Verification & Connection Testing", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundColor(.cyan)

                            Text("Perform a real completion request to verify connection integrity, stream latency, and response token parsing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Test Codex") {
                                    runConnectionTest()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                .disabled(isTesting || bridgeManager.bridgeStatus != .running)

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text("Test Status: \(testStatus)")
                                    if testDuration > 0 {
                                        Text("Response Latency: \(String(format: "%.2f", testDuration))s")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if !testResponse.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Streamed Response:")
                                        .font(.caption.bold())
                                    Text(testResponse)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            if let error = testError {
                                Text("Test Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding()
            }

            Divider()

            // Footer / Control Action bar
            HStack {
                Button("Close Setup") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(isRunningSequence)

                Spacer()

                Button {
                    Task {
                        await startSetupSequence()
                    }
                } label: {
                    HStack {
                        if isRunningSequence {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isRunningSequence ? "Executing Onboarding..." : "Connect Codex")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isRunningSequence)
            }
            .padding()
            .background(.thinMaterial)
        }
        .frame(width: 580, height: 720)
    }

    private func startSetupSequence() async {
        isRunningSequence = true
        sequenceError = nil
        sequenceSuccess = false

        let inputKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = inputKey.isEmpty ? (KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "") : inputKey

        guard !resolvedKey.isEmpty else {
            sequenceError = "API Key cannot be empty. Please enter an OpenAI API Key."
            isRunningSequence = false
            return
        }

        do {
            try await bridgeManager.startStartupSequence(apiKey: resolvedKey) { stage, description in
                self.currentStage = stage
                self.stageDescription = description
                self.bridgeManager.appendLog("STAGE [\(stage.rawValue)]: \(description)")
            }
            sequenceSuccess = true
            UserDefaults.standard.set(true, forKey: "com.swiftcode.codex.completedSetup")

            // Auto select Codex as preferred provider
            UserDefaults.standard.set("Codex", forKey: "assist.selectedProvider")

            // Dismiss after slight delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            sequenceError = error.localizedDescription
            bridgeManager.appendLog("Onboarding failed at stage '\(currentStage?.rawValue ?? "Unknown")' with error: \(error.localizedDescription)")
        }

        isRunningSequence = false
    }

    private func runConnectionTest() {
        isTesting = true
        testResponse = ""
        testError = nil
        testStatus = "Connecting..."
        testDuration = 0
        let startTime = Date()

        Task {
            do {
                try await bridgeManager.streamPrompt(testPrompt) { token in
                    testResponse += token
                    testStatus = "Streaming..."
                }
                testDuration = Date().timeIntervalSince(startTime)
                testStatus = "Success"
            } catch {
                testError = error.localizedDescription
                testStatus = "Failed"
            }
            isTesting = false
        }
    }

    private func statusColor(_ status: CodexBridgeStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting, .reconnecting: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isOk ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(value)
                    .font(.caption.monospaced())
            }
        }
    }
}
