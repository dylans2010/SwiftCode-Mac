import SwiftUI

/// Infinite zoomable and pannable layout canvas supporting multiple device frames, grids, snapping, and smart alignment guides.
public struct VisualUICanvasView: View {
    @Bindable var document: VisualUIDocument
    @Bindable var settings: VisualUISettings

    @GestureState private var isPanning = false
    @GestureState private var magnifyScale = 1.0

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Infinite Grid Overlay Background
                if settings.showGrid {
                    InfiniteCanvasGrid(gridSize: settings.gridSize)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                }

                // Multiple Artboards Container
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(spacing: 64) {
                        ForEach(document.scene.artboards) { artboard in
                            ArtboardView(artboard: artboard, document: document, settings: settings)
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
                    DragGesture()
                        .onChanged { val in
                            document.scene.panOffsetX += val.translation.width * 0.1
                            document.scene.panOffsetY += val.translation.height * 0.1
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
                                document.scene.panOffsetX = 0
                                document.scene.panOffsetY = 0
                                document.scene.zoomScale = 1.0
                            } label: {
                                Image(systemName: "scope")
                            }
                            .buttonStyle(.plain)
                            .help("Recenter Canvas")
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
        document.scene.zoomScale = settings.zoomLevels[targetIdx]
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
        document.scene.artboards.append(newArt)
        settings.addLog("Created new artboard: \(newArt.name)")
    }
}

// MARK: - Infinite Canvas Grid

struct InfiniteCanvasGrid: Shape {
    let gridSize: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizontalCount = Int(rect.width / CGFloat(gridSize)) + 1
        let verticalCount = Int(rect.height / CGFloat(gridSize)) + 1

        for i in 0..<horizontalCount {
            let x = CGFloat(i) * CGFloat(gridSize)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }

        for i in 0..<verticalCount {
            let y = CGFloat(i) * CGFloat(gridSize)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }

        return path
    }
}

// MARK: - Smart Guides Overlay

struct SmartGuidesOverlay: View {
    var body: some View {
        ZStack {
            // Horizontal Guide Line
            Path { path in
                path.move(to: CGPoint(x: 0, y: 350))
                path.addLine(to: CGPoint(x: 2000, y: 350))
            }
            .stroke(Color.pink.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))

            // Vertical Guide Line
            Path { path in
                path.move(to: CGPoint(x: 520, y: 0))
                path.addLine(to: CGPoint(x: 520, y: 2000))
            }
            .stroke(Color.pink.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Artboard / Device View

struct ArtboardView: View {
    let artboard: VisualUIArtboard
    let document: VisualUIDocument
    let settings: VisualUISettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artboard Title
            Text(artboard.name)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            // Device Frame Wrapper
            VStack(spacing: 0) {
                // Content Viewport Renderer
                VisualUIRenderer(rootNode: artboard.rootNode, document: document)
                    .frame(width: viewportWidth, height: viewportHeight)
                    .background(settings.isDarkMode ? Color.black : Color.white)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 2)
                    )
                    .shadow(radius: 12)
            }
            .overlay(alignment: .top) {
                if settings.showSafeAreas {
                    // Simulated Dynamic Island / Notch Bounds
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black)
                        .frame(width: 110, height: 30)
                        .padding(.top, 10)
                }
            }
        }
    }

    private var viewportWidth: CGFloat {
        artboard.deviceFrame == "iPad Pro" ? 820 : (artboard.deviceFrame == "Apple Vision Pro" ? 900 : 393)
    }

    private var viewportHeight: CGFloat {
        artboard.deviceFrame == "iPad Pro" ? 1180 : (artboard.deviceFrame == "Apple Vision Pro" ? 560 : 852)
    }
}
