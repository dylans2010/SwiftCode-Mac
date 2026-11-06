import SwiftUI
import AppKit

public struct HandshakeDiagnostics: Identifiable, Sendable {
    public var id: UUID = UUID()
    public let stage: String
    public let failureReason: String
    public let providerResponse: String?
    public let recommendedResolution: String
}

@MainActor
public struct CodexSignInFlow: View {
    @Environment(\.dismiss) private var dismiss

    // Binding to CodexBridgeManager
    @Bindable private var bridgeManager = CodexBridgeManager.shared

    // Authentication Key inputs
    @State private var apiKey: String = ""
    @State private var showKey: Bool = false

    // Device Auth state
    @State private var deviceUrl: String = ""
    @State private var deviceCode: String = ""
    @State private var showDeviceCodeSheet: Bool = false

    // Verification Connection test states
    @State private var isTesting: Bool = false
    @State private var testResponse: String = ""
    @State private var testDuration: TimeInterval = 0
    @State private var testStatus: String = "Standby"
    @State private var testError: String? = nil
    @State private var handshakeDiagnostics: HandshakeDiagnostics? = nil

    public init() {}

    private var hasStoredKey: Bool {
        !(KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isAuthenticatedWithAPIKey: Bool {
        hasStoredKey
    }

    private var isAuthenticatedWithChatGPT: Bool {
        // Authenticated but does not have a saved API Key in Keychain
        bridgeManager.isAuthenticated && !hasStoredKey
    }

    private var isAnyAuthenticated: Bool {
        isAuthenticatedWithAPIKey || isAuthenticatedWithChatGPT
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
                    Text("OpenAI Codex Integration")
                        .font(.title2.bold())
                    Text("Configure, install, and authenticate the official Codex CLI backend.")
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
                    // Installer State Alert
                    if bridgeManager.isInstalling {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .padding(.trailing, 4)
                                    Text("Installing Official OpenAI Codex CLI...")
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                }
                                Text(bridgeManager.installProgress)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Section 1: Live CLI Status Panel
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Live CLI Status", systemImage: "info.circle.fill")
                                .font(.headline)
                                .foregroundColor(.orange)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible(), alignment: .trailing)], spacing: 8) {
                                statusRow(title: "CLI Installation", value: bridgeManager.cliLocation == "Not Detected" ? "Missing" : "Installed", isOk: bridgeManager.cliLocation != "Not Detected")
                                statusRow(title: "CLI Version", value: bridgeManager.cliVersion, isOk: bridgeManager.cliVersion != "N/A" && bridgeManager.cliVersion != "Unknown")
                                statusRow(title: "Location", value: bridgeManager.cliLocation, isOk: true)
                                statusRow(title: "Authentication", value: bridgeManager.isAuthenticated ? "Authenticated" : "Required", isOk: bridgeManager.isAuthenticated)
                                statusRow(title: "Auth Mode", value: bridgeManager.authModeString, isOk: true)
                                statusRow(title: "Connection Status", value: bridgeManager.bridgeStatus.rawValue, isOk: bridgeManager.bridgeStatus == .running)
                                statusRow(title: "Active Stream", value: bridgeManager.streamStatus, isOk: true)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 2: Install CLI (if not detected or management requested)
                    if bridgeManager.cliLocation == "Not Detected" {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Managed Installer", systemImage: "square.and.arrow.down.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)

                                Text("The official stand-alone installer will download, configure, and install OpenAI's Codex CLI onto your Mac securely.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    Task {
                                        try? await bridgeManager.installCLI()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "icloud.and.arrow.down")
                                        Text("Install CLI")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(bridgeManager.isInstalling)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Section 3: ChatGPT Authentication & State Changes
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("ChatGPT Authentication", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.headline)
                                .foregroundColor(.green)

                            if isAnyAuthenticated {
                                Text("You are already authenticated!")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                    .padding(.vertical, 4)

                                Text(isAuthenticatedWithAPIKey ? "Authenticated using OpenAI API Key stored securely in Keychain." : "Authenticated using official ChatGPT OAuth session.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    Task {
                                        if isAuthenticatedWithAPIKey {
                                            // Sign out API Key
                                            KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)
                                            bridgeManager.appendLog("API Key removed from Keychain.")
                                        } else {
                                            // Sign out ChatGPT
                                            await bridgeManager.logout()
                                            bridgeManager.appendLog("ChatGPT OAuth session cleared.")
                                        }
                                        await bridgeManager.auditEnvironment()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "power")
                                        Text("Sign Out")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            } else {
                                Text("Connect using your official ChatGPT account. No API Keys are required. SwiftCode will launch the browser validation and the CLI will safely persist your credentials in auth.json.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    Button {
                                        Task {
                                            if hasStoredKey {
                                                let proceed = await confirmChatGPTTransition()
                                                if !proceed { return }
                                                KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)
                                                await bridgeManager.auditEnvironment()
                                            }
                                            try? await bridgeManager.loginWithChatGPT()
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "safari")
                                            Text("Continue with ChatGPT")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .disabled(bridgeManager.cliLocation == "Not Detected" || bridgeManager.isConnecting)

                                    Button {
                                        Task {
                                            if hasStoredKey {
                                                let proceed = await confirmChatGPTTransition()
                                                if !proceed { return }
                                                KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)
                                                await bridgeManager.auditEnvironment()
                                            }
                                            try? await bridgeManager.loginWithDeviceCode { url, code in
                                                self.deviceUrl = url
                                                self.deviceCode = code
                                                self.showDeviceCodeSheet = true
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "tv")
                                            Text("Device Code Login")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(bridgeManager.cliLocation == "Not Detected" || bridgeManager.isConnecting)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 4: Alternative API Key Integration (Hidden if authenticated)
                    if !isAnyAuthenticated {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("OpenAI API Key Integration (Alternative)", systemImage: "key.fill")
                                    .font(.headline)
                                    .foregroundColor(.cyan)

                                HStack {
                                    Group {
                                        if showKey {
                                            TextField("sk-...", text: $apiKey)
                                        } else {
                                            SecureField("sk-...", text: $apiKey)
                                        }
                                    }
                                    .textFieldStyle(.roundedBorder)
                                    .fontDesign(.monospaced)

                                    Button {
                                        showKey.toggle()
                                    } label: {
                                        Image(systemName: showKey ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.plain)

                                    Button("Paste") {
                                        if let string = NSPasteboard.general.string(forType: .string) {
                                            apiKey = string.trimmingCharacters(in: .whitespacesAndNewlines)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack {
                                    Button("Save and Validate API Key") {
                                        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        Task {
                                            let valid = await bridgeManager.validateAPIKey(trimmed)
                                            if valid {
                                                KeychainService.shared.set(trimmed, forKey: KeychainService.codexUserAPIKey)
                                                bridgeManager.appendLog("API Key verified and stored in KeyChain.")
                                                apiKey = ""
                                                await bridgeManager.auditEnvironment()
                                            } else {
                                                bridgeManager.appendLog("API Key validation failed.")
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.cyan)
                                    .disabled(apiKey.isEmpty || bridgeManager.cliLocation == "Not Detected")

                                    if hasStoredKey {
                                        Button("Remove Saved Key") {
                                            KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)
                                            bridgeManager.appendLog("API Key removed from Keychain.")
                                            Task {
                                                await bridgeManager.auditEnvironment()
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Section 5: Diagnostics Console logs
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Diagnostics Logs", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                                Button("Clear") {
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
                                            Text("Awaiting logs...")
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
                                .frame(height: 140)
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

                    // Section 6: Testing & HANDSHAKE
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Verification and Handshake Test", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundColor(.yellow)

                            Text("Perform a live integration check. This executes a fast completion request to the CLI backend to check latency, communication stream, and tool registry.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Test Connection") {
                                    runConnectionTest()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.yellow)
                                .disabled(isTesting || !bridgeManager.isAuthenticated)

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text("Handshake: \(testStatus)")
                                    if testDuration > 0 {
                                        Text("Latency: \(String(format: "%.2f", testDuration))s")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if !testResponse.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Response payload:")
                                        .font(.caption.bold())
                                    Text(testResponse)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            if let diags = handshakeDiagnostics {
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "exclamationmark.octagon.fill")
                                                .foregroundColor(.red)
                                            Text("Detailed Handshake Diagnostic Report")
                                                .font(.headline)
                                                .foregroundColor(.red)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Connection Stage: ").bold() + Text(diags.stage)
                                            Text("Failure Reason: ").bold() + Text(diags.failureReason).foregroundStyle(.red)
                                            if let resp = diags.providerResponse {
                                                Text("Provider Response: ").bold() + Text(resp).fontDesign(.monospaced)
                                            }
                                            Divider()
                                            Text("Recommended Resolution: ").bold() + Text(diags.recommendedResolution).foregroundColor(.green)
                                        }
                                        .font(.caption)
                                    }
                                    .padding(8)
                                }
                                .groupBoxStyle(ModernGroupBoxStyle())
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Close Setup") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task {
                        try? await bridgeManager.startStartupSequence(apiKey: "") { _, _ in }
                        dismiss()
                    }
                } label: {
                    Text("Auto Connect Codex")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(bridgeManager.cliLocation == "Not Detected" || !bridgeManager.isAuthenticated)
            }
            .padding()
            .background(.thinMaterial)
        }
        .frame(width: 580, height: 720)
        .sheet(isPresented: $showDeviceCodeSheet) {
            VStack(spacing: 16) {
                Text("Device Authentication")
                    .font(.headline)
                Text("Open the OpenAI link and enter the following verification code:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(deviceCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .padding()
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Button("Open Link in Browser") {
                    if let url = URL(string: deviceUrl) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    showDeviceCodeSheet = false
                    Task {
                        await bridgeManager.auditEnvironment()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 320, height: 260)
        }
        .task {
            await bridgeManager.auditEnvironment()
        }
    }

    private func confirmChatGPTTransition() async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Switch to ChatGPT Authentication?"
        alert.informativeText = "Continuing with ChatGPT authentication will remove the currently saved API key authentication."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue with ChatGPT")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    private func runConnectionTest() {
        isTesting = true
        testResponse = ""
        testStatus = "Executing Handshake..."
        testDuration = 0
        testError = nil
        handshakeDiagnostics = nil
        let startTime = Date()

        Task {
            // Stage 1: CLI Discovery
            bridgeManager.appendLog("[Handshake] Stage 1: Verifying CLI discovery...")
            guard let _ = bridgeManager.discoverCLIPath() else {
                testStatus = "Handshake Failed"
                handshakeDiagnostics = HandshakeDiagnostics(
                    stage: "Binary Verification & CLI Discovery",
                    failureReason: "Official OpenAI Codex CLI executable was not found on this machine.",
                    providerResponse: nil,
                    recommendedResolution: "Please run the Managed Installer above to set up the official Codex CLI."
                )
                isTesting = false
                return
            }

            // Stage 2: Authentication Verification
            bridgeManager.appendLog("[Handshake] Stage 2: Auditing authentication credentials...")
            await bridgeManager.auditEnvironment()
            if !bridgeManager.isAuthenticated {
                testStatus = "Handshake Failed"
                handshakeDiagnostics = HandshakeDiagnostics(
                    stage: "Authentication Handshake",
                    failureReason: "Codex CLI lacks authorized credentials. Both OpenAI API Key and ChatGPT session are inactive.",
                    providerResponse: nil,
                    recommendedResolution: "Please save a valid OpenAI API key or sign in via 'Continue with ChatGPT' to authorize the CLI."
                )
                isTesting = false
                return
            }

            // Stage 3: Request Payload & Execution Pipeline
            bridgeManager.appendLog("[Handshake] Stage 3: Initializing stream connection to backend...")
            do {
                testStatus = "Executing prompt..."
                var receivedText = ""
                try await bridgeManager.streamPrompt("Respond with 'Codex Connection Success'") { @MainActor token in
                    receivedText += token
                    testResponse = receivedText
                    testStatus = "Streaming..."
                }

                if receivedText.isEmpty {
                    throw NSError(domain: "CodexHandshake", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Received an empty response stream from the Codex backend."])
                }

                testDuration = Date().timeIntervalSince(startTime)
                testStatus = "Success"
                bridgeManager.appendLog("[Handshake] Connection successfully verified! Latency: \(String(format: "%.2f", testDuration))s")
            } catch {
                testStatus = "Handshake Failed"
                let exitCodeMessage = error.localizedDescription
                bridgeManager.appendLog("[Handshake] Connection test threw error: \(exitCodeMessage)")

                var resolution = "Ensure you have a stable internet connection. If using ChatGPT auth, try running a manual terminal command 'codex login status' to diagnose, or Sign Out and try a fresh login."
                if exitCodeMessage.contains("1") {
                    resolution = "The CLI exited with code 1. This often indicates expired credentials or a billing limit reached. Please verify your OpenAI key/account status."
                } else if exitCodeMessage.contains("401") || exitCodeMessage.contains("unauthorized") {
                    resolution = "The request was unauthorized. Please verify that your OpenAI API Key has correct permissions and is active."
                }

                handshakeDiagnostics = HandshakeDiagnostics(
                    stage: "Execution Pipeline Initialization",
                    failureReason: "Stream connection failed with error: \(exitCodeMessage)",
                    providerResponse: testResponse.isEmpty ? nil : testResponse,
                    recommendedResolution: resolution
                )
            }
            isTesting = false
        }
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, isOk: Bool) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 4) {
            Circle()
                .fill(isOk ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(value)
                .font(.caption.monospaced())
        }
    }
}
