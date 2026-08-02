import SwiftUI

@MainActor
struct LicencesAddView: View {
    let project: Project

    enum SortMode: String, CaseIterable, Identifiable {
        case nameAZ = "Name A-Z"
        case nameZA = "Name Z-A"
        case category = "Category"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var sortMode: SortMode = .nameAZ
    @State private var selectedLicenseForPreview: LicenseTemplate?
    @State private var isWriting = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var categories: [String] {
        ["All"] + Array(Set(LicenseCatalog.all.map(\.category))).sorted()
    }

    private var filteredLicenses: [LicenseTemplate] {
        var values = LicenseCatalog.all

        if selectedCategory != "All" {
            values = values.filter { $0.category == selectedCategory }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            values = values.filter {
                $0.name.lowercased().contains(query) ||
                $0.summary.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }

        switch sortMode {
        case .nameAZ: values.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameZA: values.sort { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .category: values.sort { ($0.category, $0.name) < ($1.category, $1.name) }
        }
        return values
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Project Licenses", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            Text("Quickly add open source license templates directly to your project codebase.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Filter controls card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Filters & Selection")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)

                            HStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search licenses...", text: $searchText)
                                        .textFieldStyle(.plain)
                                }
                                .padding(6)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                                Picker("Category", selection: $selectedCategory) {
                                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.regular)

                                Picker("Sort", selection: $sortMode) {
                                    ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.regular)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // License Directory list card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("License Templates", systemImage: "list.bullet.rectangle")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            if filteredLicenses.isEmpty {
                                HStack {
                                    Spacer()
                                    ContentUnavailableView(
                                        "No Licenses Found",
                                        systemImage: "doc.text.magnifyingglass",
                                        description: Text("Try adjusting search or category filters.")
                                    )
                                    .padding()
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(filteredLicenses) { license in
                                        Button {
                                            selectedLicenseForPreview = license
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(license.name)
                                                        .font(.subheadline.bold())
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Text(license.category)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.blue.opacity(0.15), in: Capsule())
                                                        .foregroundStyle(.blue)
                                                }

                                                Text(license.summary)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            .padding(12)
                                            .background(Color.secondary.opacity(0.04))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .navigationTitle("Add License")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .sourceControlEmbedded()
        .frame(width: 600, height: 650)
        .alert("License Installation", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $selectedLicenseForPreview) { license in
            LicensePreviewDetailView(license: license) {
                Task { await addLicense(license) }
            }
        }
    }

    @MainActor
    private func addLicense(_ license: LicenseTemplate) async {
        isWriting = true
        defer { isWriting = false }

        let repositoryURL = project.directoryURL
        let destination = repositoryURL.appendingPathComponent("LICENSE")

        // 1. Write the complete license text into the LICENSE file, replacing any existing contents.
        do {
            try license.body.write(to: destination, atomically: true, encoding: .utf8)
            sessionStore.refreshFileTree(for: project)
        } catch {
            alertMessage = "Failed to create or update LICENSE file: \(error.localizedDescription)"
            showAlert = true
            return
        }

        // 2. Perform Git automation (stage, commit, push)
        do {
            let git = GitService.shared
            guard await git.isGitInstalled() else {
                throw AppError.gitError("Git executable is not available on this system.")
            }

            // Stage only the LICENSE file
            try await git.stage(path: destination, repositoryURL: repositoryURL)

            // Create a Git commit with the exact message: Added License with SwiftCode
            try await git.commit(message: "Added License with SwiftCode", repositoryURL: repositoryURL)

            // Push the commit to the current branch's configured remote
            try await git.push(repositoryURL: repositoryURL)

            alertMessage = "Successfully created LICENSE file and pushed to remote branch!"
            showAlert = true
        } catch {
            alertMessage = "License created locally, but Git operations failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct LicensePreviewDetailView: View {
    let license: LicenseTemplate
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Summary card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("License Summary", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()

                                Button {
                                    onAdd()
                                    dismiss()
                                } label: {
                                    Label("Add to Project", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }

                            Text(license.summary)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Body card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("License Template Body", systemImage: "scroll")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)

                            Text(license.body)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .padding()
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .navigationTitle(license.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 650, height: 600)
    }
}
