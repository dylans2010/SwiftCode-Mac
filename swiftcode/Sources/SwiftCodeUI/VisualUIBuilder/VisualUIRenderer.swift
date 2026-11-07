import SwiftUI
import Charts
import MapKit
import Observation

public struct VisualUIRenderer: View {
    let rootNode: VisualComponentNode
    @Bindable var document: VisualUIDocument

    @State private var textValues: [UUID: String] = [:]
    @State private var toggleValues: [UUID: Bool] = [:]
    @State private var sliderValues: [UUID: Double] = [:]
    @State private var pickerSelections: [UUID: Int] = [:]
    @State private var tabSelection = 0
    @State private var navigationPath = NavigationPath()
    @State private var activeSheetNode: VisualComponentNode? = nil
    @State private var activePopoverNode: VisualComponentNode? = nil
    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var counter = 10
    @State private var newItemText = ""

    public init(rootNode: VisualComponentNode, document: VisualUIDocument) {
        self.rootNode = rootNode
        self.document = document
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                renderNode(node: rootNode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Live Workspace")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: {
                        withAnimation(.spring()) {
                            counter += 1
                        }
                    }) {
                        Label("Increment", systemImage: "plus.circle")
                    }

                    Menu {
                        Button("Theme Toggle") {
                            withAnimation {
                                VisualUISettings.shared.isDarkMode.toggle()
                            }
                        }
                        Button("Reset State") {
                            counter = 10
                            dragOffsets.removeAll()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: VisualComponentNode.self) { destinationNode in
                ScrollView {
                    VStack {
                        HStack {
                            Button(action: {
                                if !navigationPath.isEmpty {
                                    navigationPath.removeLast()
                                }
                            }) {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 12)
                            Spacer()
                        }

                        renderNode(node: destinationNode)
                    }
                    .padding(16)
                }
            }
            .sheet(item: Binding(
                get: { activeSheetNode },
                set: { activeSheetNode = $0 }
            )) { sheetNode in
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button("Dismiss") {
                            activeSheetNode = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()

                    renderNode(node: sheetNode)
                        .padding()
                }
                .presentationDetents([.medium, .large])
            }
            .popover(item: Binding(
                get: { activePopoverNode },
                set: { activePopoverNode = $0 }
            )) { popNode in
                renderNode(node: popNode)
                    .padding()
                    .frame(width: 250, height: 180)
            }
        }
    }

    private func renderNode(node: VisualComponentNode) -> AnyView {
        if node.isHidden {
            return AnyView(Color.clear.frame(width: 0, height: 0))
        }

        let baseView = Group {
            switch node.type {
            case .vStack:
                VStack(alignment: .center, spacing: CGFloat(Double(node.properties["spacing"] ?? "8") ?? 8)) {
                    ForEach(node.children) { child in
                        renderNode(node: child)
                    }
                }

            case .hStack:
                HStack(alignment: .center, spacing: CGFloat(Double(node.properties["spacing"] ?? "8") ?? 8)) {
                    ForEach(node.children) { child in
                        renderNode(node: child)
                    }
                }

            case .zStack:
                ZStack {
                    ForEach(node.children) { child in
                        renderNode(node: child)
                    }
                }

            case .group:
                Group {
                    ForEach(node.children) { child in
                        renderNode(node: child)
                    }
                }

            case .groupBox:
                GroupBox(node.name) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(node.children) { child in
                            renderNode(node: child)
                        }
                    }
                }
                .groupBoxStyle(.liquidGlass)

            case .scrollView:
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(node.children) { child in
                            renderNode(node: child)
                        }
                    }
                }

            case .list:
                List {
                    Section {
                        ForEach(node.children) { child in
                            HStack {
                                Label(child.properties["textValue"] ?? child.name, systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.purple)
                                Spacer()
                                Button(action: {
                                    withAnimation {
                                        node.children.removeAll(where: { $0.id == child.id })
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Task Items (\(node.children.count))")
                    }

                    Section {
                        HStack {
                            TextField("New item...", text: $newItemText)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    withAnimation {
                                        node.children.append(VisualComponentNode(type: .text, properties: ["textValue": trimmed]))
                                        newItemText = ""
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

            case .form:
                Form {
                    Section("Profile Settings") {
                        TextField("Username", text: Binding(
                            get: { textValues[node.id] ?? "" },
                            set: { textValues[node.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Toggle("Push Notifications", isOn: Binding(
                            get: { toggleValues[node.id] ?? false },
                            set: { toggleValues[node.id] = $0 }
                        ))
                    }

                    Section("Theme Configuration") {
                        Slider(value: Binding(
                            get: { sliderValues[node.id] ?? 0.5 },
                            set: { sliderValues[node.id] = $0 }
                        ), in: 0...1)

                        Picker("Visual Workspace", selection: Binding(
                            get: { pickerSelections[node.id] ?? 0 },
                            set: { pickerSelections[node.id] = $0 }
                        )) {
                            Text("Full Stack").tag(0)
                            Text("Split Canvas").tag(1)
                            Text("Isolated Viewport").tag(2)
                        }
                    }
                }

            case .text:
                Text(node.properties["textValue"] ?? "Text Block")
                    .font(customFont(from: node))
                    .fontWeight(fontWeight(from: node))

            case .button:
                Button(action: {
                    triggerAction(for: node)
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("\(node.properties["textValue"] ?? "Button") (\(counter))")
                    }
                    .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)

            case .label:
                Label(
                    node.properties["textValue"] ?? "Label",
                    systemImage: node.properties["sfSymbolName"] ?? "sparkles"
                )

            case .image:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)

            case .asyncImage:
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title)
                    Text("Remote Image")
                        .font(.caption)
                }

            case .toggle:
                Toggle(node.properties["textValue"] ?? "Toggle Me", isOn: Binding(
                    get: { toggleValues[node.id] ?? false },
                    set: { toggleValues[node.id] = $0 }
                ))

            case .picker:
                Picker("Selection", selection: Binding(
                    get: { pickerSelections[node.id] ?? 0 },
                    set: { pickerSelections[node.id] = $0 }
                )) {
                    Text("Option 1").tag(0)
                    Text("Option 2").tag(1)
                    Text("Option 3").tag(2)
                }

            case .slider:
                VStack {
                    Slider(value: Binding(
                        get: { sliderValues[node.id] ?? 0.5 },
                        set: { sliderValues[node.id] = $0 }
                    ), in: 0...1)
                    Text("Value: \(String(format: "%.2f", sliderValues[node.id] ?? 0.5))")
                        .font(.caption.monospacedDigit())
                }

            case .stepper:
                Stepper(value: $counter, in: 0...100) {
                    Text("\(node.properties["textValue"] ?? "Stepper"): \(counter)")
                }

            case .progressView:
                ProgressView()

            case .textField:
                TextField("Text Input", text: Binding(
                    get: { textValues[node.id] ?? "" },
                    set: { textValues[node.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

            case .secureField:
                SecureField("Password Input", text: Binding(
                    get: { textValues[node.id] ?? "" },
                    set: { textValues[node.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

            case .divider:
                Divider()

            case .spacer:
                Spacer()

            case .charts:
                chartView(for: node)

            case .map:
                Map()
                    .frame(height: 150)
                    .cornerRadius(8)

            case .videoPlayer:
                ZStack {
                    Color.black.cornerRadius(8)
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
                .frame(height: 150)

            case .webView:
                VStack {
                    Image(systemName: "globe")
                        .font(.title)
                    Text("WebView Sandbox")
                        .font(.caption)
                }

            case .sfSymbol:
                Image(systemName: node.properties["sfSymbolName"] ?? "sparkles")
                    .font(.title)
                    .foregroundColor(.accentColor)

            case .navigationStack:
                VStack {
                    ForEach(node.children) { child in
                        renderNode(node: child)
                    }
                }

            case .navigationSplitView:
                HSplitView {
                    VStack {
                        Text("Sidebar")
                            .font(.headline)
                        if !node.children.isEmpty {
                            renderNode(node: node.children[0])
                        }
                    }
                    .frame(width: 150)

                    VStack {
                        Text("Detail View")
                            .font(.headline)
                        if node.children.count > 1 {
                            renderNode(node: node.children[1])
                        }
                    }
                    .frame(minWidth: 200)
                }

            case .tabView:
                TabView(selection: $tabSelection) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { idx, child in
                        renderNode(node: child)
                            .tabItem {
                                Label(child.name, systemImage: "star.fill")
                            }
                            .tag(idx)
                    }
                }

            default:
                Text(node.name)
            }
        }

        return AnyView(
            baseView
                .padding(CGFloat(Double(node.properties["padding"] ?? "0") ?? 0))
                .foregroundColor(node.properties["foregroundColor"].map { Color(hex: $0) })
                .background(node.properties["backgroundColor"].map { Color(hex: $0) })
                .frame(
                    width: node.properties["width"].flatMap { Double($0) }.map { CGFloat($0) },
                    height: node.properties["height"].flatMap { Double($0) }.map { CGFloat($0) }
                )
                .cornerRadius(CGFloat(Double(node.properties["cornerRadius"] ?? "0") ?? 0))
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(Double(node.properties["cornerRadius"] ?? "0") ?? 0))
                        .stroke(
                            document.scene.selectedNodeIDs.contains(node.id) ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
                .offset(dragOffsets[node.id] ?? .zero)
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            dragOffsets[node.id] = val.translation
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                dragOffsets[node.id] = .zero
                            }
                        }
                )
                .onTapGesture {
                    document.scene.selectedNodeIDs = [node.id]
                }
        )
    }

    private func chartView(for node: VisualComponentNode) -> AnyView {
        let bars: [(label: String, value: Double)] = node.children.compactMap { child in
            guard let raw = child.properties["value"], let value = Double(raw) else { return nil }
            return (label: child.properties["textValue"] ?? child.name, value: value)
        }
        if bars.isEmpty {
            return AnyView(
                ContentUnavailableView("No Chart Data", systemImage: "chart.bar", description: Text("Add child nodes with a numeric \"value\" property to plot bars."))
                    .frame(height: 120)
            )
        }
        return AnyView(
            Chart {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    BarMark(x: .value("Category", bar.label), y: .value("Value", bar.value))
                }
            }
            .frame(height: 120)
        )
    }

    private func customFont(from node: VisualComponentNode) -> Font {
        let preset = node.properties["fontPreset"] ?? "Body"
        switch preset {
        case "Large Title": return .largeTitle
        case "Title 1": return .title
        case "Headline": return .headline
        case "Subhead": return .subheadline
        case "Footnote": return .footnote
        default: return .body
        }
    }

    private func fontWeight(from node: VisualComponentNode) -> Font.Weight {
        let preset = node.properties["fontPreset"] ?? "Body"
        if preset.contains("Bold") || preset == "Headline" || preset == "Large Title" {
            return .bold
        }
        if preset.contains("Semibold") {
            return .semibold
        }
        return .regular
    }

    private func triggerAction(for node: VisualComponentNode) {
        let navType = node.properties["navigationType"] ?? "None"
        if navType != "None" {
            let dest = node.properties["navigationDestination"] ?? ""
            VisualUISettings.shared.addLog("Triggered interactive navigation action: \(navType) towards \(dest)")
            if let destUUID = UUID(uuidString: dest),
               let artboard = document.scene.artboards.first(where: { $0.id == destUUID }) {
                navigationPath.append(artboard.rootNode)
            }
        } else {
            if node.properties["actionType"] == "sheet" {
                if let child = node.children.first {
                    activeSheetNode = child
                } else {
                    VisualUISettings.shared.addLog("Sheet action ignored: node '\(node.name)' has no child node to present.")
                }
            } else if node.properties["actionType"] == "popover" {
                if let child = node.children.first {
                    activePopoverNode = child
                } else {
                    VisualUISettings.shared.addLog("Popover action ignored: node '\(node.name)' has no child node to present.")
                }
            } else {
                withAnimation(.spring()) {
                    counter += 1
                }
                VisualUISettings.shared.addLog("State counter updated natively: \(counter)")
            }
        }
    }
}
