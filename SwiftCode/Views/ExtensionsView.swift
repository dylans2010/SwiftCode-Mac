import SwiftUI

// MARK: - Extensions View

struct ExtensionsView: View {
    @StateObject private var manager = ExtensionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: ExtensionManifest.ExtensionCategory? = nil
    @State private var sortOrder: SortOrder = .name
    @State private var selectedExtension: ExtensionManifest?
    @State private var showCreateSheet = false
    @State private var extensionToEdit: ExtensionManifest?
    @State private var extensionToDelete: ExtensionManifest?
    @State private var showDeleteConfirm = false
    @State private var extensionForDemo: ExtensionManifest?
    @State private var showDemoSheet = false
    @State private var showDownloadAllConfirm = false

    enum SortOrder: String, CaseIterable {
        case name      = "Name"
        case category  = "Category"
        case installed = "Installed"
    }

    var filteredExtensions: [ExtensionManifest] {
        var result = manager.extensions

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by category
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        // Sort
        switch sortOrder {
        case .name:
            result.sort { $0.name < $1.name }
        case .category:
            result.sort { $0.category.rawValue < $1.category.rawValue }
        case .installed:
            result.sort { $0.isDownloaded && !$1.isDownloaded }
        }

        return result
    }

    private var allDownloaded: Bool {
        manager.extensions.allSatisfy { $0.isDownloaded }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar: Category filters & Extension List
            VStack(spacing: 0) {
                // Categories Quick Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(label: "All", icon: "square.grid.2x2", selected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(ExtensionManifest.ExtensionCategory.allCases) { category in
                            filterChip(label: category.rawValue, icon: category.icon, selected: selectedCategory == category) {
                                selectedCategory = (selectedCategory == category) ? nil : category
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.background.opacity(0.4))

                Divider()

                if manager.isLoading && manager.extensions.isEmpty {
                    ProgressView("Loading Extensions…")
                        .tint(.orange)
                        .frame(maxHeight: .infinity)
                } else if filteredExtensions.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    List(filteredExtensions, selection: $selectedExtension) { ext in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(categoryColor(ext.category).opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: ext.category.icon)
                                    .font(.caption)
                                    .foregroundStyle(categoryColor(ext.category))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ext.name)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text(ext.author)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if ext.isDownloaded && ext.isEnabled {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .tag(ext)
                    }
                    .listStyle(.sidebar)
                }
            }
            .searchable(text: $searchText, prompt: "Search Extensions")
            .navigationTitle("Extensions")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        Button {
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .help("Create Extension")
                        }

                        Button {
                            Task { await manager.scanExtensions() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .help("Refresh")
                        }
                    }
                }
            }
        } detail: {
            // Detail View
            if let ext = selectedExtension {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header info
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(categoryColor(ext.category).opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Image(systemName: ext.category.icon)
                                    .font(.title)
                                    .foregroundStyle(categoryColor(ext.category))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ext.name)
                                    .font(.title2.bold())
                                Text("v\(ext.version) · By \(ext.author)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Download/Toggle Action
                            if ext.isDownloaded {
                                Toggle(isOn: Binding(
                                    get: { ext.isEnabled },
                                    set: { _ in manager.toggleExtension(ext) }
                                )) {
                                    Text(ext.isEnabled ? "Enabled" : "Disabled")
                                        .font(.subheadline.bold())
                                }
                                .toggleStyle(.switch)
                            } else {
                                Button {
                                    manager.downloadExtension(ext)
                                } label: {
                                    Label("Install Extension", systemImage: "arrow.down.circle.fill")
                                        .font(.subheadline.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(ext.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }

                        // Categories & Metadata
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Metadata")
                                .font(.headline)

                            HStack {
                                Label("Category: \(ext.category.rawValue)", systemImage: ext.category.icon)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(categoryColor(ext.category).opacity(0.12))
                                    .foregroundStyle(categoryColor(ext.category))
                                    .cornerRadius(6)

                                if ext.isUserCreated {
                                    Label("User Created", systemImage: "person.circle.fill")
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(6)
                                }
                            }
                            .font(.caption)
                        }

                        // Actions Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Actions")
                                .font(.headline)

                            HStack(spacing: 12) {
                                if ext.isUserCreated {
                                    Button {
                                        extensionToEdit = ext
                                    } label: {
                                        Label("Edit Extension", systemImage: "pencil")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                }

                                Button(role: .destructive) {
                                    extensionToDelete = ext
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding(32)
                }
                .navigationTitle(ext.name)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select an Extension",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Choose an extension from the sidebar to inspect or customize its behaviors.")
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateExtensionView()
        }
        .sheet(item: $extensionToEdit) { ext in
            EditExtensionView(extension: ext)
        }
        .confirmationDialog(
            "Delete \(extensionToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let ext = extensionToDelete {
                    try? manager.uninstallExtension(ext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the extension and remove it from the IDE.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Category Filter Bar Helpers

    private func filterChip(label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.orange.opacity(0.2) : Color.white.opacity(0.06), in: Capsule())
            .foregroundStyle(selected ? .orange : .secondary)
            .overlay(
                Capsule().stroke(selected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryColor(_ category: ExtensionManifest.ExtensionCategory) -> Color {
        switch category {
        case .editor:    return .blue
        case .tools:     return .orange
        case .themes:    return .pink
        case .languages: return .green
        case .ai:        return .purple
        case .build:     return .yellow
        case .testing:   return .teal
        case .other:     return .secondary
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.5))
            Text("No Extensions Found")
                .font(.headline)
            Text("Try expanding your search query or choosing a different category category.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}
