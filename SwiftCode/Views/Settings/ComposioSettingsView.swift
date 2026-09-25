import SwiftUI
import AppKit

@MainActor
public struct ComposioSettingsView: View {
    @Bindable private var service = ComposioService.shared

    @State private var inputApiKey: String = ""
    @State private var isShowingKey: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var testResult: ComposioExecutionResult?
    @State private var isLinkingToolkit: String? = nil
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Connection Header & Status Badge
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.indigo)
                                .frame(width: 42, height: 42)
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Composio Integration Platform")
                                    .font(.headline)

                                if service.isConnected {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 8, height: 8)
                                        Text("ACTIVE")
                                            .font(.caption2.bold())
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                } else {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                                        Text("SETUP REQUIRED")
                                            .font(.caption2.bold())
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }

                            Text("Connect 1500+ external app toolkits directly to your Assist coding agent.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            Task {
                                await service.refreshStatus()
                            }
                        } label: {
                            if service.isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !service.accountEmail.isEmpty || !service.currentOrg.isEmpty {
                        Divider()

                        HStack(spacing: 24) {
                            if !service.accountEmail.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ACCOUNT")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(service.accountEmail)
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }

                            if !service.currentOrg.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ORGANIZATION")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(service.currentOrg)
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }

                            if let cli = service.resolvedCLIPath {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CLI ENGINE")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(cli)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }

            // 2. API Credentials Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("API Credentials", systemImage: "key.fill")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Spacer()

                        Link(destination: URL(string: "https://dashboard.composio.dev/~/project/settings/api-keys")!) {
                            Label("Get API Key", systemImage: "arrow.up.right")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Configure your Composio Project API Key (ak_...) or User API Key (uak_...) to enable direct SDK/REST access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if isShowingKey {
                            TextField("ak_... or uak_...", text: $inputApiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("ak_... or uak_...", text: $inputApiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button {
                            isShowingKey.toggle()
                        } label: {
                            Image(systemName: isShowingKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Key Visibility")

                        Button("Save Key") {
                            service.saveApiKey(inputApiKey)
                            statusMessage = "API Key saved to Keychain."
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(12)
            }

            // 3. Connected Accounts
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Connected Accounts", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline)
                            .foregroundColor(.indigo)

                        Spacer()

                        Text("\(service.connectedAccounts.count) Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if service.connectedAccounts.isEmpty {
                        Text("No active accounts connected yet. Connect an integration below to enable external tools.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(service.connectedAccounts) { account in
                                HStack(spacing: 12) {
                                    Image(systemName: account.systemIcon)
                                        .font(.title3)
                                        .foregroundColor(.indigo)
                                        .frame(width: 28, height: 28)
                                        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.toolkit.capitalized)
                                            .font(.subheadline.bold())

                                        if let wordId = account.wordId {
                                            Text(wordId)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    HStack(spacing: 4) {
                                        Circle().fill(account.isActive ? Color.green : Color.orange).frame(width: 6, height: 6)
                                        Text(account.status)
                                            .font(.caption2.bold())
                                            .foregroundColor(account.isActive ? .green : .orange)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background((account.isActive ? Color.green : Color.orange).opacity(0.1), in: Capsule())
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(12)
            }

            // 4. Quick Connect Integrations
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Connect Integrations", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Spacer()
                    }

                    Text("Click an integration below to launch the authorization window in your browser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let toolkits = [
                        ("GitHub", "github", "arrow.triangle.branch"),
                        ("Slack", "slack", "bubble.left.and.bubble.right.fill"),
                        ("Google Calendar", "googlecalendar", "calendar"),
                        ("Gmail", "gmail", "envelope.fill"),
                        ("Linear", "linear", "checklist"),
                        ("Jira", "jira", "list.bullet.rectangle"),
                        ("Notion", "notion", "doc.text.fill"),
                        ("Discord", "discord", "message.fill")
                    ]

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                        ForEach(toolkits, id: \.1) { name, slug, icon in
                            Button {
                                linkToolkit(slug)
                            } label: {
                                HStack(spacing: 8) {
                                    if isLinkingToolkit == slug {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    } else {
                                        Image(systemName: icon)
                                            .font(.subheadline)
                                    }
                                    Text(name)
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLinkingToolkit != nil)
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(12)
            }

            // 5. Live Tool Execution & Diagnostic Test
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Live Diagnostic Test", systemImage: "bolt.fill")
                            .font(.headline)
                            .foregroundColor(.purple)

                        Spacer()

                        Button {
                            runDiagnosticTest()
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Label("Run Test Call", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isTestingConnection)
                    }

                    Text("Execute a live, safe read-only call to verify that Assist tools and Composio APIs can communicate seamlessly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let result = testResult {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    Text(result.success ? "EXECUTION SUCCEEDED" : "EXECUTION FAILED")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(result.success ? .green : .red)

                                Spacer()

                                if result.duration > 0 {
                                    Text(String(format: "%.2fs", result.duration))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                if let logId = result.logId {
                                    Link(destination: URL(string: "https://dashboard.composio.dev/~/project/logs")!) {
                                        HStack(spacing: 2) {
                                            Text(logId)
                                            Image(systemName: "arrow.up.right")
                                        }
                                        .font(.system(size: 11, design: .monospaced))
                                    }
                                }
                            }

                            ScrollView {
                                Text(result.output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 140)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(12)
            }

            // 6. External Links & Assist Usage Guide
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Assist Tool Integration Guide", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.indigo)

                    Text("Assist has a dedicated tool registered under `use_composio`. When you chat with Assist in Agent Mode, it can automatically query connected services (e.g., 'Inspect my GitHub repos', 'Check my Slack messages', or 'List my upcoming calendar events').")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Link(destination: URL(string: "https://dashboard.composio.dev/~/project/logs")!) {
                            Label("Dashboard Logs", systemImage: "doc.text")
                                .font(.caption)
                        }

                        Link(destination: URL(string: "https://docs.composio.dev")!) {
                            Label("Documentation", systemImage: "book")
                                .font(.caption)
                        }

                        Link(destination: URL(string: "https://dashboard.composio.dev/~/project/settings")!) {
                            Label("Project Settings", systemImage: "gearshape")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .onAppear {
            if !service.apiKey.isEmpty {
                inputApiKey = service.apiKey
            }
        }
    }

    private func linkToolkit(_ slug: String) {
        isLinkingToolkit = slug
        errorMessage = nil
        Task {
            defer { isLinkingToolkit = nil }
            do {
                if let url = try await service.generateConnectLink(toolkit: slug) {
                    NSWorkspace.shared.open(url)
                    statusMessage = "Opened authorization link in your browser."
                } else {
                    errorMessage = "Failed to generate authorization link for \(slug)."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runDiagnosticTest() {
        isTestingConnection = true
        testResult = nil
        errorMessage = nil
        Task {
            defer { isTestingConnection = false }
            do {
                let res = try await service.testConnection()
                testResult = res
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
