import SwiftUI
import os

private let logger = Logger(
    subsystem: "com.swiftcode.Backups",
    category: "CreateBackupView"
)

@MainActor
struct CreateBackupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var notes = ""
    @State private var isCreating = false
    @State private var progress: Double = 0.0
    @State private var status = "Ready to start snapshot"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "Create a new point-in-time snapshot of the active workspace. This includes projects list, templates, preferences, and cached chats."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local Storage")
                                .font(.body.bold())

                            Text(
                                "Your backup will be stored locally on this Mac."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Storage Strategy")
                }

                Section {
                    TextField(
                        "Backup Description / Label (Optional)",
                        text: $notes
                    )
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
                            Image(
                                systemName: "exclamationmark.octagon.fill"
                            )
                            .foregroundColor(.red)

                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption.bold())
                        }
                    }
                }

                Section {
                    Button(action: startBackup) {
                        Text(
                            isCreating
                                ? "Processing Backup..."
                                : "Start Snapshot Backup"
                        )
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
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
        }
        .frame(width: 440, height: 420)
    }

    // MARK: - Create Backup

    private func startBackup() {
        guard !isCreating else { return }

        isCreating = true
        errorMessage = nil
        progress = 0.0
        status = "Gathering files and archiving..."

        Task {
            do {
                progress = 0.2

                // Create a local backup without a cloud provider.
                try await BackupEngine.shared.performBackup(
                    cloudProvider: nil
                )

                progress = 1.0
                status = "Backup snapshot fully completed!"

                try? await Task.sleep(nanoseconds: 500_000_000)

                dismiss()
            } catch {
                errorMessage = error.localizedDescription

                logger.error(
                    "Failed to perform snapshot: \(error.localizedDescription)"
                )
            }

            isCreating = false
        }
    }
}
