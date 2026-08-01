import SwiftUI

/// Infinite zoomable and pannable layout canvas supporting multiple device frames, grids, snapping, and smart alignment guides.
/// Optimized for maximum productivity, smooth panning, and gestures.
public struct VisualUICanvasView: View {
    @Bindable var document: VisualUIDocument
    @Bindable var settings: VisualUISettings

    @GestureState private var isPanning = false
    @State private var magnifyScale = 1.0
    @State private var dragStartOffset = CGSize.zero

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Infinite Grid Overlay Background
                if settings.showGrid {
                    InfiniteCanvasGrid(gridSize: settings.gridSize)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                }

                // Keyboard Shortcuts Bridge
                Group {
                    Button(action: { adjustZoom(by: 0.25) }) { Text("") }
                        .keyboardShortcut("+", modifiers: .command)
                    Button(action: { adjustZoom(by: -0.25) }) { Text("") }
                        .keyboardShortcut("-", modifiers: .command)
                    Button(action: {
                        document.scene.panOffsetX = 0
                        document.scene.panOffsetY = 0
                        document.scene.zoomScale = 1.0
                    }) { Text("") }
                        .keyboardShortcut("0", modifiers: .command)
                }
                .opacity(0)
                .frame(width: 0, height: 0)

                // Multiple Artboards Container
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(spacing: 64) {
                        ForEach(document.scene.artboards) { artboard in
                            ArtboardView(artboard: artboard, document: document, settings: settings)
                                .transition(.slide)
                        }

                        // Add Artboard Button
                        Button {
                            addNewArtboard()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 36))
                                Text("Add Artboard")
                                    .font(.headline)
                            }
                            .frame(width: 250, height: 400)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(100)
                    .scaleEffect(document.scene.zoomScale * magnifyScale)
                    .offset(x: document.scene.panOffsetX, y: document.scene.panOffsetY)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            if dragStartOffset == .zero {
                                dragStartOffset = CGSize(width: document.scene.panOffsetX, height: document.scene.panOffsetY)
                            }
                            document.scene.panOffsetX = dragStartOffset.width + val.translation.width
                            document.scene.panOffsetY = dragStartOffset.height + val.translation.height
                        }
                        .onEnded { _ in
                            dragStartOffset = .zero
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            magnifyScale = value
                        }
                        .onEnded { value in
                            document.scene.zoomScale = max(0.25, min(4.0, document.scene.zoomScale * value))
                            magnifyScale = 1.0
                        }
                )

                // Smart Snapping & Guides Overlay
                if settings.smartGuidesEnabled, !document.scene.selectedNodeIDs.isEmpty {
                    SmartGuidesOverlay()
                }

                // Floating HUD Zoom/Pan Dashboard
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Button {
                                adjustZoom(by: -0.25)
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.plain)

                            Text("\(Int(document.scene.zoomScale * 100))%")
                                .font(.caption.monospacedDigit().bold())
                                .frame(width: 44)

                            Button {
                                adjustZoom(by: 0.25)
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 16)

                            Button {
                                withAnimation(.spring()) {
                                    document.scene.panOffsetX = 0
                                    document.scene.panOffsetY = 0
                                    document.scene.zoomScale = 1.0
                                }
                            } label: {
                                Image(systemName: "scope")
                            }
                            .buttonStyle(.plain)
                            .help("Recenter Canvas (⌘0)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                        .padding(16)
                    }
                }
            }
        }
    }

    private func adjustZoom(by offset: Double) {
        let currentIdx = settings.zoomLevels.firstIndex(of: document.scene.zoomScale) ?? 3
        let targetIdx = max(0, min(settings.zoomLevels.count - 1, currentIdx + (offset > 0 ? 1 : -1)))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            document.scene.zoomScale = settings.zoomLevels[targetIdx]
        }
        settings.addLog("Adjusted workspace zoom to \(Int(document.scene.zoomScale * 100))%")
    }

    private func addNewArtboard() {
        document.checkpoint()
        let count = document.scene.artboards.count + 1
        let rootNode = VisualComponentNode(
            type: .vStack,
            children: [
                VisualComponentNode(type: .text, properties: ["textValue": "Screen \(count)"])
            ]
        )
        let newArt = VisualUIArtboard(name: "Artboard \(count)", rootNode: rootNode)
        withAnimation {
            document.scene.artboards.append(newArt)
        }
        settings.addLog("Created new artboard: \(newArt.name)")
    }
}
