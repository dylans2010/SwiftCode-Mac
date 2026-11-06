import Foundation
import SwiftUI
import SwiftCodeCloud

// Backups settings, adapted from Legacy's `SwiftCode/Views/Settings/`
// (`BackupsView`, `BackupDetailsView`, `CreateBackupView`) onto SwiftCode's
// `BackupEngine` (`SwiftCodeCloud/BackupEngine.swift`, gap-closure port of
// Legacy's `Frameworks/Internal/Backups/Engine/BackupEngine.swift`).
// Local backups only in this view: listing, creating, restoring and
// deleting local ZIP snapshots. Cloud upload needs an authenticated
// Appwrite session, which lives in the Accounts pane
// (`CloudAccountsSettings.swift`); restore erases the current local
// application state exactly as Legacy did, so it asks for confirmation
// first and there is no undo.

/// List, create, restore and delete local backup snapshots.
@MainActor
struct BackupsSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var manifests: [BackupManifest] = []
    @State private var selected: BackupManifest?
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingRestoreConfirm = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Backups").font(ShellFonts.rowBold)
                Spacer()
                Button("Create Backup") { createBackup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                Button("Refresh") { reload() }
                    .disabled(isWorking)
            }
            .padding(10)
            if let statusMessage {
                Text(verbatim: statusMessage)
                    .font(ShellFonts.small)
                    .foregroundStyle(statusIsError ? .red : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Hairline(color: c.separator)
            if manifests.isEmpty {
                ContentUnavailableView(
                    "No backups yet",
                    systemImage: "externaldrive",
                    description: Text("Create a backup to capture a point-in-time snapshot of local application state. Snapshots are ZIP archives in Application Support.")
                )
            } else {
                // No List(selection:) here: BackupManifest (SwiftCodeCloud)
                // is Equatable but not Hashable, so selection is set
                // by tapping a row instead of a selection binding.
                List {
                    ForEach(manifests) { manifest in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: manifest.filename).font(ShellFonts.rowBold)
                            Text(verbatim: "\(manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: manifest.sizeInBytes, countStyle: .file)) · \(manifest.deviceName)")
                                .font(ShellFonts.small)
                                .foregroundStyle(c.secondaryLabel)
                            Text(verbatim: manifest.isCloudStored ? "Stored in cloud" : "Local only")
                                .font(ShellFonts.mini)
                                .foregroundStyle(c.tertiaryLabel)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = manifest }
                        .contextMenu {
                            Button("Restore…") {
                                selected = manifest
                                showingRestoreConfirm = true
                            }
                            Button("Delete", role: .destructive) {
                                selected = manifest
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            if let manifest = selected {
                Hairline(color: c.separator)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup details").font(ShellFonts.rowBold)
                    detailRow(label: "File", value: manifest.filename, colors: c)
                    detailRow(label: "Created", value: manifest.createdAt.formatted(date: .complete, time: .shortened), colors: c)
                    detailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: manifest.sizeInBytes, countStyle: .file), colors: c)
                    detailRow(label: "Device", value: manifest.deviceName, colors: c)
                    detailRow(label: "App version", value: manifest.appVersion, colors: c)
                    detailRow(label: "Location", value: manifest.isCloudStored ? "Cloud backups bucket" : "Local backups folder", colors: c)
                    HStack {
                        Button("Restore…") { showingRestoreConfirm = true }
                            .disabled(isWorking)
                        Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                            .disabled(isWorking)
                        Spacer()
                        Text("Restore erases the current local application state before extracting. There is no undo.")
                            .font(ShellFonts.mini)
                            .foregroundStyle(c.tertiaryLabel)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(10)
            }
        }
        .onAppear { reload() }
        .alert("Restore this backup?", isPresented: $showingRestoreConfirm, presenting: selected) { manifest in
            Button("Restore", role: .destructive) { restore(manifest) }
            Button("Cancel", role: .cancel) {}
        } message: { manifest in
            Text("Restoring \(manifest.filename) erases the current local application state and replaces it with the snapshot. This cannot be undone.")
        }
        .alert("Delete this backup?", isPresented: $showingDeleteConfirm, presenting: selected) { manifest in
            Button("Delete", role: .destructive) { deleteBackup(manifest) }
            Button("Cancel", role: .cancel) {}
        } message: { manifest in
            Text("Delete \(manifest.filename)? This cannot be undone.")
        }
    }

    private func detailRow(label: String, value: String, colors c: ShellColors) -> some View {
        HStack {
            Text(verbatim: label).font(ShellFonts.small).foregroundStyle(c.secondaryLabel).frame(width: 90, alignment: .leading)
            Text(verbatim: value).font(ShellFonts.small)
            Spacer()
        }
    }

    private func reload() {
        BackupEngine.shared.loadLocalBackups()
        manifests = BackupEngine.shared.backups
        if let selected, !manifests.contains(selected) {
            self.selected = nil
        }
    }

    private func createBackup() {
        isWorking = true
        statusIsError = false
        Task {
            do {
                try await BackupEngine.shared.performBackup()
                statusMessage = "Backup created."
                reload()
            } catch {
                statusIsError = true
                statusMessage = "Backup failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func restore(_ manifest: BackupManifest) {
        isWorking = true
        statusIsError = false
        Task {
            do {
                _ = try await BackupEngine.shared.restore(manifest: manifest)
                statusMessage = "Backup restored."
                reload()
            } catch {
                statusIsError = true
                statusMessage = "Restore failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func deleteBackup(_ manifest: BackupManifest) {
        isWorking = true
        statusIsError = false
        Task {
            do {
                try await BackupEngine.shared.delete(manifest: manifest)
                statusMessage = "Backup deleted."
                selected = nil
                reload()
            } catch {
                statusIsError = true
                statusMessage = "Delete failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }
}
