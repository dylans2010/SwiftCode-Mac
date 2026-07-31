import SwiftUI
import Charts
import MapKit

/// Visual Canvas Renderer that bridges abstract layout scene nodes directly into real live interactive SwiftUI views.
public struct VisualUIRenderer: View {
    let rootNode: VisualComponentNode
    @Bindable var document: VisualUIDocument

    public var body: some View {
        RenderNode(node: rootNode)
    }

    @ViewBuilder
    private func RenderNode(node: VisualComponentNode) -> some View {
        if node.isHidden {
            Color.clear.frame(width: 0, height: 0)
        } else {
            let baseView = Group {
                switch node.type {
                // Layout & Stacks
                case .vStack:
                    VStack(alignment: .center, spacing: CGFloat(Double(node.properties["spacing"] ?? "8") ?? 8)) {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                case .hStack:
                    HStack(alignment: .center, spacing: CGFloat(Double(node.properties["spacing"] ?? "8") ?? 8)) {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                case .zStack:
                    ZStack {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                case .group:
                    Group {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                case .groupBox:
                    GroupBox(node.name) {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                // ScrollViews & Lists
                case .scrollView:
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(node.children) { child in
                                RenderNode(node: child)
                            }
                        }
                    }

                case .list:
                    List {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                case .form:
                    Form {
                        ForEach(node.children) { child in
                            RenderNode(node: child)
                        }
                    }

                // Controls
                case .text:
                    Text(node.properties["textValue"] ?? "Text Block")
                        .font(customFont(from: node))
                        .fontWeight(fontWeight(from: node))

                case .button:
                    Button(action: {
                        triggerAction(for: node)
                    }) {
                        Text(node.properties["textValue"] ?? "Button")
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
                    Toggle(node.properties["textValue"] ?? "Toggle Me", isOn: .constant(true))

                case .picker:
                    Picker("Selection", selection: .constant(1)) {
                        Text("Option 1").tag(1)
                        Text("Option 2").tag(2)
                    }

                case .slider:
                    Slider(value: .constant(0.5))

                case .stepper:
                    Stepper(node.properties["textValue"] ?? "Stepper", onIncrement: {}, onDecrement: {})

                case .progressView:
                    ProgressView()

                case .textField:
                    TextField("Text Input", text: .constant(""))
                        .textFieldStyle(.roundedBorder)

                case .secureField:
                    SecureField("Password Input", text: .constant(""))
                        .textFieldStyle(.roundedBorder)

                case .divider:
                    Divider()

                case .spacer:
                    Spacer()

                // Advanced Elements
                case .charts:
                    Chart {
                        BarMark(x: .value("A", "Category 1"), y: .value("B", 5))
                        BarMark(x: .value("A", "Category 2"), y: .value("B", 12))
                    }
                    .frame(height: 120)

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

                default:
                    Text(node.name)
                }
            }

            // Apply universal modifiers
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
                .onTapGesture {
                    document.scene.selectedNodeIDs = [node.id]
                }
        }
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
                document.scene.activeArtboardID = artboard.id
                VisualUISettings.shared.addLog("Active artboard context switched to \(artboard.name)")
            }
        }
    }
}
