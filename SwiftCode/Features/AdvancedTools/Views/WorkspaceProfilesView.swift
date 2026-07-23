import SwiftUI

struct WorkspaceProfilesView: View {
    @StateObject private var manager = WorkspaceProfilesManager.shared

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
    let sortOptions = ["Name", "Configuration", "Recently Used"]

    var body: some View {
        NavigationStack {
            HSplitView {
                // Sidebar: List & Search
                VStack(spacing: 0) {
                    // Header search and filters
                    VStack(spacing: 8) {
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
                        .pickerStyle(.menu)

                        HStack {
                            Picker("Sort", selection: $sortOption) {
                                ForEach(sortOptions, id: \.self) { Text("Sort: \($0)").tag($0) }
                            }
                            .pickerStyle(.menu)

                            Spacer()

                            Button {
                                prepareCreate()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)

                    Divider()

                    // List of profiles
                    if filteredProfiles.isEmpty {
                        ContentUnavailableView("No Profiles", systemImage: "person.crop.square")
                            .frame(maxHeight: .infinity)
                    } else {
                        List(filteredProfiles, selection: $selectedProfile) { profile in
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
                                if profile.preferences["isFavorite"] as? Bool ?? false {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .tag(profile)
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 350)

                // Content: Details panel
                Group {
                    if let profile = selectedProfile {
                        profileDetailsPanel(profile)
                    } else {
                        ContentUnavailableView("Select a Profile", systemImage: "person.crop.square")
                    }
                }
                .frame(minWidth: 350)
            }
            .navigationTitle("Workspace Profiles")
            .sheet(isPresented: $showEditSheet) {
                editProfileSheet
            }
        }
    }

    // MARK: - Details Panel

    private func profileDetailsPanel(_ profile: WorkspaceProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.title2.bold())
                        Text("Build Configuration: \(profile.buildConfiguration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if manager.activeProfileID != profile.id {
                        Button("Activate Profile") {
                            manager.switchTo(profile)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Divider()

                // Specifications Panel
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Profile Parameters", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Profile ID:")
                                    .foregroundStyle(.secondary)
                                Text(profile.id.uuidString).font(.caption.monospaced())
                            }
                            GridRow {
                                Text("Build configuration:")
                                    .foregroundStyle(.secondary)
                                Text(profile.buildConfiguration)
                            }
                        }
                    }
                    .padding(6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Environment Variables
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Environment Variables", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundColor(.blue)

                        if profile.environmentVariables.isEmpty {
                            Text("No environment variables defined.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(profile.environmentVariables.keys).sorted(), id: \.self) { key in
                                HStack {
                                    Text(key).bold()
                                    Spacer()
                                    Text(profile.environmentVariables[key] ?? "")
                                        .font(.caption.monospaced())
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Quick Actions
                HStack(spacing: 8) {
                    Button("Edit Profile") {
                        prepareEdit(profile)
                    }
                    .buttonStyle(.bordered)

                    Button("Duplicate") {
                        duplicateProfile(profile)
                    }
                    .buttonStyle(.bordered)

                    Button(profile.preferences["isFavorite"] as? Bool ?? false ? "Unfavorite" : "Favorite") {
                        toggleFavorite(profile)
                    }
                    .buttonStyle(.bordered)

                    Button("Export Profile") {
                        exportProfile(profile)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        deleteProfile(profile)
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
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
            list = list.filter { $0.preferences["isFavorite"] as? Bool ?? false }
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
        let current = profile.preferences["isFavorite"] as? Bool ?? false
        updated.preferences["isFavorite"] = !current

        manager.delete(profile)
        manager.add(updated)
        selectedProfile = updated
    }

    private func exportProfile(_ profile: WorkspaceProfile) {
        if let data = try? JSONEncoder().encode(profile),
           let str = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    private func deleteProfile(_ profile: WorkspaceProfile) {
        manager.delete(profile)
        selectedProfile = nil
    }
}
