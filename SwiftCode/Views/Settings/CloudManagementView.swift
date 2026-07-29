import SwiftUI
import Appwrite
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "CloudManagementView")

@MainActor
public struct CloudManagementView: View {
    @AppStorage("com.swiftcode.cloud.syncEnabled") private var syncEnabled = false
    @State private var showingAuthSheet = false
    @State private var stats = CloudStatistics()
    @State private var selectedTab = 0

    // Interactive edit sheet states
    @State private var showingChangeEmail = false
    @State private var showingChangePassword = false

    // Server Ping Connection States
    @State private var isTestingConnection = false
    @State private var testConnectionResult: String?
    @State private var testConnectionSuccess = false

    private var authManager = AuthManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Account & Setup").tag(0)
                Text("Cloud Sync").tag(1)
                Text("System Telemetry").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Divider()
                .padding(.top, 12)

            if selectedTab == 0 {
                accountSetupTab
            } else if selectedTab == 1 {
                CloudSyncView()
            } else {
                CloudStatusView()
            }
        }
        .sheet(isPresented: $showingAuthSheet) {
            CloudAuthViews(onSuccess: {
                loadStats()
            })
        }
        .sheet(isPresented: $showingChangeEmail) {
            ChangeEmailSheet()
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordSheet()
        }
        .onAppear {
            loadStats()
        }
    }

    private var accountSetupTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Section 1: User Account & Connection Status
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("User Session", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        if authManager.isAuthenticated, let user = authManager.currentUser {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Signed in as:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(user.email)
                                            .font(.title3.bold())
                                    }

                                    Spacer()

                                    // Verification status badge
                                    HStack(spacing: 4) {
                                        Image(systemName: user.emailVerification ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                        Text(user.emailVerification ? "Verified" : "Unverified")
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(user.emailVerification ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .foregroundColor(user.emailVerification ? .green : .orange)
                                    .cornerRadius(6)
                                }

                                Divider()

                                // Display permanent SwiftCode ID
                                if let swiftCodeID = authManager.swiftCodeID {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Canonical SwiftCode ID:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        HStack {
                                            Text(swiftCodeID)
                                                .font(.system(.subheadline, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(6)
                                                .background(Color.secondary.opacity(0.1))
                                                .cornerRadius(4)

                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(swiftCodeID, forType: .string)
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }

                                Divider()

                                // Operational controls
                                HStack(spacing: 12) {
                                    Button {
                                        showingChangeEmail = true
                                    } label: {
                                        Label("Change Email", systemImage: "envelope")
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        showingChangePassword = true
                                    } label: {
                                        Label("Change Password", systemImage: "key")
                                    }
                                    .buttonStyle(.bordered)

                                    if !user.emailVerification {
                                        Button {
                                            sendVerification()
                                        } label: {
                                            Label("Verify Email", systemImage: "paperplane")
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    Spacer()

                                    Button {
                                        refreshAccountInfo()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Refresh account details")

                                    Button(role: .destructive) {
                                        logout()
                                    } label: {
                                        Text("Sign Out")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Divider()

                                Button(role: .destructive) {
                                    confirmDeleteAccount()
                                } label: {
                                    Label("Permanently Delete Account", systemImage: "person.crop.circle.badge.xmark")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sign in to your SwiftCode Cloud account to enable automatic data sync and point-in-time cloud backups.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showingAuthSheet = true
                                } label: {
                                    Label("Sign In or Register", systemImage: "lock.shield.fill")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 2: Appwrite Server Ping Test
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Appwrite Server Connection", systemImage: "network")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                        }

                        Text("Test responsiveness and latency to the hosted Appwrite authentication server.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(action: testServerConnection) {
                                HStack {
                                    if isTestingConnection {
                                        ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                    }
                                    Text(isTestingConnection ? "Testing Connection..." : "Test Connection to Server")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTestingConnection)

                            if let result = testConnectionResult {
                                HStack(spacing: 6) {
                                    Image(systemName: testConnectionSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(testConnectionSuccess ? .green : .red)
                                    Text(result)
                                        .font(.subheadline.bold())
                                        .foregroundColor(testConnectionSuccess ? .green : .red)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 3: Sync Engine Configurations
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Continuous Cloud Sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        Toggle(isOn: $syncEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Sync Engine")
                                    .font(.subheadline.bold())
                                Text("Automatically keep your projects, AI chat histories, snippets, preferences, and workspace settings synchronized across all your devices.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!authManager.isAuthenticated)
                        .onChange(of: syncEnabled) { _, newValue in
                            Task {
                                await CloudSyncEngine.shared.setSyncEnabled(newValue)
                            }
                        }

                        if !authManager.isAuthenticated {
                            Text("Please sign in above to enable cloud synchronization options.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 4: Sync Activity Stats
                if syncEnabled && authManager.isAuthenticated {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Synchronization Metrics", systemImage: "chart.bar.xaxis")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                                Button {
                                    Task { await CloudSyncEngine.shared.triggerSync() }
                                } label: {
                                    Label("Sync Now", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            HStack(spacing: 20) {
                                StatCard(title: "Uploaded Records", value: "\(stats.totalUploadCount)", icon: "arrow.up.circle.fill", color: .green)
                                StatCard(title: "Downloaded Records", value: "\(stats.totalDownloadCount)", icon: "arrow.down.circle.fill", color: .blue)
                                StatCard(title: "Pending Changes", value: "\(stats.pendingUploadsCount)", icon: "clock.fill", color: .orange)
                            }

                            if let lastSync = stats.lastSyncTimestamp {
                                Text("Last synchronized at: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
    }

    private func loadStats() {
        Task {
            stats = await CloudSyncEngine.shared.getStatistics()
        }
    }

    private func refreshAccountInfo() {
        Task {
            await authManager.restoreSession()
        }
    }

    private func sendVerification() {
        Task {
            do {
                try await authManager.sendVerificationEmail()
                logger.info("Verification email dispatched.")
            } catch {
                logger.error("Failed to dispatch verification email: \(error.localizedDescription)")
            }
        }
    }

    private func logout() {
        Task {
            await authManager.logout()
            syncEnabled = false
            await CloudSyncEngine.shared.setSyncEnabled(false)
            loadStats()
        }
    }

    private func confirmDeleteAccount() {
        let alert = NSAlert()
        alert.messageText = "Permanently Delete SwiftCode Account?"
        alert.informativeText = "Warning: This will permanently delete your user account and all remote credentials on the Appwrite authentication server. This action is destructive and cannot be undone."
        alert.addButton(withTitle: "Delete Account")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    try await authManager.deleteAccount()
                    syncEnabled = false
                    await CloudSyncEngine.shared.setSyncEnabled(false)
                    loadStats()
                } catch {
                    logger.error("Account self-deletion failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func testServerConnection() {
        isTestingConnection = true
        testConnectionResult = nil

        Task {
            do {
                _ = try await authManager.client.ping()
                testConnectionSuccess = true
                testConnectionResult = "Connection Succeeded (Appwrite Server Reachable)"
            } catch {
                testConnectionSuccess = false
                testConnectionResult = "Connection Failed: \(error.localizedDescription)"
            }
            isTestingConnection = false
        }
    }
}

// MARK: - Change Email Sheet

struct ChangeEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New Email Address", text: $newEmail)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    SecureField("Current Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Change Email Address")
                }

                if let error = errorText {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption.bold())
                    }
                }

                Section {
                    Button {
                        saveEmail()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                            }
                            Text("Save Email")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || newEmail.isEmpty || password.isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Update Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 380, height: 280)
    }

    private func saveEmail() {
        isSaving = true
        errorText = nil
        Task {
            do {
                try await AuthManager.shared.changeEmail(newEmail: newEmail, password: SecureString(password))
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Change Password Sheet

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Password", text: $oldPassword)
                        .textFieldStyle(.roundedBorder)
                    SecureField("New Password", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Update Credentials")
                }

                if let error = errorText {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption.bold())
                    }
                }

                Section {
                    Button {
                        savePassword()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                            }
                            Text("Change Password")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || oldPassword.isEmpty || newPassword.isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Update Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 380, height: 280)
    }

    private func savePassword() {
        isSaving = true
        errorText = nil
        Task {
            do {
                try await AuthManager.shared.changePassword(oldPassword: SecureString(oldPassword), newPassword: SecureString(newPassword))
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Modern GroupBox Styling Shorthand

struct ModernGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}
