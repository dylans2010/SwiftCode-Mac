import SwiftUI

public struct SupabaseCloudView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var emailInput = ""
    @State private var passwordInput = ""
    @State private var errorMessage = ""
    @State private var isProcessing = false

    private var authService: SupabaseAuthService {
        SupabaseAuthService.shared
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("SwiftCode Cloud (Supabase)")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !errorMessage.isEmpty {
                        GroupBox {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                Spacer()
                                Button("Dismiss") {
                                    errorMessage = ""
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(4)
                        }
                    }

                    // Account Authentication Card
                    GroupBox(label: Label("Account Status", systemImage: "person.crop.circle.badge.checkmark")) {
                        VStack(alignment: .leading, spacing: 12) {
                            if authService.authState == .authenticated {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Signed in as:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(authService.currentUserEmail ?? "active_session_user")
                                            .bold()
                                    }
                                    Spacer()
                                    if isProcessing {
                                        ProgressView().scaleEffect(0.5)
                                    } else {
                                        Button("Sign Out") {
                                            executeAuthAction {
                                                try await authService.signOut()
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Email Address", text: $emailInput)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isProcessing)
                                    SecureField("Password", text: $passwordInput)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isProcessing)

                                    HStack {
                                        if isProcessing {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        } else {
                                            Button("Sign In") {
                                                executeAuthAction {
                                                    try await authService.signInWithEmail(email: emailInput, password: passwordInput)
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(emailInput.isEmpty || passwordInput.isEmpty)

                                            Button("Create Account") {
                                                executeAuthAction {
                                                    try await authService.signUpWithEmail(email: emailInput, password: passwordInput)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(emailInput.isEmpty || passwordInput.isEmpty)

                                            Spacer()

                                            Button("Sign in with Apple") {
                                                executeAuthAction {
                                                    try await authService.signInWithProvider(name: "Apple")
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Connection Status & Realtime Monitoring
                    GroupBox(label: Label("Realtime Connection Diagnostics", systemImage: "wifi.circle")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("WebSocket Status:")
                                Spacer()
                                if authService.authState == .authenticated {
                                    Text("Connected (Heartbeat OK)")
                                        .foregroundStyle(.green)
                                        .bold()
                                } else {
                                    Text("Disconnected")
                                        .foregroundStyle(.red)
                                }
                            }

                            HStack {
                                Text("Active Channels:")
                                Spacer()
                                Text("public:profiles, public:projects, public:backups")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Active Endpoint:")
                                Spacer()
                                Text(authService.supabaseURL)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Administration Actions
                    GroupBox(label: Label("Cloud Administration", systemImage: "wrench.and.screwdriver")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Button("Sync Now") {
                                    Task {
                                        try? await CloudSyncEngineImpl.shared.triggerSync()
                                    }
                                }
                                .buttonStyle(.bordered)

                                Button("Reset Sync State") {
                                    UserDefaults.standard.removeObject(forKey: "com.swiftcode.cloud.sync.last_sync_time")
                                }
                                .buttonStyle(.bordered)

                                Button("Delete All Cloud Data") {
                                    executeAuthAction {
                                        try await authService.deleteAccount()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
        }
    }

    private func executeAuthAction(_ action: @escaping () async throws -> Void) {
        isProcessing = true
        errorMessage = ""
        Task {
            do {
                try await action()
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}
