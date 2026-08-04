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
    @State private var eligibleDocuments: [URL] = []
    @State private var selectedDocumentURL: URL? = nil
    private let fileScanTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

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
                            ArtboardView(
                                artboard: artboard,
                                document: document,
                                settings: settings,
                                eligibleDocuments: eligibleDocuments,
                                selectedDocumentURL: $selectedDocumentURL
                            )
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
            .onAppear {
                scanForEligibleDocuments()
            }
            .onReceive(fileScanTimer) { _ in
                scanForEligibleDocuments()
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

    private func scanForEligibleDocuments() {
        Task {
            let docs = await XcodeBuildAPI.shared.scanForVisualUIDocuments()
            await MainActor.run {
                self.eligibleDocuments = docs
                if selectedDocumentURL == nil || !docs.contains(where: { $0.path == selectedDocumentURL?.path }) {
                    if let activeDocURL = DocumentCoordinator.shared.activeDocument?.url,
                       docs.contains(where: { $0.path == activeDocURL.path }) {
                        self.selectedDocumentURL = activeDocURL
                    } else {
                        self.selectedDocumentURL = docs.first
                    }
                }
            }
        }
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
    let eligibleDocuments: [URL]
    @Binding var selectedDocumentURL: URL?

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
                        HStack(spacing: 4) {
                            Text("Default:")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Picker("", selection: $selectedDocumentURL) {
                                Text("Select Document").tag(URL?.none)
                                ForEach(eligibleDocuments, id: \.self) { docURL in
                                    Text(docURL.lastPathComponent).tag(URL?.some(docURL))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 180)
                            .onChange(of: selectedDocumentURL) { _, newURL in
                                if let newURL = newURL {
                                    Task {
                                        if let content = try? String(contentsOf: newURL, encoding: .utf8) {
                                            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(content, filename: newURL.path)
                                            await PreviewManager.shared.startFreshLivePreviewSession(
                                                sourcePath: newURL.path,
                                                sourceCode: preparedCode
                                            )
                                        }
                                    }
                                }
                            }
                        }
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

                if artboard.name != "Default" && artboard.name != "Simulator" && document.scene.artboards.count > 1 {
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
                            HStack {
                                Label("Compilation Failed", systemImage: "xmark.octagon.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Spacer()
                                CopyLogsButton(logs: PreviewManager.shared.buildLogs.joined(separator: "\n"))
                            }

                            if PreviewManager.shared.buildLogs.joined(separator: "\n").contains("Build already in progress.") {
                                Button(action: {
                                    Task {
                                        await PreviewManager.shared.stopAndRestartSession()
                                    }
                                }) {
                                    Label("Stop and Restart", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }

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
                } else if artboard.name == "Simulator" {
                    SimulatorArtboardView(size: size, settings: settings)
                        .frame(width: size.width, height: size.height)
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


// MARK: - Simulator Artboard View

struct SimulatorArtboardView: View {
    let size: CGSize
    let settings: VisualUISettings

    @State private var runManager = FullAppRunManager.shared
    @State private var api = XcodeBuildAPI.shared
    @State private var selectedLogsTab = 0 // 0: Runtime Logs, 1: Build Logs, 2: Diagnostics, 3: Session Info

    var body: some View {
        VStack(spacing: 0) {
            // Simulator Controls Header (integrated into device frame header)
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            await runManager.runFullApp()
                        }
                    }) {
                        Label("Restart", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(runManager.isRunning || api.isExecuting)

                    Button(action: {
                        runManager.stopApplication()
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!runManager.isRunning && !api.isExecuting)

                    Spacer()

                    // Mini Status Indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(runManager.isRunning ? Color.green : (api.isExecuting ? Color.orange : Color.secondary))
                            .frame(width: 8, height: 8)
                        Text(runManager.isRunning ? "RUNNING" : (api.isExecuting ? "BUILDING" : "IDLE"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Tabs selector inside the simulator artboard
                Picker("", selection: $selectedLogsTab) {
                    Text("Runtime").tag(0)
                    Text("Build").tag(1)
                    Text("Diag").tag(2)
                    Text("Session").tag(3)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Screen View
            ZStack {
                Color.black

                if selectedLogsTab == 0 {
                    // Runtime Logs Tab
                    logsScrollView(logs: runManager.runLogs, placeholder: "No runtime logs available. Press Run App or Restart to run.")
                } else if selectedLogsTab == 1 {
                    // Build Logs Tab
                    logsScrollView(logs: api.currentLogs, placeholder: "No build logs available.")
                } else if selectedLogsTab == 2 {
                    // Diagnostics Tab
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let error = api.activeGenerationError {
                                Text("Project Generation / Build Error")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(error.message)
                                    .font(.body)
                                    .foregroundColor(.white)
                                if let recovery = error.suggestedRecovery {
                                    Text("Suggested Recovery:")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.green)
                                    Text(recovery)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("No Active Diagnostics Errors.")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Text("All compiler toolchains and project checks are healthy.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Session Info Tab
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Active Simulator Session")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                                .padding(.bottom, 4)

                            Group {
                                LabeledInfoRow(label: "Product Name", value: api.determineProductName())
                                LabeledInfoRow(label: "Bundle ID", value: api.determineBundleIdentifier())
                                LabeledInfoRow(label: "Active Scheme", value: api.determineActiveScheme()?.name ?? "Default")
                                LabeledInfoRow(label: "Active SDK", value: "iphonesimulator")
                                LabeledInfoRow(label: "Destination", value: api.determineBuildDestination().destination)
                                LabeledInfoRow(label: "Configuration", value: api.determineActiveBuildConfiguration().rawValue)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func logsScrollView(logs: [String], placeholder: String) -> some View {
        if logs.isEmpty {
            VStack {
                Text(placeholder)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(logs.indices, id: \.self) { idx in
                        Text(logs[idx])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct LabeledInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .bold()
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.white)
            Spacer()
        }
        .font(.caption)
    }
}
