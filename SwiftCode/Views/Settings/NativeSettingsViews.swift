import SwiftUI
import AppKit

// MARK: - 1. SettingsCategory

public enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general = "general"
    case themes = "themes"
    case cloud = "cloud"
    case backups = "backups"
    case connect = "connect_host"
    case assist = "ai_assist"
    case composio = "composio"
    case offlineModels = "offline_models"
    case plugins = "plugins"
    case updates = "updates"
    case credits = "credits"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .themes: return "Themes"
        case .cloud: return "Cloud"
        case .backups: return "Backups"
        case .connect: return "Connect"
        case .assist: return "AI & Assist"
        case .composio: return "Composio"
        case .offlineModels: return "Offline Models"
        case .plugins: return "Plugins"
        case .updates: return "Updates"
        case .credits: return "Credits"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .themes: return "paintbrush"
        case .cloud: return "icloud"
        case .backups: return "clock.arrow.circlepath"
        case .connect: return "iphone.radiowaves.left.and.right"
        case .assist: return "sparkles"
        case .composio: return "link.badge.plus"
        case .offlineModels: return "externaldrive"
        case .plugins: return "cpu"
        case .updates: return "arrow.triangle.2.circlepath.circle"
        case .credits: return "person.2"
        }
    }

    public var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("com.swiftcode.settings.\(rawValue)")
    }
}

// MARK: - 0. NativeSettingsLayout & State

public enum NativeSettingsLayout {
    public static let width: CGFloat = 820
    public static let height: CGFloat = 640
}

@Observable
@MainActor
public final class NativeSettingsState {
    public static let shared = NativeSettingsState()
    public var selectedCategory: SettingsCategory = .general
}

// MARK: - 2. NativeSettingsContainerView

public struct NativeSettingsContainerView: View {
    @Bindable var state: NativeSettingsState = .shared
    @EnvironmentObject private var settings: AppSettings

    public init(state: NativeSettingsState = .shared) {
        self.state = state
    }

    public init(selectedCategory: SettingsCategory) {
        self.state = .shared
        self.state.selectedCategory = selectedCategory
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(nsColor: .separatorColor))

            Group {
                switch state.selectedCategory {
                case .general:
                    NativeGeneralSettingsView()
                case .themes:
                    NativeThemesSettingsView()
                case .cloud:
                    NativeCloudSettingsView()
                case .backups:
                    NativeBackupsSettingsView()
                case .connect:
                    NativeConnectSettingsView()
                case .assist:
                    NativeAssistSettingsView()
                case .composio:
                    NativeComposioSettingsView()
                case .offlineModels:
                    NativeOfflineModelsSettingsView()
                case .plugins:
                    NativePluginsSettingsView()
                case .updates:
                    NativeUpdatesSettingsView()
                case .credits:
                    NativeCreditsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(width: NativeSettingsLayout.width, height: NativeSettingsLayout.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
        .environmentObject(settings)
    }
}

// MARK: - 3. NativeGeneralSettingsView

public struct NativeGeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    public init() {}

    public var body: some View {
        Form {
            Section("Settings Experience") {
                Toggle("Use New Settings Window", isOn: $settings.useNewSettingsWindow)
                Text("When enabled, preferences will open in the modern native macOS settings window with toolbar tabs. Disable to use the legacy multi-panel window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Editor Defaults") {
                Stepper(value: $settings.editorFontSize, in: 9...36, step: 1) {
                    HStack {
                        Text("Editor Font Size")
                        Spacer()
                        Text("\(Int(settings.editorFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Toggle("Auto-Save", isOn: $settings.autoSave)
                Text("Automatically save open documents as edits are performed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Start on New Project", isOn: $settings.startOnNewProject)
                Text("Display the new project template wizard when SwiftCode launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Organization & Templates") {
                TextField("Default Organization", text: $settings.defaultOrganization)
                Text("Organization identifier used for bundle identifiers in generated projects (e.g. com.example).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Author Name", text: $settings.fileHeaderAuthor)
                Text("Name placed in generated file header comments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Custom Comment", text: $settings.fileHeaderCustomComment)
                Text("Custom text or copyright notice appended to generated file headers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Project Location") {
                Toggle("Save Projects to Custom Folder", isOn: $settings.saveProjectsOnCustomFolder)

                HStack(spacing: 8) {
                    TextField("Folder Path", text: $settings.customProjectsFolder)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.saveProjectsOnCustomFolder)

                    Button("Choose...") {
                        selectCustomFolder()
                    }
                    .disabled(!settings.saveProjectsOnCustomFolder)
                }
            }
        }
        .formStyle(.grouped)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let selectedURL = panel.url {
            settings.customProjectsFolder = selectedURL.path
        }
    }
}

// MARK: - 4. NativeThemesSettingsView

public struct NativeThemesSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("editorLineSpacing") private var lineSpacing: Double = 4.0
    @State private var themeManager = ThemeManager.shared

    public init() {}

    public var body: some View {
        Form {
            Section("Theme Selection") {
                Toggle("Use Dark Appearance", isOn: $settings.useDarkTheme)

                Picker("Editor Syntax Theme", selection: $settings.selectedThemeID) {
                    ForEach(themeManager.allThemes) { theme in
                        HStack {
                            Text(theme.name)
                            if theme.isBuiltIn {
                                Text("(Preset)").foregroundStyle(.secondary)
                            }
                        }
                        .tag(theme.id)
                    }
                }
            }

            Section("Typography & Spacing") {
                Stepper(value: $settings.editorFontSize, in: 9...36, step: 1) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(settings.editorFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Stepper(value: $lineSpacing, in: 0...20, step: 1) {
                    HStack {
                        Text("Line Spacing")
                        Spacer()
                        Text("\(Int(lineSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Active Theme Palette") {
                if let activeTheme = themeManager.theme(for: settings.selectedThemeID) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("Color Tokens:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ForEach([
                                activeTheme.colors.background,
                                activeTheme.colors.syntaxKeyword,
                                activeTheme.colors.accent,
                                activeTheme.colors.syntaxString
                            ], id: \.self) { hex in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        }

                        Text("struct ContentView: View {\n    var body: some View {\n        Text(\"Hello, SwiftCode!\")\n            .padding()\n    }\n}")
                            .font(.system(size: settings.editorFontSize, weight: .regular, design: .monospaced))
                            .lineSpacing(lineSpacing)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: activeTheme.colors.background))
                            .foregroundColor(Color(hex: activeTheme.colors.syntaxKeyword))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 5. NativeCloudSettingsView

public struct NativeCloudSettingsView: View {
    @AppStorage("com.swiftcode.cloud.syncEnabled") private var syncEnabled = false
    @State private var cloudManager = CloudManager.shared
    @State private var isSyncing = false
    @State private var syncStatusMessage: String?
    @State private var syncSuccess: Bool = true
    @State private var pendingQueueCount: Int = 0

    public init() {}

    public var body: some View {
        Form {
            Section("Supabase Cloud Integration") {
                LabeledContent("Endpoint URL") {
                    Text("https://secctbuzkfbketdihzui.supabase.co")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("SSL Security") {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Text("TLS 1.3 Active")
                    }
                }

                LabeledContent("Authentication Session") {
                    if AuthManager.shared.isAuthenticated, let user = AuthManager.shared.currentUser {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text(user.email)
                        }
                    } else {
                        Text("Not Signed In (Local Workspace)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Synchronization") {
                Toggle("Continuous Real-Time Sync", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, newValue in
                        Task {
                            await CloudSyncEngine.shared.setSyncEnabled(newValue)
                        }
                    }

                Text("Automatically synchronize workspace settings, files, and templates with your remote Supabase storage bucket.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Current State") {
                    Text(cloudManager.syncState.rawValue.capitalized)
                        .foregroundStyle(syncStateColor)
                        .font(.caption.bold())
                }

                LabeledContent("Last Synchronized") {
                    if let lastSync = cloudManager.lastSyncTime {
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Pending Queue") {
                    Text("\(pendingQueueCount) items")
                        .font(.caption)
                }

                HStack {
                    Button {
                        triggerManualSync()
                    } label: {
                        HStack(spacing: 6) {
                            if isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Sync Now")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncing)

                    if let message = syncStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(syncSuccess ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshSyncInfo()
        }
    }

    private var syncStateColor: Color {
        switch cloudManager.syncState {
        case .idle: return .green
        case .syncing: return .blue
        case .paused: return .orange
        case .error: return .red
        }
    }

    private func refreshSyncInfo() {
        Task {
            pendingQueueCount = await SyncQueue.shared.getPendingUploadCount()
        }
    }

    private func triggerManualSync() {
        isSyncing = true
        syncStatusMessage = nil
        Task {
            await CloudSyncEngine.shared.triggerSync()
            refreshSyncInfo()
            isSyncing = false
            syncSuccess = true
            syncStatusMessage = "Sync completed successfully."
        }
    }
}

// MARK: - 6. NativeBackupsSettingsView

public struct NativeBackupsSettingsView: View {
    @State private var backups: [BackupManifest] = []
    @State private var showingCreateSheet = false
    @State private var selectedManifest: BackupManifest?
    @State private var restoreStatusMessage: String?
    @State private var isSuccessStatus = true
    @State private var manifestToRestore: BackupManifest?
    @State private var showRestoreConfirmation = false

    public init() {}

    public var body: some View {
        Form {
            Section("Snapshot Management") {
                Text("Point-in-time snapshots capture local preferences, syntax themes, project listings, and workspace configurations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Create Backup Snapshot...") {
                        showingCreateSheet = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh") {
                        loadBackups()
                    }
                }

                if let message = restoreStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: isSuccessStatus ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isSuccessStatus ? .green : .red)
                        Text(message)
                            .font(.caption.bold())
                            .foregroundStyle(isSuccessStatus ? .green : .red)
                    }
                }
            }

            Section("Saved Backups (\(backups.count))") {
                if backups.isEmpty {
                    Text("No backup snapshots created yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { manifest in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(manifest.filename.isEmpty ? "Snapshot \(manifest.backupID.prefix(8))" : manifest.filename)
                                    .font(.headline)

                                HStack(spacing: 8) {
                                    Text(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    Text("•")
                                    Text(ByteCountFormatter.string(fromByteCount: manifest.sizeInBytes, countStyle: .file))
                                    if manifest.isCloudStored {
                                        Text("•")
                                        Text("Cloud").foregroundStyle(.blue)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Details") {
                                selectedManifest = manifest
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Restore") {
                                manifestToRestore = manifest
                                showRestoreConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadBackups()
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateBackupView()
                .onDisappear {
                    loadBackups()
                }
        }
        .sheet(item: $selectedManifest) { manifest in
            NavigationStack {
                BackupDetailsView(manifest: manifest)
            }
            .onDisappear {
                loadBackups()
            }
        }
        .confirmationDialog(
            "Restore Backup Snapshot",
            isPresented: $showRestoreConfirmation,
            presenting: manifestToRestore
        ) { manifest in
            Button("Restore Snapshot", role: .destructive) {
                performRestore(manifest: manifest)
            }
            Button("Cancel", role: .cancel) {}
        } message: { manifest in
            Text("Are you sure you want to restore snapshot from \(manifest.createdAt.formatted())? Current unsaved settings may be overwritten.")
        }
    }

    private func loadBackups() {
        Task {
            BackupEngine.shared.loadLocalBackups()
            backups = BackupEngine.shared.backups
        }
    }

    private func performRestore(manifest: BackupManifest) {
        Task {
            do {
                _ = try await BackupEngine.shared.restore(manifest: manifest)
                isSuccessStatus = true
                restoreStatusMessage = "Restored successfully from \(manifest.filename)."
            } catch {
                isSuccessStatus = false
                restoreStatusMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 7. NativeConnectSettingsView

public struct NativeConnectSettingsView: View {
    @State private var connectServer = ConnectServer.shared
    @State private var bonjour = BonjourAdvertiser.shared
    @State private var diagnostics = ConnectDiagnostics.shared
    @State private var portString: String = ""
    @State private var portError: String?

    public init() {}

    public var body: some View {
        Form {
            Section("SwiftCode Connect Server") {
                Toggle("Server Running", isOn: Binding(
                    get: { connectServer.isRunning },
                    set: { shouldRun in
                        Task {
                            if shouldRun {
                                do {
                                    try await connectServer.startServer()
                                    portError = nil
                                } catch {
                                    portError = error.localizedDescription
                                }
                            } else {
                                connectServer.stopServer()
                                portError = nil
                            }
                        }
                    }
                ))

                LabeledContent("Server State") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectServer.isRunning ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(connectServer.isRunning ? "Active (Listening)" : "Stopped")
                            .font(.caption.bold())
                            .foregroundStyle(connectServer.isRunning ? .green : .secondary)
                    }
                }

                LabeledContent("Active Port") {
                    if let port = connectServer.activePort {
                        Text("\(port)")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Configured Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)

                    Button("Apply Port") {
                        if let port = UInt16(portString) {
                            Task {
                                do {
                                    try await connectServer.applyPort(port)
                                    portError = nil
                                } catch {
                                    portError = error.localizedDescription
                                }
                            }
                        } else {
                            portError = "Invalid port number. Must be between 1024 and 65535."
                        }
                    }
                }

                if let error = portError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Network & Bonjour Discovery") {
                LabeledContent("Device Name") {
                    Text(bonjour.macName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Device ID") {
                    Text(bonjour.deviceID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Local IP Address") {
                    Text(diagnostics.localIPAddress ?? "Not Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Bonjour Advertising") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bonjour.isAdvertising ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(bonjour.isAdvertising ? "Broadcasting to Local Network" : "Idle")
                            .font(.caption)
                    }
                }

                LabeledContent("Active Sessions") {
                    Text("\(connectServer.activeSessions.count) connected")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            portString = "\(connectServer.configuredPort)"
            diagnostics.refreshLocalIP()
        }
    }
}

// MARK: - 8. NativeAssistSettingsView

public struct NativeAssistSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    public init() {}

    public var body: some View {
        AssistSettingsView()
            .environmentObject(settings)
            .clipped()
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

// MARK: - 9. NativeComposioSettingsView

public struct NativeComposioSettingsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            ComposioSettingsView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 10. NativeOfflineModelsSettingsView

public struct NativeOfflineModelsSettingsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            OfflineModelsView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 11. NativePluginsSettingsView

public struct NativePluginsSettingsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            PluginManagerView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 12. NativeUpdatesSettingsView

public struct NativeUpdatesSettingsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            UpdatesView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 13. NativeCreditsSettingsView

public struct NativeCreditsSettingsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            CreditsView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
