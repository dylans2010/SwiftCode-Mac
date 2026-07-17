import SwiftUI
import AppKit

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

                    // Section 3: ChatGPT Authentication
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("ChatGPT Authentication", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.headline)
                                .foregroundColor(.green)

                            Text("Connect using your official ChatGPT account. No API Keys are required. SwiftCode will launch the browser validation and the CLI will safely persist your credentials in auth.json.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                Button {
                                    Task {
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
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Section 4: Alternative API Key Integration
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

    private func runConnectionTest() {
        isTesting = true
        testResponse = ""
        testStatus = "Executing Handshake..."
        testDuration = 0
        let startTime = Date()

        Task {
            do {
                try await bridgeManager.streamPrompt("Respond with 'Codex Connection Success'") { @MainActor token in
                    testResponse += token
                    testStatus = "Streaming..."
                }
                testDuration = Date().timeIntervalSince(startTime)
                testStatus = "Success"
            } catch {
                testStatus = "Handshake Failed"
                testError = error.localizedDescription
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