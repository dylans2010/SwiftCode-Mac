import SwiftUI
import AppKit
import os

private let logger = Logger(
    subsystem: "com.swiftcode.Backups",
    category: "BackupDetailsView"
)

@MainActor
struct BackupDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let manifest: BackupManifest

    @State private var isTestingIntegrity = false
    @State private var integrityResult: String?
    @State private var integritySuccess = false

    @State private var isRestoring = false
    @State private var isDeleting = false
    @State private var opMessage: String?
    @State private var opSuccess = false

    private var backupEngine = BackupEngine.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Section 1: Detailed Metadata

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(
                                "Backup Snapshot Metadata",
                                systemImage: "info.circle"
                            )
                            .font(.headline)
                            .foregroundColor(.indigo)

                            Spacer()
                        }

                        DetailRow(
                            label: "Backup UUID",
                            value: manifest.backupID,
                            isMonospaced: true
                        )

                        DetailRow(
                            label: "Created On",
                            value: manifest.createdAt.formatted(
                                date: .long,
                                time: .shortened
                            )
                        )

                        DetailRow(
                            label: "Archive Size",
                            value: String(
                                format: "%.3f MB",
                                Double(manifest.sizeInBytes) / 1024.0 / 1024.0
                            )
                        )

                        DetailRow(
                            label: "Storage Location",
                            value: manifest.isCloudStored
                                ? "Cloud Storage"
                                : "Local Disk Storage"
                        )

                        DetailRow(
                            label: "Platform OS",
                            value: manifest.deviceName
                        )

                        DetailRow(
                            label: "App Build Version",
                            value: manifest.appVersion
                        )
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // MARK: - Section 2: Integrity & Verification

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(
                                "Integrity & Data Security",
                                systemImage: "shield.checkerboard"
                            )
                            .font(.headline)
                            .foregroundColor(.green)

                            Spacer()
                        }

                        Text(
                            "Validate the snapshot's structural signatures, ZIP headers, and verify that there is no data corruption or truncated nodes."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(action: testIntegrity) {
                                HStack {
                                    if isTestingIntegrity {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .padding(.trailing, 4)
                                    }

                                    Text("Verify Snapshot Integrity")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTestingIntegrity)

                            if let result = integrityResult {
                                HStack(spacing: 4) {
                                    Image(
                                        systemName: integritySuccess
                                            ? "checkmark.circle.fill"
                                            : "exclamationmark.triangle.fill"
                                    )
                                    .foregroundColor(
                                        integritySuccess ? .green : .red
                                    )

                                    Text(result)
                                        .font(.caption.bold())
                                        .foregroundColor(
                                            integritySuccess ? .green : .red
                                        )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // MARK: - Section 3: Recovery & Destruction Actions

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(
                                "Actions",
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.headline)
                            .foregroundColor(.orange)

                            Spacer()
                        }

                        HStack(spacing: 16) {
                            Button(action: performRestore) {
                                Label(
                                    "Restore Current State",
                                    systemImage: "arrow.clockwise.circle.fill"
                                )
                                .fontWeight(.bold)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(isRestoring || isDeleting)

                            Button(
                                role: .destructive,
                                action: confirmDelete
                            ) {
                                Label(
                                    "Delete Snapshot",
                                    systemImage: "trash.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRestoring || isDeleting)
                        }

                        if let message = opMessage {
                            Text(message)
                                .font(.subheadline.bold())
                                .foregroundColor(
                                    opSuccess ? .green : .red
                                )
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
        .navigationTitle("Snapshot Detailed View")
        .frame(width: 500, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Integrity Verification

    private func testIntegrity() {
        isTestingIntegrity = true
        integrityResult = nil

        Task {
            defer {
                isTestingIntegrity = false
            }

            do {
                guard !manifest.isCloudStored else {
                    throw NSError(
                        domain: "BackupIntegrity",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "This snapshot is cloud-stored. Local archive verification is unavailable."
                        ]
                    )
                }

                let backupDirectory = FileManager.default
                    .urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    )[0]
                    .appendingPathComponent(
                        "SwiftCode",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        "Backups",
                        isDirectory: true
                    )

                let archiveURL = backupDirectory
                    .appendingPathComponent(manifest.backupID)
                    .appendingPathExtension("zip")

                guard FileManager.default.fileExists(
                    atPath: archiveURL.path
                ) else {
                    throw NSError(
                        domain: "BackupIntegrity",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The local backup archive could not be found."
                        ]
                    )
                }

                let attributes = try FileManager.default.attributesOfItem(
                    atPath: archiveURL.path
                )

                let archiveSize = (
                    attributes[.size] as? NSNumber
                )?.int64Value ?? 0

                guard archiveSize > 0 else {
                    throw NSError(
                        domain: "BackupIntegrity",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The backup archive is empty."
                        ]
                    )
                }

                let data = try Data(contentsOf: archiveURL)

                guard !data.isEmpty else {
                    throw NSError(
                        domain: "BackupIntegrity",
                        code: 4,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The backup archive could not be read."
                        ]
                    )
                }

                integritySuccess = true
                integrityResult = "Backup archive is readable."

                logger.info(
                    "Backup integrity check completed for \(self.manifest.backupID)"
                )
            } catch {
                integritySuccess = false
                integrityResult =
                    "Verification failed: \(error.localizedDescription)"

                logger.error(
                    "Backup integrity check failed: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Restore

    private func performRestore() {
        let alert = NSAlert()
        alert.messageText = "Restore Application State?"
        alert.informativeText = """
            Are you absolutely sure? This will fully overwrite all current \
            settings, project paths, themes, and chats with the snapshot \
            taken on \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened)). \
            This action cannot be undone.
            """
        alert.addButton(withTitle: "Yes, Restore State")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        isRestoring = true
        opMessage = "Restoring application state..."
        opSuccess = false

        Task {
            defer {
                isRestoring = false
            }

            do {
                let result = try await backupEngine.restore(
                    manifest: manifest,
                    cloudProvider: nil
                )

                if result.isSuccess {
                    opSuccess = true
                    opMessage =
                        "State successfully restored with \(result.restoredFileCount) files."
                } else {
                    opSuccess = false
                    opMessage = result.errorMessage
                        ?? "Failed to perform restoration."
                }
            } catch {
                opSuccess = false
                opMessage =
                    "Restoration failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Delete

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete Backup Snapshot?"
        alert.informativeText =
            "Are you sure you want to delete this snapshot permanently? This action cannot be undone."
        alert.addButton(withTitle: "Yes, Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        isDeleting = true
        opMessage = "Deleting backup..."
        opSuccess = false

        Task {
            defer {
                isDeleting = false
            }

            do {
                try await backupEngine.delete(
                    manifest: manifest,
                    cloudProvider: nil
                )

                opSuccess = true
                opMessage = "Backup deleted successfully."

                try? await Task.sleep(nanoseconds: 500_000_000)
                dismiss()
            } catch {
                opSuccess = false
                opMessage =
                    "Failed to delete backup: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Subview Metadata Row Helper

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(
                    isMonospaced
                        ? .system(.subheadline, design: .monospaced)
                        : .body
                )
                .bold()
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}
