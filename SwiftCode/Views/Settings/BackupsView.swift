import SwiftUI

@Observable
@MainActor
class BackupsViewState {
    var searchQuery: String = ""
    var selectedSort: String = "Date"
    var filterProvider: CloudProviderType = .none // None represents all providers
    var showCreateSheet: Bool = false
    var showDetailsSheet: Bool = false
    var selectedBackupID: UUID? = nil
    var backupNameInput: String = ""
    var activeBackupProvider: CloudProviderType = .supabase

    // Retention policy settings
    var retentionPolicyDays: Int = 30
    var compressBackups: Bool = true
    var encryptBackups: Bool = true
}

public struct BackupsView: View {
    @State private var state = BackupsViewState()
    @State private var backupManager = BackupManager.shared

    public init() {}

    private var filteredBackups: [BackupMetadata] {
        var list = backupManager.backups

        // Search Filter
        if !state.searchQuery.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(state.searchQuery) }
        }

        // Provider Filter
        if state.filterProvider != .none {
            list = list.filter { $0.providerType == state.filterProvider }
        }

        // Sorting
        if state.selectedSort == "Date" {
            list.sort { $0.createdAt > $1.createdAt }
        } else if state.selectedSort == "Size" {
            list.sort { $0.sizeBytes > $1.sizeBytes }
        } else {
            list.sort { $0.name < $1.name }
        }

        return list
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // General Info and Stats
            GroupBox(label: Label("Backup Overview", systemImage: "archivebox.fill")) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        VStack(alignment: .leading) {
                            Text("Total Snapshots")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(backupManager.backups.count) Backups")
                                .font(.title3.bold())
                        }

                        VStack(alignment: .leading) {
                            Text("Last Backup Completed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let last = backupManager.lastBackupDate {
                                Text(last, style: .time)
                                    .font(.title3.bold())
                            } else {
                                Text("Never")
                                    .font(.title3.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Storage Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Multi-Destination")
                                .font(.title3.bold())
                        }
                    }
                }
                .padding(8)
            }

            // Filters and Search Toolbar
            HStack(spacing: 12) {
                TextField("Search backups...", text: $state.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Picker("Provider:", selection: $state.filterProvider) {
                    Text("All Providers").tag(CloudProviderType.none)
                    Text("Supabase").tag(CloudProviderType.supabase)
                    Text("iCloud").tag(CloudProviderType.icloud)
                }
                .frame(width: 160)

                Picker("Sort By:", selection: $state.selectedSort) {
                    Text("Date").tag("Date")
                    Text("Size").tag("Size")
                    Text("Name").tag("Name")
                }
                .frame(width: 140)

                Spacer()

                Button(action: {
                    state.backupNameInput = "Manual Backup \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
                    state.showCreateSheet = true
                }) {
                    Label("Create Backup...", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            // Backup list table
            VStack {
                if filteredBackups.isEmpty {
                    ContentUnavailableView("No backups matching your criteria", systemImage: "doc.text.magnifyingglass")
                        .frame(height: 200)
                } else {
                    List(filteredBackups) { backup in
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: backup.providerType == .supabase ? "icloud.and.arrow.up" : "icloud")
                                    .foregroundColor(.blue)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.name)
                                    .font(.headline)
                                HStack(spacing: 12) {
                                    Text(backup.providerType.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(backup.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Actions...") {
                                state.selectedBackupID = backup.id
                                state.showDetailsSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                    .frame(height: 250)
                }
            }

            // Retention and Configuration details
            GroupBox(label: Label("Automated Schedule & Retention Policy", systemImage: "calendar.badge.clock")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Automated Backup Schedule", isOn: $backupManager.automaticBackupsEnabled)
                        .toggleStyle(.checkbox)

                    if backupManager.automaticBackupsEnabled {
                        HStack {
                            Picker("Frequency:", selection: $backupManager.backupInterval) {
                                Text("Hourly").tag("Hourly")
                                Text("Daily").tag("Daily")
                                Text("Weekly").tag("Weekly")
                                Text("Monthly").tag("Monthly")
                            }
                            .frame(width: 180)

                            Spacer()

                            Stepper("Keep backups for: \(state.retentionPolicyDays) days", value: $state.retentionPolicyDays, in: 7...180)
                        }
                    }

                    HStack(spacing: 16) {
                        Toggle("Compress Backup Archives", isOn: $state.compressBackups)
                            .toggleStyle(.checkbox)
                        Toggle("Encrypt Backup Files", isOn: $state.encryptBackups)
                            .toggleStyle(.checkbox)
                    }
                }
                .padding(8)
            }
        }
        .sheet(isPresented: $state.showCreateSheet) {
            // New Backup Creator Sheet
            VStack(spacing: 20) {
                Text("Create Local/Cloud Backup")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Backup Name", text: $state.backupNameInput)
                        .textFieldStyle(.roundedBorder)

                    Picker("Destination Provider:", selection: $state.activeBackupProvider) {
                        Text("Supabase Cloud").tag(CloudProviderType.supabase)
                        Text("Apple iCloud").tag(CloudProviderType.icloud)
                    }
                }
                .padding()

                HStack {
                    Button("Cancel") {
                        state.showCreateSheet = false
                    }
                    .buttonStyle(.bordered)

                    Button("Create") {
                        Task {
                            try? await backupManager.createBackup(name: state.backupNameInput, provider: state.activeBackupProvider)
                            state.showCreateSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 400, height: 220)
        }
        .sheet(isPresented: $state.showDetailsSheet) {
            if let backupID = state.selectedBackupID,
               let backup = backupManager.backups.first(where: { $0.id == backupID }) {
                BackupDetailsView(backup: backup) {
                    state.showDetailsSheet = false
                }
                .frame(width: 600, height: 450)
            }
        }
    }
}
