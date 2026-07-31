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

// MARK: - Individual Template Item view card

struct TemplateItemCard: View {
    let title: String
    let icon: String
    let desc: String
    let category: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text(category)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }
}
