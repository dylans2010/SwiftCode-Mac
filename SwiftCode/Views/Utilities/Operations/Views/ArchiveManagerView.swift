import SwiftUI

struct ArchiveManagerView: View {
    @State private var am = ArchiveManager.shared
    @State private var selectedArchive: SCArchive? = nil
    @State private var showExportPanel = false
    @State private var exportLocation = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Archive Manager")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Compiled app archives, signatures, and releases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        if let active = ProjectSessionStore.shared.activeProject {
                            am.addArchive(projectName: active.name, version: "1.0.0", buildNumber: "1")
                        }
                    } label: {
                        Label("Archive Active Target", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ProjectSessionStore.shared.activeProject == nil)
                }
                .padding(16)

                Divider()

                if am.archives.isEmpty {
                    ContentUnavailableView {
                        Label("No Archives Found", systemImage: "archivebox")
                    } description: {
                        Text("Create a release archive of your active project to bundle resources and prepare binary releases.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(am.archives, selection: $selectedArchive) { archive in
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(archive.projectName)
                                    .font(.headline)
                                Text("v\(archive.version) (\(archive.buildNumber)) • \(formatSize(archive.binarySize))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(archive.configuration)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 4)
                        .tag(archive)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let archive = selectedArchive {
                Divider()
                ArchiveDetailView(archive: archive) {
                    am.deleteArchive(archive)
                    selectedArchive = nil
                }
                .frame(width: 320)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ArchiveDetailView: View {
    let archive: SCArchive
    let onDelete: () -> Void

    @State private var isExporting = false
    @State private var showReleaseNotesSheet = false
    @State private var notesText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "shippingbox")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(archive.projectName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Build v\(archive.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Archive Info")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    SCDetailRow(label: "Build Number", value: archive.buildNumber)
                    SCDetailRow(label: "Configuration", value: archive.configuration)
                    SCDetailRow(label: "Commit", value: archive.commit)
                    SCDetailRow(label: "Symbols", value: archive.symbolsAvailable ? "Included" : "None")
                    SCDetailRow(label: "Size", value: formatSize(archive.binarySize))
                }

                if !archive.releaseNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Release Notes")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text(archive.releaseNotes)
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    Button {
                        exportArchive()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(isExporting ? "Exporting..." : "Distribute / Export App")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)

                    Button {
                        notesText = archive.releaseNotes
                        showReleaseNotesSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("Edit Release Notes")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Archive")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showReleaseNotesSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Release Notes")
                    .font(.headline)

                TextEditor(text: $notesText)
                    .frame(height: 120)
                    .cornerRadius(4)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showReleaseNotesSheet = false
                    }
                    Button("Save") {
                        if var updated = ArchiveManager.shared.archives.first(where: { $0.id == archive.id }) {
                            updated.releaseNotes = notesText
                            if let idx = ArchiveManager.shared.archives.firstIndex(where: { $0.id == archive.id }) {
                                ArchiveManager.shared.archives[idx] = updated
                                ArchiveManager.shared.saveArchives()
                            }
                        }
                        showReleaseNotesSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 350)
        }
    }

    private func exportArchive() {
        isExporting = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.application]
        panel.nameFieldStringValue = "\(archive.projectName).app"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? "App Binary Placeholder".write(to: url, atomically: true, encoding: .utf8)
            }
            isExporting = false
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
