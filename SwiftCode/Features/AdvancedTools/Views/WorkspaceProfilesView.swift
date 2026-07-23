import SwiftUI

struct WorkspaceProfilesView: View {
    @StateObject private var manager = WorkspaceProfilesManager.shared
    @Environment(\.dismiss) private var dismiss

    // UI state
    @State private var searchQuery = ""
    @State private var selectedCategory = "All"
    @State private var sortOption = "Name"
    @State private var selectedProfile: WorkspaceProfile? = nil

    // Creation/Editing fields
    @State private var showEditSheet = false
    @State private var isCreatingNew = false
    @State private var draftName = ""
    @State private var draftBuildConfiguration = "Debug"
    @State private var draftEnvironmentVariables = ""

    let categories = ["All", "Favorites", "Development", "Production", "Staging"]
    let sortOptions = ["Name", "Configuration"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Workspace Setting Profiles", systemImage: "person.crop.square.fill.and.at.rectangle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            Text("Create, edit, duplicate, and switch between customized settings and environment profiles for your projects.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Filter controls
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Filter & Sorting")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)

                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search profiles...", text: $searchQuery)
                                    .textFieldStyle(.plain)
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                            Picker("Category", selection: $selectedCategory) {
                                ForEach(categories, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Picker("Sort", selection: $sortOption) {
                                    ForEach(sortOptions, id: \.self) { Text("Sort: \($0)").tag($0) }
                                }
                                .pickerStyle(.menu)

                                Spacer()

                                Button {
                                    prepareCreate()
                                } label: {
                                    Label("Create Profile", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Profiles list inside a GroupBox
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profiles Directory")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)

                            let profiles = filteredProfiles
                            if profiles.isEmpty {
                                Text("No profiles match the filter criteria.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(profiles) { profile in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(profile.name).bold()
                                                if manager.activeProfileID == profile.id {
                                                    Text("ACTIVE")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.green.opacity(0.15))
                                                        .foregroundStyle(.green)
                                                        .cornerRadius(4)
                                                }
                                            }
                                            Text("Build: \(profile.buildConfiguration)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 8) {
                                            if manager.activeProfileID != profile.id {
                                                Button("Activate") {
                                                    manager.switchTo(profile)
                                                    selectedProfile = profile
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.small)
                                            }

                                            Button {
                                                selectedProfile = profile
                                                prepareEdit(profile)
                                            } label: {
                                                Image(systemName: "pencil")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button {
                                                duplicateProfile(profile)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button {
                                                toggleFavorite(profile)
                                            } label: {
                                                Image(systemName: profile.preferences["isFavorite"] == "true" ? "star.fill" : "star")
                                                    .foregroundStyle(profile.preferences["isFavorite"] == "true" ? .yellow : .secondary)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button(role: .destructive) {
                                                deleteProfile(profile)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(8)
                                    .background(selectedProfile?.id == profile.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)

                                    if profile.id != profiles.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Detailed panel for selected profile
                    if let profile = selectedProfile ?? manager.profiles.first(where: { $0.id == manager.activeProfileID }) ?? manager.profiles.first {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Selected Profile: \(profile.name)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.purple)

                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                    GridRow {
                                        Text("Profile ID:")
                                            .foregroundStyle(.secondary)
                                        Text(profile.id.uuidString).font(.caption.monospaced())
                                    }
                                    GridRow {
                                        Text("Build Configuration:")
                                            .foregroundStyle(.secondary)
                                        Text(profile.buildConfiguration)
                                    }
                                }

                                Divider()

                                Text("Environment Variables")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                if profile.environmentVariables.isEmpty {
                                    Text("No environment variables defined.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(profile.environmentVariables.keys).sorted(), id: \.self) { key in
                                        HStack {
                                            Text(key).bold().font(.caption.monospaced())
                                            Spacer()
                                            Text(profile.environmentVariables[key] ?? "")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Workspace Profiles")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                editProfileSheet
            }
        }
    }

    // MARK: - Sheets & Wizards

    private var editProfileSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isCreatingNew ? "Create Profile" : "Edit Profile")
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
                            Text("Profile Name").bold()
                            TextField("Name", text: $draftName)
                                .textFieldStyle(.roundedBorder)

                            Text("Build Configuration").bold()
                            TextField("Build Config (e.g. Debug, Release)", text: $draftBuildConfiguration)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Environment Variables").bold()
                            Text("Enter key-value pairs separated by equals sign, one per line (e.g. KEY=VALUE)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("KEY=VALUE", text: $draftEnvironmentVariables, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .frame(height: 100)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.isEmpty)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 420)
    }

    // MARK: - Operations

    private var filteredProfiles: [WorkspaceProfile] {
        var list = manager.profiles

        if !searchQuery.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
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
            list.sort { $0.name < $1.name }
        case "Configuration":
            list.sort { $0.buildConfiguration < $1.buildConfiguration }
        default:
            break
        }

        return list
    }

    private func prepareCreate() {
        draftName = ""
        draftBuildConfiguration = "Debug"
        draftEnvironmentVariables = ""
        isCreatingNew = true
        showEditSheet = true
    }

    private func prepareEdit(_ profile: WorkspaceProfile) {
        draftName = profile.name
        draftBuildConfiguration = profile.buildConfiguration
        draftEnvironmentVariables = profile.environmentVariables.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        isCreatingNew = false
        showEditSheet = true
    }

    private func saveProfile() {
        var env: [String: String] = [:]
        let lines = draftEnvironmentVariables.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                env[String(parts[0])] = String(parts[1])
            }
        }

        if isCreatingNew {
            let newProfile = WorkspaceProfile(
                id: UUID(),
                name: draftName,
                buildConfiguration: draftBuildConfiguration,
                environmentVariables: env,
                preferences: [:]
            )
            manager.add(newProfile)
            selectedProfile = newProfile
        } else if let original = selectedProfile {
            var updated = original
            updated.name = draftName
            updated.buildConfiguration = draftBuildConfiguration
            updated.environmentVariables = env

            manager.delete(original)
            manager.add(updated)
            selectedProfile = updated
        }

        showEditSheet = false
    }

    private func duplicateProfile(_ profile: WorkspaceProfile) {
        let copy = WorkspaceProfile(
            id: UUID(),
            name: "\(profile.name) Copy",
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
        updated.preferences["isFavorite"] = (!current).description

        manager.delete(profile)
        manager.add(updated)
        selectedProfile = updated
    }

    private func deleteProfile(_ profile: WorkspaceProfile) {
        manager.delete(profile)
        if selectedProfile?.id == profile.id {
            selectedProfile = nil
        }
    }
}
