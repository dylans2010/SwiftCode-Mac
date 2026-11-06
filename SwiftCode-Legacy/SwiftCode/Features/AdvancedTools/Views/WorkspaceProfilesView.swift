import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Export document

private struct ProfilesExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var payload: Data

    init(profiles: [WorkspaceProfile]) {
        payload = (try? JSONEncoder().encode(profiles)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        payload = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: payload)
    }
}

// MARK: - View

struct WorkspaceProfilesView: View {
    @State private var manager = WorkspaceProfilesManager.shared
    @Environment(\.dismiss) private var dismiss

    // Filter state
    @State private var searchQuery = ""
    @State private var selectedCategory = "All"
    @State private var sortOption = "Name"
    @State private var selectedProfile: WorkspaceProfile? = nil

    // Create / edit sheet state
    @State private var showEditSheet = false
    @State private var isCreatingNew = false
    @State private var draftName = ""
    @State private var draftBuildConfiguration = "Debug"
    @State private var draftEnvironmentVariables = ""
    @State private var draftIsFavorite = false

    // Import / export state
    @State private var isImporting = false
    @State private var exportDocument: ProfilesExportDocument? = nil
    @State private var isExporting = false
    @State private var importError = false

    // Delete confirmation
    @State private var profilePendingDelete: WorkspaceProfile? = nil

    let categories = ["All", "Favorites", "Development", "Production", "Staging"]
    let sortOptions = ["Name", "Recently used", "Configuration"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerCard
                    filterCard
                    profilesCard
                    detailCard
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Workspace profiles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button {
                            isImporting = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportDocument = ProfilesExportDocument(profiles: manager.profiles)
                            isExporting = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(manager.profiles.isEmpty)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                editProfileSheet
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    importProfiles(from: url)
                case .failure:
                    importError = true
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "workspace-profiles.json"
            ) { _ in }
            .confirmationDialog(
                "Delete profile",
                isPresented: Binding(
                    get: { profilePendingDelete != nil },
                    set: { if !$0 { profilePendingDelete = nil } }
                ),
                presenting: profilePendingDelete
            ) { profile in
                Button("Delete", role: .destructive) {
                    deleteProfile(profile)
                    profilePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    profilePendingDelete = nil
                }
            } message: { profile in
                Text("Delete the profile \"\(profile.name)\"? This can't be undone.")
            }
            .alert("Couldn't import profiles", isPresented: $importError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The selected file doesn't contain valid workspace profile JSON.")
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Workspace profiles", systemImage: "square.stack.3d.up")
                    .font(.headline)
                Text("Create, edit, duplicate, and switch between customized settings and environment profiles for your projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var filterCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filter and sorting")
                    .font(.subheadline.bold())

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search profiles", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(sortOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button {
                        prepareCreate()
                    } label: {
                        Label("Create profile", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var profilesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Profiles")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(filteredProfiles.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if manager.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No profiles yet", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("Create a profile to save a build configuration and environment variables you can switch between.")
                    } actions: {
                        Button("Create profile") {
                            prepareCreate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredProfiles.isEmpty {
                    Text("No profiles match these filters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredProfiles) { profile in
                            profileRow(profile)

                            if profile.id != filteredProfiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func profileRow(_ profile: WorkspaceProfile) -> some View {
        let isActive = manager.activeProfileID == profile.id
        let isSelected = selectedProfile?.id == profile.id
        let isFavorite = profile.preferences["isFavorite"] == "true"

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(profile.name)
                        .bold()
                        .lineLimit(nil)
                    if isActive {
                        Text("Active")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(contentsSummary(for: profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if !isActive {
                    Button("Activate") {
                        manager.switchTo(profile)
                        selectedProfile = profile
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    prepareEdit(profile)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rename")

                Button {
                    duplicateProfile(profile)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Duplicate")

                Button {
                    toggleFavorite(profile)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle favorite")

                Button(role: .destructive) {
                    profilePendingDelete = profile
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete")
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProfile = profile
        }
    }

    @ViewBuilder
    private var detailCard: some View {
        if let profile = selectedProfile ?? manager.profiles.first(where: { $0.id == manager.activeProfileID }) ?? manager.profiles.first {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text(profile.name)
                        .font(.subheadline.bold())
                        .lineLimit(nil)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Build configuration")
                                .foregroundStyle(.secondary)
                            Text(profile.buildConfiguration)
                                .lineLimit(nil)
                        }
                        if let lastUsed = profile.lastUsed {
                            GridRow {
                                Text("Last used")
                                    .foregroundStyle(.secondary)
                                Text(lastUsed, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        GridRow {
                            Text("Profile ID")
                                .foregroundStyle(.secondary)
                            Text(profile.id.uuidString)
                                .font(.caption.monospaced())
                                .lineLimit(nil)
                                .textSelection(.enabled)
                        }
                    }
                    .font(.caption)

                    Divider()

                    HStack {
                        Text("Environment variables")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !profile.environmentVariables.isEmpty {
                            Button("Copy all") {
                                let text = profile.environmentVariables
                                    .sorted(by: { $0.key < $1.key })
                                    .map { "\($0.key)=\($0.value)" }
                                    .joined(separator: "\n")
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if profile.environmentVariables.isEmpty {
                        Text("No environment variables defined.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(profile.environmentVariables.keys.sorted(), id: \.self) { key in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key)
                                        .font(.caption.monospaced())
                                        .bold()
                                        .lineLimit(nil)
                                    Text(profile.environmentVariables[key] ?? "")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(nil)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    // MARK: - Create / edit sheet

    private var editProfileSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isCreatingNew ? "Create profile" : "Rename profile")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showEditSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profile name").bold()
                            TextField("Name", text: $draftName)
                                .textFieldStyle(.roundedBorder)

                            Text("Build configuration").bold()
                            TextField("Build configuration (e.g. Debug, Release)", text: $draftBuildConfiguration)
                                .textFieldStyle(.roundedBorder)

                            Toggle("Favorite", isOn: $draftIsFavorite)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Environment variables").bold()
                            Text("Enter key-value pairs separated by an equals sign, one per line (e.g. KEY=VALUE).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)

                            TextEditor(text: $draftEnvironmentVariables)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 100)
                                .padding(4)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    Button("Save profile") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
        }
        .frame(minWidth: 460, minHeight: 440)
    }

    // MARK: - Filtering & summaries

    private var filteredProfiles: [WorkspaceProfile] {
        var list = manager.profiles

        if !searchQuery.isEmpty {
            let query = searchQuery
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.buildConfiguration.localizedCaseInsensitiveContains(query) ||
                $0.environmentVariables.keys.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }

        switch selectedCategory {
        case "Favorites":
            list = list.filter { $0.preferences["isFavorite"] == "true" }
        case "Development":
            list = list.filter { $0.buildConfiguration.localizedCaseInsensitiveContains("debug") }
        case "Production":
            list = list.filter { $0.buildConfiguration.localizedCaseInsensitiveContains("release") }
        case "Staging":
            list = list.filter { $0.buildConfiguration.localizedCaseInsensitiveContains("stage") }
        default:
            break
        }

        switch sortOption {
        case "Name":
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "Recently used":
            list.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        case "Configuration":
            list.sort { $0.buildConfiguration.localizedCaseInsensitiveCompare($1.buildConfiguration) == .orderedAscending }
        default:
            break
        }

        return list
    }

    private func contentsSummary(for profile: WorkspaceProfile) -> String {
        var parts: [String] = []
        parts.append("Build: \(profile.buildConfiguration)")
        let envCount = profile.environmentVariables.count
        parts.append(envCount == 1 ? "1 environment variable" : "\(envCount) environment variables")
        if let lastUsed = profile.lastUsed {
            let relative = RelativeDateTimeFormatter().localizedString(for: lastUsed, relativeTo: Date())
            parts.append("Last used \(relative)")
        } else {
            parts.append("Never used")
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Operations

    private func prepareCreate() {
        draftName = ""
        draftBuildConfiguration = "Debug"
        draftEnvironmentVariables = ""
        draftIsFavorite = false
        isCreatingNew = true
        showEditSheet = true
    }

    private func prepareEdit(_ profile: WorkspaceProfile) {
        selectedProfile = profile
        draftName = profile.name
        draftBuildConfiguration = profile.buildConfiguration
        draftEnvironmentVariables = profile.environmentVariables
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        draftIsFavorite = profile.preferences["isFavorite"] == "true"
        isCreatingNew = false
        showEditSheet = true
    }

    private func saveProfile() {
        var env: [String: String] = [:]
        for line in draftEnvironmentVariables.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    env[key] = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        let name = draftName.trimmingCharacters(in: .whitespaces)

        if isCreatingNew {
            let newProfile = WorkspaceProfile(
                id: UUID(),
                name: name,
                buildConfiguration: draftBuildConfiguration,
                environmentVariables: env,
                preferences: draftIsFavorite ? ["isFavorite": "true"] : [:]
            )
            manager.add(newProfile)
            selectedProfile = newProfile
        } else if let original = selectedProfile {
            var updated = original
            updated.name = name
            updated.buildConfiguration = draftBuildConfiguration
            updated.environmentVariables = env
            updated.preferences["isFavorite"] = draftIsFavorite ? "true" : nil
            manager.update(updated)
            selectedProfile = updated
        }

        showEditSheet = false
    }

    private func duplicateProfile(_ profile: WorkspaceProfile) {
        let copy = WorkspaceProfile(
            id: UUID(),
            name: "\(profile.name) copy",
            buildConfiguration: profile.buildConfiguration,
            environmentVariables: profile.environmentVariables,
            preferences: profile.preferences
        )
        manager.add(copy)
        selectedProfile = copy
    }

    private func toggleFavorite(_ profile: WorkspaceProfile) {
        var updated = profile
        let current = profile.preferences["isFavorite"] == "true"
        updated.preferences["isFavorite"] = current ? nil : "true"
        manager.update(updated)
        if selectedProfile?.id == profile.id {
            selectedProfile = updated
        }
    }

    private func deleteProfile(_ profile: WorkspaceProfile) {
        manager.delete(profile)
        if selectedProfile?.id == profile.id {
            selectedProfile = nil
        }
    }

    // MARK: - Import / export

    private func importProfiles(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            importError = true
            return
        }
        importProfiles(from: data)
    }

    private func importProfiles(from data: Data) {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([WorkspaceProfile].self, from: data) {
            mergeImportedProfiles(decoded)
        } else if let single = try? decoder.decode(WorkspaceProfile.self, from: data) {
            mergeImportedProfiles([single])
        } else {
            importError = true
        }
    }

    private func mergeImportedProfiles(_ imported: [WorkspaceProfile]) {
        for profile in imported {
            if manager.profiles.contains(where: { $0.id == profile.id }) {
                manager.update(profile)
            } else {
                manager.add(profile)
            }
        }
    }
}
