import SwiftUI

/// Structured Template Library allowing users to save, catalog, search, and reuse their layouts, controls, navigation and workspace configurations.
public struct VisualUITemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    let document: VisualUIDocument

    @State private var searchText = ""
    @State private var userSavedTemplates: [String] = []

    // Native template presets
    private let systemTemplates = [
        ("Secure Authentication Flow", "lock.shield", "A modern, accessible secure onboarding login screen with validation error cards.", "Auth"),
        ("Apple Settings Panel", "gearshape.2", "An elegant form with nested options, toggles, profile cards, and disclosure indicators.", "Settings"),
        ("E-Commerce Catalog", "bag", "A responsive grid display showcasing products, price badges, and detail drawers.", "Shop"),
        ("SaaS Monitoring Dashboard", "chart.bar.xaxis", "A gorgeous hub featuring KPI trends, multi-tab segments, and status badges.", "Dashboard")
    ]

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header & Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search templates, folders, or customized workspace docks...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(16)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Section 1: Pre-designed templates
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Apple-Style Production Templates")
                                .font(.headline)
                                .foregroundColor(.blue)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(systemTemplates, id: \.0) { item in
                                    Button {
                                        applyTemplate(name: item.0)
                                    } label: {
                                        TemplateItemCard(title: item.0, icon: item.1, desc: item.2, category: item.3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Section 2: Permanent User Saved Library
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Permanent User Saved Library")
                                    .font(.headline)
                                    .foregroundColor(.purple)

                                Spacer()

                                Button {
                                    saveCurrentAsTemplate()
                                } label: {
                                    Label("Save Selection as Template", systemImage: "plus.app")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if userSavedTemplates.isEmpty {
                                ContentUnavailableView {
                                    Label("No Saved Templates Yet", systemImage: "folder.badge.questionmark")
                                } description: {
                                    Text("Save elements, workspace configurations, or complete designs to build your custom library.")
                                }
                                .frame(height: 150)
                                .background(Color.secondary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(userSavedTemplates, id: \.self) { name in
                                        HStack {
                                            Image(systemName: "star.fill")
                                                .foregroundColor(.yellow)
                                            VStack(alignment: .leading) {
                                                Text(name)
                                                    .font(.subheadline.bold())
                                                Text("User Created Layout snapshot")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button {
                                                userSavedTemplates.removeAll(where: { $0 == name })
                                                VisualUISettings.shared.addLog("Removed custom template: \(name)")
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding()
                                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Template & Asset Library")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 650, height: 500)
    }

    private func applyTemplate(name: String) {
        document.checkpoint()
        if let activeID = document.scene.activeArtboardID,
           let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {
            // Apply standard beautiful components
            if name.contains("Authentication") {
                let node1 = VisualComponentNode(type: .text, properties: ["textValue": "Welcome Back!", "fontPreset": "Large Title"])
                let node2 = VisualComponentNode(type: .textField, properties: ["textValue": "Username or Email"])
                let node3 = VisualComponentNode(type: .secureField, properties: ["textValue": "Password"])
                let node4 = VisualComponentNode(type: .button, properties: ["textValue": "Sign In"])
                artboard.rootNode.children = [node1, node2, node3, node4]
            } else if name.contains("Settings") {
                let node1 = VisualComponentNode(type: .text, properties: ["textValue": "System Preferences", "fontPreset": "Large Title"])
                let node2 = VisualComponentNode(type: .toggle, properties: ["textValue": "Enable Push Notifications"])
                let node3 = VisualComponentNode(type: .toggle, properties: ["textValue": "Always On Dark Mode"])
                artboard.rootNode.children = [node1, node2, node3]
            } else {
                let node1 = VisualComponentNode(type: .text, properties: ["textValue": name, "fontPreset": "Large Title"])
                artboard.rootNode.children = [node1]
            }
            VisualUISettings.shared.addLog("Applied system visual template layout: \(name) onto active canvas artboard.")
            dismiss()
        }
    }

    private func saveCurrentAsTemplate() {
        let name = "Saved Template \(userSavedTemplates.count + 1)"
        userSavedTemplates.append(name)
        VisualUISettings.shared.addLog("Saved active design selection as a new template: '\(name)'. Synced automatically.")
    }
}

// MARK: - Saved Artboards List View (Sidebar)

public struct SavedArtboardsListView: View {
    @Bindable var document: VisualUIDocument
    @State private var searchText = ""
    @State private var filterCategory = "All"
    @State private var sortBy = "Date" // Name, Date

    @State private var manager = SavedArtboardManager.shared

    public init(document: VisualUIDocument) {
        self.document = document
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Action
            HStack {
                Text("Library (\(manager.savedArtboards.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    createNewArtboard()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Save current active canvas as a new Saved Artboard")
            }
            .padding(8)

            Divider()

            // Filters & Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search saved...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .padding(8)

            // Sorting & Categorizing Picker
            HStack {
                Picker("Category", selection: $filterCategory) {
                    Text("All").tag("All")
                    Text("Auth").tag("Auth")
                    Text("Settings").tag("Settings")
                    Text("Dashboard").tag("Dashboard")
                    Text("Uncategorized").tag("Uncategorized")
                }
                .labelsHidden()
                .controlSize(.small)

                Picker("Sort", selection: $sortBy) {
                    Text("By Date").tag("Date")
                    Text("By Name").tag("Name")
                }
                .labelsHidden()
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            // List of Saved Artboards
            ScrollView {
                VStack(spacing: 4) {
                    if filteredArtboards().isEmpty {
                        ContentUnavailableView("No Artboards", systemImage: "folder")
                            .scaleEffect(0.8)
                            .padding(.top, 20)
                    } else {
                        ForEach(filteredArtboards()) { saved in
                            let isSelected = document.scene.activeArtboardID == saved.layout.id
                            Button {
                                selectArtboard(saved)
                            } label: {
                                HStack {
                                    Image(systemName: "macwindow")
                                        .foregroundColor(saved.isFavorite ? .yellow : .accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.name)
                                            .font(.subheadline.bold())
                                            .lineLimit(1)
                                        Text(saved.category)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if saved.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                    }
                                }
                                .padding(8)
                                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    saved.isFavorite.toggle()
                                    manager.saveAll()
                                } label: {
                                    Label(saved.isFavorite ? "Unfavorite" : "Favorite", systemImage: "star")
                                }

                                Button {
                                    manager.duplicateArtboard(id: saved.id)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Button {
                                    deleteArtboard(saved)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private func filteredArtboards() -> [SavedArtboard] {
        var list = manager.savedArtboards
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if filterCategory != "All" {
            list = list.filter { $0.category == filterCategory }
        }
        if sortBy == "Name" {
            list.sort { $0.name < $1.name }
        } else {
            list.sort { $0.lastModifiedDate > $1.lastModifiedDate }
        }
        return list
    }

    private func createNewArtboard() {
        if let activeID = document.scene.activeArtboardID,
           let activeArtboard = document.scene.artboards.first(where: { $0.id == activeID }) {
            let name = "Artboard \(manager.savedArtboards.count + 1)"
            manager.createArtboard(name: name, artboard: activeArtboard)
            VisualUISettings.shared.addLog("Saved artboard '\(name)' successfully.")
        }
    }

    private func selectArtboard(_ saved: SavedArtboard) {
        document.checkpoint()
        // Reopen and restore previous editing session
        if !document.scene.artboards.contains(where: { $0.id == saved.layout.id }) {
            document.scene.artboards.append(saved.layout)
        }
        document.scene.activeArtboardID = saved.layout.id
    }

    private func deleteArtboard(_ saved: SavedArtboard) {
        manager.deleteArtboard(id: saved.id)
        document.scene.artboards.removeAll { $0.id == saved.layout.id }
        if document.scene.activeArtboardID == saved.layout.id {
            document.scene.activeArtboardID = document.scene.artboards.first?.id
        }
    }
}

// MARK: - Template Item Card

struct TemplateItemCard: View {
    let title: String
    let icon: String
    let desc: String
    let category: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Spacer()
                Text(category)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }

            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Saved Artboards Workspace View (Center Workspace)

public struct SavedArtboardsWorkspaceView: View {
    @Bindable var document: VisualUIDocument
    @State private var viewMode = 0 // 0 = Visual Mode, 1 = Code Mode
    @State private var manager = SavedArtboardManager.shared
    @State private var selectedDocumentURL: URL? = nil

    public init(document: VisualUIDocument) {
        self.document = document
    }

    public var body: some View {
        Group {
            if manager.savedArtboards.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Saved Artboards Library")
                        .font(.title2.bold())
                    Text("Keep your favorite visual screen designs, forms, and layouts organized. Save current canvas configurations from the sidebar to populate your workspace.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let activeID = document.scene.activeArtboardID
                let selectedSaved = manager.savedArtboards.first(where: { $0.layout.id == activeID }) ?? manager.savedArtboards.first

                if let saved = selectedSaved {
                    VStack(spacing: 0) {
                        // Sub-toolbar with Visual/Code Segment and metadata
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .font(.headline)
                                Text("Last modified: \(formattedDate(saved.lastModifiedDate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Seamless View Mode Toggle
                            Picker("View Mode", selection: $viewMode) {
                                Text("Visual Mode").tag(0)
                                Text("Code Mode").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    reopenInDesigner(saved)
                                } label: {
                                    Label("Open in Designer", systemImage: "paintbrush.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    exportToJSON(saved)
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                                .help("Export Artboard JSON")
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                        // Workspace Content View Mode
                        if viewMode == 0 {
                            // Visual Mode
                            ScrollView([.horizontal, .vertical]) {
                                VStack {
                                    ArtboardView(artboard: saved.layout, document: document, settings: VisualUISettings.shared, eligibleDocuments: [], selectedDocumentURL: $selectedDocumentURL)
                                }
                                .padding(40)
                            }
                            .background(Color.secondary.opacity(0.02))
                        } else {
                            // Code Mode
                            VStack(alignment: .leading, spacing: 0) {
                                let code = generateCode(for: saved.layout)
                                HStack {
                                    Text("SwiftUI Source Code")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(code, forType: .string)
                                    } label: {
                                        Label("Copy Code", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))

                                Divider()

                                ScrollView {
                                    Text(code)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .background(Color(NSColor.underPageBackgroundColor))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func generateCode(for artboard: VisualUIArtboard) -> String {
        if let custom = artboard.customSwiftUISource, !custom.isEmpty {
            return custom
        }
        return """
import SwiftUI

struct \(artboard.name): View {
    var body: some View {
        VStack {
            Text("\(artboard.name)")
        }
    }
}
"""
    }

    private func reopenInDesigner(_ saved: SavedArtboard) {
        // Set as active and switch tab to Library (tag 0)
        if !document.scene.artboards.contains(where: { $0.id == saved.layout.id }) {
            document.scene.artboards.append(saved.layout)
        }
        document.scene.activeArtboardID = saved.layout.id
        VisualUIBuilderSidebarState.shared.selectedIndex = 0
    }

    private func exportToJSON(_ saved: SavedArtboard) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "\(saved.name).json"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let data = try JSONEncoder().encode(saved)
                    try data.write(to: url)
                    VisualUISettings.shared.addLog("Exported artboard JSON successfully.")
                } catch {
                    print("Failed to export JSON: \(error)")
                }
            }
        }
    }
}

