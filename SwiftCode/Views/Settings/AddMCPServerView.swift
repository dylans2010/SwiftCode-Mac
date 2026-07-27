import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.mcp", category: "AddMCPServerView")

// MARK: - Key Value Pair Helper Model

struct MCPKeyValuePair: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}

// MARK: - AddMCPServerView

@MainActor
public struct AddMCPServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = MCPServerManager.shared

    // Active sheet states
    @State private var showAddServerSheet = false
    @State private var editingServer: MCPServer? = nil

    // Tools browser states
    @State private var browsingServer: MCPServer? = nil
    @State private var showToolsBrowser = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Label("Model Context Protocol (MCP) Manager", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()

                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/mcp")!)
                }) {
                    Label("Discover MCPs", systemImage: "safari")
                }
                .buttonStyle(.bordered)

                Button(action: { showAddServerSheet = true }) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Quick Introduction card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About Model Context Protocol")
                                .font(.headline)
                            Text("MCP allows SwiftCode to securely connect to external developer tools, language servers, and contextual backends. Configured servers can be dynamically explored and executed by your AI Agents during autonomous tasks.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Configured Servers Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Configured Servers (\(manager.servers.count))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        if manager.servers.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No MCP servers configured yet.")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Add a local stdio executable or remote HTTP server to extend the capabilities of your AI assistant.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            // Subview displaying the table list
                            AddedMCPServersView(
                                manager: manager,
                                onEdit: { server in
                                    editingServer = server
                                },
                                onViewTools: { server in
                                    browsingServer = server
                                    showToolsBrowser = true
                                }
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        // Sheets
        .sheet(isPresented: $showAddServerSheet) {
            ServerConfigFormView(manager: manager, serverToEdit: nil)
        }
        .sheet(item: $editingServer) { server in
            ServerConfigFormView(manager: manager, serverToEdit: server)
        }
        .sheet(isPresented: $showToolsBrowser) {
            if let server = browsingServer {
                ToolsBrowserSheet(server: server)
            }
        }
    }
}

// MARK: - Server Configuration Form (Add/Edit)

struct ServerConfigFormView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: MCPServerManager
    let serverToEdit: MCPServer?

    // Form fields
    @State private var displayName = ""
    @State private var transport: MCPTransport = .stdio
    @State private var urlString = "http://localhost:3011"
    @State private var executablePath = ""
    @State private var launchArguments = ""
    @State private var envVars: [MCPKeyValuePair] = []
    @State private var customHeaders: [MCPKeyValuePair] = []
    @State private var authType: MCPAuthenticationType = .none
    @State private var secretKey = ""

    // Testing State
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var testSuccess: Bool? = nil
    @State private var testMetadata: MCPServerMetadata? = nil
    @State private var testTools: [MCPTool] = []
    @State private var showLogsSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // General Config Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("General Configuration", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            TextField("Server Display Name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()

                            Picker("Transport Type", selection: $transport) {
                                Text("Local Stdio Subprocess").tag(MCPTransport.stdio)
                                Text("HTTP API endpoint").tag(MCPTransport.http)
                                Text("HTTPS Secure API endpoint").tag(MCPTransport.https)
                            }
                            .pickerStyle(.radioGroup)
                            .horizontalRadioGroupLayout()
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Transport details Card
                    if transport == .stdio {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Local Stdio Subprocess Configuration", systemImage: "terminal.fill")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }

                                TextField("Executable absolute path", text: $executablePath)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()

                                TextField("Launch arguments (comma-separated)", text: $launchArguments)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("Subprocess Environment Variables", systemImage: "slider.horizontal.3")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Button(action: {
                                            envVars.append(MCPKeyValuePair(key: "KEY", value: "VALUE"))
                                        }) {
                                            Label("Add Environment Var", systemImage: "plus")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.accentColor)
                                    }

                                    ForEach($envVars) { $env in
                                        HStack {
                                            TextField("Key", text: $env.key)
                                                .textFieldStyle(.roundedBorder)
                                            TextField("Value", text: $env.value)
                                                .textFieldStyle(.roundedBorder)
                                            Button(role: .destructive) {
                                                envVars.removeAll { $0.id == env.id }
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    } else {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("HTTP / HTTPS API Configuration", systemImage: "network")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }

                                TextField("Server Base URL", text: $urlString)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()

                                Picker("Authorization Type", selection: $authType) {
                                    Text("None").tag(MCPAuthenticationType.none)
                                    Text("API Key Header").tag(MCPAuthenticationType.apiKey)
                                    Text("Bearer Authorization Token").tag(MCPAuthenticationType.bearerToken)
                                    Text("OAuth Access Token").tag(MCPAuthenticationType.oauth)
                                    Text("Environment Variables").tag(MCPAuthenticationType.envVars)
                                    Text("Custom HTTP Headers").tag(MCPAuthenticationType.customHeaders)
                                }

                                if authType == .apiKey || authType == .bearerToken || authType == .oauth {
                                    SecureField(authType == .apiKey ? "API Key" : (authType == .bearerToken ? "Bearer Token" : "OAuth Token"), text: $secretKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                if authType == .customHeaders {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Label("Custom HTTP Headers", systemImage: "checklist")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Button("Add Header") {
                                                customHeaders.append(MCPKeyValuePair(key: "X-My-Header", value: "Value"))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.accentColor)
                                        }

                                        ForEach($customHeaders) { $header in
                                            HStack {
                                                TextField("Header Key", text: $header.key)
                                                    .textFieldStyle(.roundedBorder)
                                                TextField("Value", text: $header.value)
                                                    .textFieldStyle(.roundedBorder)
                                                Button(role: .destructive) {
                                                    customHeaders.removeAll { $0.id == header.id }
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Diagnostics Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Verification Diagnostics", systemImage: "checkmark.shield.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()

                                Button(action: { showLogsSheet = true }) {
                                    Label("Connection Logs", systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(.bordered)
                            }

                            HStack(spacing: 12) {
                                Button(action: testConnection) {
                                    HStack {
                                        if isTesting {
                                            ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                        } else {
                                            Image(systemName: "play.circle.fill")
                                        }
                                        Text(isTesting ? "Testing Handshake..." : "Test Connection Handshake")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isTesting)

                                if let success = testSuccess {
                                    HStack(spacing: 6) {
                                        Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .foregroundColor(success ? .green : .red)
                                        Text(success ? "HANDSHAKE PASSED" : "HANDSHAKE FAILED")
                                            .font(.caption.bold())
                                            .foregroundColor(success ? .green : .red)
                                    }
                                }
                            }

                            if let result = testResult {
                                VStack(alignment: .leading, spacing: 6) {
                                    if testSuccess == false {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(result, forType: .string)
                                            }) {
                                                Label("Copy Failure Logs", systemImage: "doc.on.doc")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }

                                    Text(result)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.12))
                                        .cornerRadius(6)
                                        .foregroundColor(testSuccess == true ? .green : .red)
                                }
                            }

                            if !testTools.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Discovered Available Tools (\(testTools.count)):")
                                        .font(.subheadline.bold())
                                    ForEach(testTools) { tool in
                                        HStack {
                                            Image(systemName: "hammer.fill")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                            Text(tool.name)
                                                .font(.system(.caption, design: .monospaced))
                                            if let desc = tool.description {
                                                Text("- \(desc)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(.leading, 8)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(20)
            }
            .navigationTitle(serverToEdit == nil ? "Add MCP Server" : "Edit MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveServer() }
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                loadServerData()
            }
            .sheet(isPresented: $showLogsSheet) {
                MCPLogsView(serverFilter: displayName.isEmpty ? nil : displayName)
            }
        }
        .frame(width: 580, height: 650)
    }

    private func loadServerData() {
        guard let server = serverToEdit else { return }
        displayName = server.displayName
        transport = server.transport
        urlString = server.urlString
        executablePath = server.executablePath ?? ""
        launchArguments = server.launchArguments?.joined(separator: ", ") ?? ""
        authType = server.authType

        // Map environment variables
        if let env = server.envVariables {
            envVars = env.map { MCPKeyValuePair(key: $0.key, value: $0.value) }
        }

        // Map custom headers
        if let headers = server.customHeaders {
            customHeaders = headers.map { MCPKeyValuePair(key: $0.key, value: $0.value) }
        }

        // Map secret
        if let secret = manager.getSecret(for: server.id) {
            secretKey = secret
        }
    }

    private func constructServerObject(id: UUID) -> MCPServer {
        let trimmedArgs = launchArguments.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        var mappedEnv: [String: String] = [:]
        for pair in envVars {
            if !pair.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mappedEnv[pair.key] = pair.value
            }
        }

        var mappedHeaders: [String: String] = [:]
        for pair in customHeaders {
            if !pair.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mappedHeaders[pair.key] = pair.value
            }
        }

        return MCPServer(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: transport,
            urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            executablePath: executablePath.isEmpty ? nil : executablePath.trimmingCharacters(in: .whitespacesAndNewlines),
            launchArguments: trimmedArgs.isEmpty ? nil : trimmedArgs,
            envVariables: mappedEnv.isEmpty ? nil : mappedEnv,
            customHeaders: mappedHeaders.isEmpty ? nil : mappedHeaders,
            authType: authType
        )
    }

    private func testConnection() {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil
        testSuccess = nil
        testMetadata = nil
        testTools = []

        let testServer = constructServerObject(id: serverToEdit?.id ?? UUID())

        Task {
            do {
                let (metadata, tools) = try await manager.testConnection(config: testServer, secretKey: secretKey.isEmpty ? nil : secretKey)
                testSuccess = true
                testMetadata = metadata
                testTools = tools
                testResult = "Handshake Successful!\nServer: \(metadata.name)\nVersion: \(metadata.version)\nProtocol: \(metadata.protocolVersion)\nDiscovered \(tools.count) callable tools."
            } catch {
                testSuccess = false
                testResult = "Connection test failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func saveServer() {
        let serverID = serverToEdit?.id ?? UUID()
        let server = constructServerObject(id: serverID)

        if serverToEdit == nil {
            manager.addServer(server, secretKey: secretKey.isEmpty ? nil : secretKey)
        } else {
            manager.updateServer(server, secretKey: secretKey.isEmpty ? nil : secretKey)
        }
        dismiss()
    }
}

// MARK: - Tools Browser Sheet

struct ToolsBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    let server: MCPServer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Browse every real capability and schema returned by MCP server '\(server.displayName)'. These schemas inform agents of correct argument mappings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Available Tools (\(server.tools.count))") {
                    if server.tools.isEmpty {
                        Text("No tools found on this server. Connect or refresh server capabilities.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(server.tools) { tool in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(tool.name, systemImage: "hammer.fill")
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    if tool.isCallable {
                                        Text("CALLABLE")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }

                                if let desc = tool.description {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                // Interactive input parameters scheme block
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("INPUT PARAMETERS SCHEMA")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)

                                    let schemaDesc = formatSchema(tool.inputSchema)
                                    Text(schemaDesc)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.12))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("\(server.displayName) - Real Capabilities")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 580, height: 600)
    }

    private func formatSchema(_ schema: MCPToolSchema) -> String {
        guard let data = try? JSONEncoder().encode(schema),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return "type: \(schema.type)"
        }
        return prettyString
    }
}

// MARK: - MCPLogsView

struct MCPLogsView: View {
    @Environment(\.dismiss) private var dismiss
    let serverFilter: String? // nil or server display name to filter by

    @State private var searchText = ""
    @State private var selectedSeverity: MCPLogSeverity? = nil

    private var filteredLogs: [MCPLogEntry] {
        let allLogs = MCPLoggingManager.shared.logs
        return allLogs.filter { log in
            if let serverFilter = serverFilter, !serverFilter.isEmpty {
                guard log.serverName.lowercased() == serverFilter.lowercased() else { return false }
            }
            if let selectedSeverity = selectedSeverity {
                guard log.severity == selectedSeverity else { return false }
            }
            if !searchText.isEmpty {
                guard log.message.localizedCaseInsensitiveContains(searchText) ||
                      log.serverName.localizedCaseInsensitiveContains(searchText) else { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter logs...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().frame(height: 16)

                    Picker("Severity", selection: $selectedSeverity) {
                        Text("All Severities").tag(MCPLogSeverity?.none)
                        Text("Info").tag(MCPLogSeverity.info as MCPLogSeverity?)
                        Text("Warnings").tag(MCPLogSeverity.warning as MCPLogSeverity?)
                        Text("Errors").tag(MCPLogSeverity.error as MCPLogSeverity?)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)

                    Button(role: .destructive) {
                        MCPLoggingManager.shared.clearLogs()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if filteredLogs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No log entries match active filters")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
                } else {
                    List {
                        ForEach(filteredLogs) { log in
                            HStack(alignment: .top, spacing: 10) {
                                // Timestamp
                                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 75, alignment: .leading)

                                // Severity badge
                                Text(log.severity.rawValue)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(severityColor(log.severity).opacity(0.12), in: Capsule())
                                    .foregroundColor(severityColor(log.severity))
                                    .frame(width: 55, alignment: .center)

                                // Server tag
                                Text(log.serverName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .leading)

                                // Message
                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle(serverFilter == nil ? "Centralized MCP Diagnostics" : "\(serverFilter!) - Diagnostics Console")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 750, height: 480)
    }

    private func severityColor(_ severity: MCPLogSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
