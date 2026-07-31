import SwiftUI

/// Panel managing individual scene layers, arranging Z-index hierarchies, bringing elements to front, or locking them securely.
public struct VisualUILayersPanel: View {
    @Bindable var document: VisualUIDocument

    public var body: some View {
        VStack(spacing: 0) {
            Text("LAYERS & ARRANGEMENT")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)

            Divider()

            if let activeID = document.scene.activeArtboardID,
               let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {
                VStack(spacing: 12) {
                    // Quick Action Ordering buttons
                    HStack(spacing: 8) {
                        Button {
                            reorderSelectedLayer(direction: .up)
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .disabled(document.scene.selectedNodeIDs.isEmpty)

                        Button {
                            reorderSelectedLayer(direction: .down)
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(document.scene.selectedNodeIDs.isEmpty)
                    }
                    .padding(8)

                    Divider()

                    ScrollView {
                        VStack(spacing: 4) {
                            // Gather flat list of nodes for layer management
                            let nodes = flattenNodes(startNode: artboard.rootNode)
                            ForEach(nodes) { node in
                                HStack {
                                    Image(systemName: node.type.systemIcon)
                                        .foregroundColor(.accentColor)
                                    Text(node.name)
                                        .font(.subheadline)

                                    Spacer()

                                    if node.isLocked {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.orange)
                                    }
                                    if node.isHidden {
                                        Image(systemName: "eye.slash.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(document.scene.selectedNodeIDs.contains(node.id) ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .onTapGesture {
                                    document.scene.selectedNodeIDs = [node.id]
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Canvas Artboard", systemImage: "square.stack.3d.down.right")
                }
            }
        }
    }

    enum MoveDirection {
        case up, down
    }

    private func reorderSelectedLayer(direction: MoveDirection) {
        guard let selectedID = document.scene.selectedNodeIDs.first else { return }
        document.checkpoint()

        if let parent = document.scene.findParentNode(ofNodeID: selectedID) {
            if let index = parent.children.firstIndex(where: { $0.id == selectedID }) {
                let targetIndex = direction == .up ? index - 1 : index + 1
                if targetIndex >= 0 && targetIndex < parent.children.count {
                    parent.children.swapAt(index, targetIndex)
                    VisualUISettings.shared.addLog("Reordered layer \(parent.children[targetIndex].name)")
                }
            }
        }
    }

    private func flattenNodes(startNode: VisualComponentNode) -> [VisualComponentNode] {
        var results = [startNode]
        for child in startNode.children {
            results.append(contentsOf: flattenNodes(startNode: child))
        }
        return results
    }
}
