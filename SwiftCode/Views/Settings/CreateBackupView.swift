import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.Backups", category: "CreateBackupView")

@MainActor
struct CreateBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var includeCloud = true
    @State private var notes = ""
    @State private var isCreating = false
    @State private var progress: Double = 0.0
    @State private var status: String = "Ready to start snapshot"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create a new point-in-time snapshot of the active workspace. This includes projects list, templates, preferences, and cached chats.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: $includeCloud) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Store Securely in Supabase Cloud")
                                .font(.body.bold())
                            Text("Your backup will be encrypted and uploaded to Supabase Storage bucket under your own isolated directory.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!AuthManager.shared.isAuthenticated)

                    if !AuthManager.shared.isAuthenticated {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Sign in to Appwrite first to enable Supabase Cloud Storage backups.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("Storage Strategy")
                }

                Section {
                    TextField("Backup Description / Label (Optional)", text: $notes)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Description")
                }

                if isCreating {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(status)
                                .font(.subheadline.bold())
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text("\(Int(progress * 100))% Completed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption.bold())
                        }
                    }
                }

                Section {
                    Button(action: startBackup) {
                        Text(isCreating ? "Processing Backup..." : "Start Snapshot Backup")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Snapshot Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 440, height: 420)
    }

    private func startBackup() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let provider = includeCloud ? SupabaseCloudProvider(
                    url: URL(string: "https://secctbuzkfbketdihzui.supabase.co")!,
                    apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlY2N0YnV6a2Zia2V0ZGloenVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDcxMDUwMDAsImV4cCI6MjAyNjg2MTAwMH0.mock-key-signature"
                ) : nil

                // Set up progress tracking listener from engine
                status = "Gathering files and archiving..."
                progress = 0.2

                try await BackupEngine.shared.performBackup(cloudProvider: provider)

                progress = 1.0
                status = "Backup snapshot fully completed!"

                // Allow user to see 100% complete for a short delay
                try? await Task.sleep(nanoseconds: 500_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                logger.error("Failed to perform snapshot: \(error.localizedDescription)")
            }
            isCreating = false
        }
    }
}
