import SwiftUI

// MARK: - Extensions View

struct ExtensionsView: View {
    @StateObject private var manager = ExtensionManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: ExtensionManifest.ExtensionCategory? = nil
    @State private var sortOrder: SortOrder = .name
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
            result.sort { $0.isInstalled && !$1.isInstalled }
        }

        return result
    }

    private var allDownloaded: Bool {
        manager.extensions.allSatisfy { $0.isDownloaded }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

                Group {
                    if manager.isLoading && manager.extensions.isEmpty {
                        ProgressView("Loading Extensions…")
                            .tint(.orange)
                    } else if filteredExtensions.isEmpty {
                        emptyState
                    } else {
                        extensionList
                    }
                }
            }
            .navigationTitle("Extensions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Extensions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !allDownloaded {
                            Button {
                                showDownloadAllConfirm = true
                            } label: {
                                Label("Download All", systemImage: "arrow.down.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption.weight(.semibold))
                            }
                        }

                        Button {
                            Task { await manager.scanExtensions() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.orange)
                        }

                        Button {
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.orange)
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
            .sheet(item: $extensionForDemo) { ext in
                ExtensionDemoView(ext: ext)
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
            .confirmationDialog(
                "Download All Extensions?",
                isPresented: $showDownloadAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Download All") {
                    manager.downloadAllExtensions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will download and enable all available extensions.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Extension List

    private var extensionList: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Category filter bar
                categoryFilterBar
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(filteredExtensions) { ext in
                        ExtensionRow(
                            ext: ext,
                            onToggle: { manager.toggleExtension(ext) },
                            onEdit: { extensionToEdit = ext },
                            onDelete: {
                                extensionToDelete = ext
                                showDeleteConfirm = true
                            },
                            onDownload: { manager.downloadExtension(ext) },
                            onTryDemo: {
                                extensionForDemo = ext
                                showDemoSheet = true
                            }
                        )
                        if ext != filteredExtensions.last {
                            Divider().opacity(0.15).padding(.leading, 70)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", icon: "square.grid.2x2", selected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(ExtensionManifest.ExtensionCategory.allCases) { category in
                    filterChip(label: category.rawValue, icon: category.icon, selected: selectedCategory == category) {
                        selectedCategory = (selectedCategory == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

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
            .background(selected ? Color.orange.opacity(0.25) : Color.white.opacity(0.07), in: Capsule())
            .foregroundStyle(selected ? .orange : .secondary)
            .overlay(
                Capsule().stroke(selected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 52))
                .foregroundStyle(.orange.opacity(0.5))
            Text(searchText.isEmpty ? "No Extensions Installed" : "No Results")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(searchText.isEmpty
                 ? "Tap + to create your own extension, or install one from a folder."
                 : "Try a different search or filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if searchText.isEmpty {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create Extension", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Extension Demo View

struct ExtensionDemoView: View {
    let ext: ExtensionManifest
    @Environment(\.dismiss) private var dismiss
    @State private var demoInput = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(categoryColor(ext.category).opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: ext.category.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(categoryColor(ext.category))
                }

                VStack(spacing: 6) {
                    Text(ext.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("v\(ext.version) · \(ext.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ext.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Try it in the editor with:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("extensionUse: \(ext.id)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Interactive Demo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Type sample input for \(ext.name)…", text: $demoInput, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))
                        .lineLimit(4...8)

                    if !demoInput.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("\(ext.name) would process this input.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(.top, 24)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12))
            .navigationTitle("Try Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
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
}

// MARK: - Extension Row

struct ExtensionRow: View {
    let ext: ExtensionManifest
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDownload: () -> Void
    let onTryDemo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryColor(ext.category).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: ext.category.icon)
                    .font(.title3)
                    .foregroundStyle(categoryColor(ext.category))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ext.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)

                    if !ext.isDownloaded {
                        Text("Online")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }

                Text(ext.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("v\(ext.version)")
                    Text("·")
                    Text(ext.author)
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Action
            if ext.isDownloaded {
                Toggle("", isOn: .constant(ext.isEnabled))
                    .labelsHidden()
                    .tint(.orange)
                    .onTapGesture { onToggle() }
            } else {
                Button {
                    onDownload()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Get")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ext.isEnabled ? Color.orange.opacity(0.02) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onDownload()
            } label: {
                Label(ext.isDownloaded ? "Re-Download" : "Download", systemImage: "arrow.down.circle.fill")
            }

            Button {
                onTryDemo()
            } label: {
                Label("Try Demo", systemImage: "play.circle.fill")
            }

            if ext.isUserCreated {
                Button { onEdit() } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Divider()

            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }

            if ext.isUserCreated {
                Button { onEdit() } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }

            if !ext.isDownloaded {
                Button { onDownload() } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .tint(.orange)
            }
        }
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
}
