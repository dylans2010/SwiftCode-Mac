import SwiftUI

/// Panel containing categorizations of native Apple components for easy visual placement.
public struct VisualUIComponentLibrary: View {
    @Bindable var document: VisualUIDocument
    @State private var searchText = ""

    // Component categories mapped beautifully
    private let categories: [String: [VisualComponentType]] = [
        "Layout & Stacks": [.vStack, .hStack, .zStack, .group, .groupBox],
        "Input Controls": [.button, .toggle, .picker, .slider, .stepper, .textField, .secureField],
        "Content & Media": [.text, .label, .image, .asyncImage, .sfSymbol],
        "Containers & Lists": [.form, .list, .scrollView, .grid, .lazyVGrid, .lazyHGrid],
        "Navigation Models": [.navigationStack, .navigationSplitView, .tabView],
        "Advanced Frameworks": [.charts, .map, .videoPlayer, .webView, .canvas]
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search components...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(8)

            Divider()

            // Library List
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(categories.keys.sorted(), id: \.self) { category in
                        let items = filteredItems(forCategory: category)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(items, id: \.self) { type in
                                        ComponentItemButton(type: type) {
                                            insertComponent(type)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func filteredItems(forCategory category: String) -> [VisualComponentType] {
        let types = categories[category] ?? []
        if searchText.isEmpty { return types }
        return types.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    private func insertComponent(_ type: VisualComponentType) {
        document.checkpoint()
        let newNode = VisualComponentNode(type: type)

        if let activeID = document.scene.activeArtboardID,
           let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {

            // If there's a selected node, insert as child or sibling of it
            if let selectedID = document.scene.selectedNodeIDs.first,
               let targetNode = document.scene.findNode(byID: selectedID) {
                targetNode.children.append(newNode)
                VisualUISettings.shared.addLog("Inserted \(type.rawValue) inside \(targetNode.name)")
            } else {
                // Insert into root
                artboard.rootNode.children.append(newNode)
                VisualUISettings.shared.addLog("Inserted \(type.rawValue) into artboard root")
            }
        }
    }
}

// MARK: - Individual Component Library Button

struct ComponentItemButton: View {
    let type: VisualComponentType
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.systemIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                Text(type.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
