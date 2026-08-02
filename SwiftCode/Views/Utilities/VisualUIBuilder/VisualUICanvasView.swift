import SwiftUI

/// Infinite zoomable and pannable layout canvas supporting multiple device frames, grids, snapping, and smart alignment guides.
/// Optimized for maximum productivity, smooth panning, and gestures.
public struct VisualUICanvasView: View {
    @Bindable var document: VisualUIDocument
    @Bindable var settings: VisualUISettings

    @GestureState private var isPanning = false
    @State private var magnifyScale = 1.0
    @State private var dragStartOffset = CGSize.zero
    @State private var showingAddArtboardSheet = false

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

                    Button(action: {
                        settings.isFullScreenCanvas.toggle()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("com.swiftcode.visualUIBuilder.toggleFullScreen"),
                            object: nil,
                            userInfo: ["isFullScreen": settings.isFullScreenCanvas]
                        )
                    }) { Text("") }
                        .keyboardShortcut("f", modifiers: [.command, .option])
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
                            showingAddArtboardSheet = true
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
                    .sheet(isPresented: $showingAddArtboardSheet) {
                        AddArtboardSheet { name, device, app, port, dtSize, scale, sArea, src in
                            addNewCustomArtboard(
                                name: name,
                                device: device,
                                appearance: app,
                                isPortrait: port,
                                dynamicTypeSize: dtSize,
                                scale: scale,
                                showSafeAreas: sArea,
                                sourceCode: src
                            )
                        }
                    }
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
                    SmartGuidesOverlay(document: document, settings: settings)
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

    private func addNewCustomArtboard(
        name: String,
        device: String,
        appearance: String,
        isPortrait: Bool,
        dynamicTypeSize: String,
        scale: Double,
        showSafeAreas: Bool,
        sourceCode: String
    ) {
        document.checkpoint()
        let rootNode = VisualComponentNode(
            type: .vStack,
            children: [
                VisualComponentNode(type: .text, properties: ["textValue": name])
            ]
        )
        let newArt = VisualUIArtboard(
            name: name,
            deviceFrame: device,
            rootNode: rootNode,
            customSwiftUISource: sourceCode,
            appearance: appearance,
            isPortrait: isPortrait,
            dynamicTypeSize: dynamicTypeSize,
            previewScale: scale,
            showSafeAreas: showSafeAreas
        )
        withAnimation {
            document.scene.artboards.append(newArt)
            document.scene.activeArtboardID = newArt.id
        }
        settings.addLog("Created custom compiled artboard: \(name)")
    }
}

/// Infinite grid that repeats vertical and horizontal lines based on gridSize settings.
public struct InfiniteCanvasGrid: Shape {
    public var gridSize: Double

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = 0.0
        while y < rect.height {
            var x = 0.0
            while x < rect.width {
                // Draw a tiny dot at (x, y)
                path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                x += gridSize
            }
            y += gridSize
        }
        return path
    }
}

/// Interactive rendering container for a single device canvas.
public struct ArtboardView: View {
    let artboard: VisualUIArtboard
    @Bindable var document: VisualUIDocument
    let settings: VisualUISettings

    var size: CGSize {
        switch artboard.deviceFrame {
        case "iPhone 16 Pro":
            return CGSize(width: 393, height: 852)
        case "iPad Pro":
            return CGSize(width: 834, height: 1112)
        case "Apple Watch":
            return CGSize(width: 242, height: 280)
        case "Apple Vision Pro":
            return CGSize(width: 900, height: 500)
        default:
            return CGSize(width: 393, height: 852)
        }
    }

    public var body: some View {
        let isActive = document.scene.activeArtboardID == artboard.id

        VStack(alignment: .leading, spacing: 12) {
            // Header panel for renaming/deleting artboards
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isActive ? .accentColor : .secondary)

                    if artboard.name == "Default" {
                        Text("Default")
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else {
                        TextField("Artboard Name", text: Binding(
                            get: { artboard.name },
                            set: { artboard.name = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .frame(maxWidth: 200)
                    }
                }

                Spacer()

                Text(artboard.deviceFrame)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: Capsule())

                // Open in Simulator button
                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("com.swiftcode.openArtboardSimulator"),
                        object: nil,
                        userInfo: ["artboardID": artboard.id]
                    )
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Open in Workspace Artboard Simulator")

                if artboard.name != "Default" && document.scene.artboards.count > 1 {
                    Button {
                        deleteArtboard()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Artboard")
                }
            }
            .padding(.horizontal, 4)

            // Render output inside the simulated device frame
            VStack {
                if artboard.name == "Default" {
                    if let hostedView = PreviewManager.shared.hostedView {
                        NativePreviewHost(hostedView: hostedView)
                            .frame(width: size.width, height: size.height)
                            .background(settings.isDarkMode ? Color.black : Color.white)
                    } else if PreviewManager.shared.isCompiling {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Compiling SwiftUI View...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: size.width, height: size.height)
                        .background(settings.isDarkMode ? Color.black : Color.white)
                    } else {
                        // Display real compiler diagnostics in place of preview!
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Compilation Failed", systemImage: "xmark.octagon.fill")
                                .font(.headline)
                                .foregroundColor(.red)

                            ScrollView {
                                Text(PreviewManager.shared.buildLogs.joined(separator: "\n"))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .frame(width: size.width, height: size.height)
                        .background(Color.red.opacity(0.05))
                    }
                } else {
                    if let customSource = artboard.customSwiftUISource, !customSource.isEmpty {
                        if let artboardView = DocumentCoordinator.shared.compiledArtboardViews[artboard.id] {
                            NativePreviewHost(hostedView: artboardView)
                                .frame(width: size.width, height: size.height)
                                .background(settings.isDarkMode ? Color.black : Color.white)
                        } else if let errorMsg = DocumentCoordinator.shared.compiledArtboardErrors[artboard.id] {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Artboard Compile Error", systemImage: "exclamationmark.triangle.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                ScrollView {
                                    Text(errorMsg)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding()
                            .frame(width: size.width, height: size.height)
                            .background(Color.red.opacity(0.05))
                        } else {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Compiling Artboard...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: size.width, height: size.height)
                            .background(settings.isDarkMode ? Color.black : Color.white)
                        }
                    } else {
                        VisualUIRenderer(rootNode: artboard.rootNode, document: document)
                            .frame(width: size.width, height: size.height)
                            .background(settings.isDarkMode ? Color.black : Color.white)
                    }
                }
            }
            .cornerRadius(settings.showSafeAreas ? 40 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: settings.showSafeAreas ? 40 : 0)
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isActive ? 3 : 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 10)
            .contentShape(Rectangle())
            .onTapGesture {
                document.scene.activeArtboardID = artboard.id
            }
        }
    }

    private func deleteArtboard() {
        document.checkpoint()
        if let idx = document.scene.artboards.firstIndex(where: { $0.id == artboard.id }) {
            document.scene.artboards.remove(at: idx)
            if document.scene.activeArtboardID == artboard.id {
                document.scene.activeArtboardID = document.scene.artboards.first?.id
            }
            settings.addLog("Deleted artboard: \(artboard.name)")
        }
    }
}

/// Fine-grained layout guide displaying dimensions, snaps, and spatial constraints for selection.
public struct SmartGuidesOverlay: View {
    @Bindable var document: VisualUIDocument
    @Bindable var settings: VisualUISettings

    public var body: some View {
        if let selectedID = document.scene.selectedNodeIDs.first,
           let node = document.scene.findNode(byID: selectedID) {
            GeometryReader { geo in
                ZStack {
                    // Floating dimension metric card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.and.outline")
                                .foregroundColor(.pink)
                            Text("Smart Snapping")
                                .font(.caption.bold())
                                .foregroundColor(.pink)
                        }

                        Text("Selected: \(node.name)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let width = node.properties["width"] {
                            Text("W: \(width) px")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.pink)
                        }
                        if let height = node.properties["height"] {
                            Text("H: \(height) px")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.pink)
                        }
                    }
                    .padding(8)
                    .background(Color.pink.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.pink.opacity(0.3), lineWidth: 1)
                    )
                    .position(x: 120, y: 40)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
