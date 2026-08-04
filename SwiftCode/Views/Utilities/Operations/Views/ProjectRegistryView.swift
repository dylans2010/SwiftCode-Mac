import SwiftUI

struct ProjectRegistryView: View {
    @State private var registry = ProjectRegistryManager.shared
    @State private var coord = OperationsCoordinator.shared
    @State private var selectedEntry: SCProjectRegistryEntry? = nil
    @State private var showDeleteAlert = false
    @State private var entryToDelete: SCProjectRegistryEntry? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Main List of Projects
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project Registry")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("All known SwiftCode projects and workspaces.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        registry.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)

                Divider()

                if registry.registryEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Registered Projects", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Open or create a new project in the workspace to see it registered here.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(registry.registryEntries, selection: $selectedEntry) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.headline)
                                Text(entry.rootURL.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(entry.buildStatus)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                        .tag(entry)
                        .contextMenu {
                            Button("Open Project") {
                                registry.openProject(entry)
                            }
                            Button("Reveal in Finder") {
                                registry.revealInFinder(entry)
                            }
                            Button("Duplicate") {
                                try? registry.duplicateProject(entry)
                            }
                            Button("Create Backup") {
                                BackupIntegration.shared.createBackup(for: entry)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                entryToDelete = entry
                                showDeleteAlert = true
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Split Details Inspector (embedded inline ProjectDetailView)
            if let selected = selectedEntry {
                Divider()
                ProjectDetailView(entry: selected) {
                    registry.refresh()
                    selectedEntry = nil
                }
                .frame(width: 320)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .alert("Confirm Delete", isPresented: $showDeleteAlert) {
            Button("Delete Project & Files", role: .destructive) {
                if let entry = entryToDelete {
                    try? registry.deleteProject(entry)
                    registry.refresh()
                    selectedEntry = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to permanently delete '\(entryToDelete?.name ?? "")' from disk? This cannot be undone.")
        }
        .onAppear {
            registry.refresh()
        }
    }
}

struct ProjectDetailView: View {
    let entry: SCProjectRegistryEntry
    let onModified: () -> Void

    @State private var isBackingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(entry.description.isEmpty ? "No description provided." : entry.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    SCDetailRow(label: "Swift Version", value: entry.swiftVersion)
                    SCDetailRow(label: "Package Config", value: entry.packageStatus)
                    SCDetailRow(label: "Git Repository", value: entry.gitStatus)
                    SCDetailRow(label: "Last Opened", value: formatDate(entry.lastOpened))
                }

                Divider()

                VStack(spacing: 8) {
                    Button {
                        ProjectRegistryManager.shared.openProject(entry)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Open in Workspace")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        ProjectRegistryManager.shared.revealInFinder(entry)
                    } label: {
                        HStack {
                            Image(systemName: "macwindow")
                            Text("Reveal in Finder")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        try? ProjectRegistryManager.shared.duplicateProject(entry)
                        onModified()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Duplicate Project")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        isBackingUp = true
                        BackupIntegration.shared.createBackup(for: entry)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isBackingUp = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.icloud")
                            Text(isBackingUp ? "Backing up..." : "Backup Archive")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBackingUp)
                }
            }
            .padding(16)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

struct SCDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
