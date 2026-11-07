import SwiftUI

public struct VisualUIHierarchy: View {
    @Bindable var document: VisualUIDocument

    public var body: some View {
        VStack(spacing: 0) {
            Text("SCENE TREE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .liquidGlass(style: .subtle, cornerRadius: 0)

            Divider()

            if let activeID = document.scene.activeArtboardID,
               let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {
                ScrollView {
                    VStack(spacing: 2) {
                        HierarchyNodeRow(
                            node: artboard.rootNode,
                            depth: 0,
                            document: document
                        )
                    }
                    .padding(8)
                }
            } else {
                ContentUnavailableView {
                    Label("No Active Artboard", systemImage: "macwindow")
                }
            }
        }
    }
}

struct HierarchyNodeRow: View {
    let node: VisualComponentNode
    let depth: Int
    let document: VisualUIDocument

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: CGFloat(depth * 14))

                if !node.children.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 10)
                }

                Image(systemName: node.type.systemIcon)
                    .foregroundColor(isSelected ? .white : .accentColor)

                Text(node.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        node.isHidden.toggle()
                        VisualUISettings.shared.addLog("Toggled visibility of \(node.name)")
                    } label: {
                        Image(systemName: node.isHidden ? "eye.slash" : "eye")
                            .foregroundStyle(node.isHidden ? Color.red : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        node.isLocked.toggle()
                        VisualUISettings.shared.addLog("Toggled lock on \(node.name)")
                    } label: {
                        Image(systemName: node.isLocked ? "lock.fill" : "lock.open")
                            .foregroundStyle(node.isLocked ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button {
                            duplicateNode()
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            deleteNode()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
                .opacity(isSelected ? 1.0 : 0.6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectNode()
            }

            if isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    HierarchyNodeRow(
                        node: child,
                        depth: depth + 1,
                        document: document
                    )
                }
            }
        }
    }

    private var isSelected: Bool {
        document.scene.selectedNodeIDs.contains(node.id)
    }

    private func selectNode() {
        document.scene.selectedNodeIDs = [node.id]
    }

    private func duplicateNode() {
        document.checkpoint()
        if let parent = document.scene.findParentNode(ofNodeID: node.id) {
            let copy = node.duplicated()
            parent.children.append(copy)
            VisualUISettings.shared.addLog("Duplicated component: \(node.name)")
        }
    }

    private func deleteNode() {
        document.checkpoint()
        if let parent = document.scene.findParentNode(ofNodeID: node.id) {
            parent.children.removeAll(where: { $0.id == node.id })
            document.scene.selectedNodeIDs.remove(node.id)
            VisualUISettings.shared.addLog("Deleted component: \(node.name)")
        }
    }
}
