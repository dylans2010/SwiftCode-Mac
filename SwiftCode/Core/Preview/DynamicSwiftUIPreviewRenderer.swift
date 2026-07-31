import SwiftUI
import Observation

// MARK: - Reactive Playground Observable Model (Swift 6 strict concurrency safe)
@Observable
@MainActor
public final class PreviewPlaygroundState {
    public static let shared = PreviewPlaygroundState()

    // Interactive Form States
    public var username: String = "Jules"
    public var isNotificationsEnabled: Bool = true
    public var accentColor: Color = .purple
    public var counter: Int = 10

    // List States
    public var items: [String] = ["Build Workspace", "Consolidate Engines", "Native Sidebars", "Playground Mode"]
    public var newItemText: String = ""

    // Gestures States
    public var dragOffset: CGSize = .zero
    public var isDragging: Bool = false

    // Animations States
    public var scale: Double = 1.0
    public var rotation: Double = 0.0
    public var isAnimatingBall: Bool = false

    private init() {}

    public func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItemText = ""
    }

    public func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
    }
}

// MARK: - Dynamic parsed element helper models
struct ParsedComponent: Identifiable, Sendable {
    let id = UUID()
    let type: ParsedType
    let text: String
    let value: String?
}

enum ParsedType: String, Sendable {
    case text
    case button
    case toggle
    case textField
    case image
    case divider
    case spacer
    case progressView
    case vStack
    case hStack
    case zStack
}

// MARK: - Dynamic SwiftUI Preview Renderer View
public struct DynamicSwiftUIPreviewRenderer: View {
    let content: String

    @State private var playgroundState = PreviewPlaygroundState.shared
    @State private var tabSelection = 0
    @State private var navigationPath = NavigationPath()

    public init(content: String) {
        self.content = content
    }

    public var body: some View {
        let parsed = parseSwiftUI(from: content)

        Group {
            if parsed.isEmpty {
                // If no SwiftUI structures are parsed, display the professional Interactive Playground suite
                playgroundSuiteView
            } else {
                // If SwiftUI components are found, render them live and interactively!
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("DYNAMIC PARSED INTERACTIVE VIEW")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.04))

                    Divider()

                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(parsed) { comp in
                                renderParsed(comp)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color.secondary.opacity(0.02))
                }
            }
        }
    }

    // MARK: - Parsed SwiftUI Live Elements Renderer
    @ViewBuilder
    private func renderParsed(_ comp: ParsedComponent) -> some View {
        switch comp.type {
        case .text:
            Text(comp.text)
                .font(.body)
                .multilineTextAlignment(.leading)
        case .button:
            Button(action: {
                withAnimation(.spring()) {
                    playgroundState.counter += 1
                }
            }) {
                Label(comp.text, systemImage: "hand.tap.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(playgroundState.accentColor)
        case .toggle:
            Toggle(comp.text, isOn: Binding(
                get: { playgroundState.isNotificationsEnabled },
                set: { playgroundState.isNotificationsEnabled = $0 }
            ))
            .toggleStyle(.switch)
        case .textField:
            VStack(alignment: .leading, spacing: 4) {
                Text(comp.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(comp.text, text: Binding(
                    get: { playgroundState.username },
                    set: { playgroundState.username = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        case .image:
            Image(systemName: comp.text)
                .font(.system(size: 32))
                .foregroundColor(playgroundState.accentColor)
        case .divider:
            Divider()
        case .spacer:
            Spacer()
        case .progressView:
            ProgressView()
        case .vStack, .hStack, .zStack:
            // Group-like layout fallbacks
            HStack {
                Image(systemName: "arrow.right.to.line")
                    .foregroundColor(.secondary)
                Text(comp.text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(6)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(4)
        }
    }

    // MARK: - RegEx-based source parser
    private func parseSwiftUI(from sourceCode: String) -> [ParsedComponent] {
        guard !sourceCode.isEmpty else { return [] }
        var list: [ParsedComponent] = []

        let lines = sourceCode.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }

            // 1. Text match
            if let textMatch = firstMatch(in: trimmed, pattern: #"Text\s*\(\s*"([^"]+)"\s*\)"#) {
                list.append(ParsedComponent(type: .text, text: textMatch, value: nil))
            }
            // 2. Button match
            else if let buttonMatch = firstMatch(in: trimmed, pattern: #"Button\s*\(\s*"([^"]+)"\s*\)"#) {
                list.append(ParsedComponent(type: .button, text: buttonMatch, value: nil))
            }
            // 3. Toggle match
            else if let toggleMatch = firstMatch(in: trimmed, pattern: #"Toggle\s*\(\s*"([^"]+)"\s*,"#) {
                list.append(ParsedComponent(type: .toggle, text: toggleMatch, value: nil))
            }
            // 4. TextField match
            else if let tfMatch = firstMatch(in: trimmed, pattern: #"TextField\s*\(\s*"([^"]+)"\s*,"#) {
                list.append(ParsedComponent(type: .textField, text: tfMatch, value: nil))
            }
            // 5. Image match
            else if let imageMatch = firstMatch(in: trimmed, pattern: #"Image\s*\(\s*systemName:\s*"([^"]+)"\s*\)"#) {
                list.append(ParsedComponent(type: .image, text: imageMatch, value: nil))
            }
            // 6. ProgressView
            else if trimmed.contains("ProgressView()") {
                list.append(ParsedComponent(type: .progressView, text: "", value: nil))
            }
            // 7. Divider
            else if trimmed.contains("Divider()") {
                list.append(ParsedComponent(type: .divider, text: "", value: nil))
            }
        }
        return list
    }

    private func firstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[valueRange])
    }

    // ====================================================================
    // PLAYGROUND INTERACTIVE CONTROL SUITE (PLAYGROUNDS-QUALITY GOAL)
    // ====================================================================
    private var playgroundSuiteView: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Deck category bar
                Picker("Playground Deck", selection: $tabSelection) {
                    Text("Controls").tag(0)
                    Text("List & Cards").tag(1)
                    Text("Gestures").tag(2)
                    Text("Animations").tag(3)
                    Text("Navigation").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(12)
                .background(Color.secondary.opacity(0.04))

                Divider()

                ScrollView {
                    VStack(spacing: 20) {
                        switch tabSelection {
                        case 0:
                            controlsView
                        case 1:
                            listCardsView
                        case 2:
                            gesturesView
                        case 3:
                            animationsView
                        default:
                            navigationView
                        }
                    }
                    .padding(20)
                }
            }
            .background(Color.secondary.opacity(0.02))
        }
    }

    // 1. Controls Panel
    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interactive Controls Console")
                .font(.headline)
                .foregroundColor(.purple)

            GroupBox {
                VStack(spacing: 14) {
                    TextField("Username Input", text: Binding(
                        get: { playgroundState.username },
                        set: { playgroundState.username = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Active User:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(playgroundState.username)
                            .bold()
                            .foregroundColor(.purple)
                        Spacer()
                    }

                    Divider()

                    Toggle("Enable Notifications", isOn: Binding(
                        get: { playgroundState.isNotificationsEnabled },
                        set: { playgroundState.isNotificationsEnabled = $0 }
                    ))

                    Divider()

                    ColorPicker("Theme Accent Color", selection: Binding(
                        get: { playgroundState.accentColor },
                        set: { playgroundState.accentColor = $0 }
                    ))

                    Divider()

                    HStack {
                        Text("Live Counter State:")
                        Spacer()
                        Button(action: {
                            withAnimation(.spring()) {
                                playgroundState.counter -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)

                        Text("\(playgroundState.counter)")
                            .font(.title3.bold())
                            .frame(width: 40)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            withAnimation(.spring()) {
                                playgroundState.counter += 1
                            }
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }

    // 2. List & Cards Panel
    private var listCardsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dynamic List & Content Cards")
                .font(.headline)
                .foregroundColor(.purple)

            GroupBox {
                VStack(spacing: 12) {
                    HStack {
                        TextField("New Task...", text: Binding(
                            get: { playgroundState.newItemText },
                            set: { playgroundState.newItemText = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Add Item") {
                            withAnimation(.spring()) {
                                playgroundState.addItem()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(playgroundState.accentColor)
                    }

                    ForEach(Array(playgroundState.items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Label(item, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring()) {
                                    playgroundState.removeItem(at: index)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding(8)
            }
        }
    }

    // 3. Gestures Panel (With velocity/drag bouncing)
    private var gesturesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spatial Gestures Simulator")
                .font(.headline)
                .foregroundColor(.purple)

            Text("Drag the card around with your mouse. Release it to see it snap back with natural spring physics.")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack {
                Color.secondary.opacity(0.04)
                    .frame(height: 250)
                    .cornerRadius(12)

                VStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                        .font(.largeTitle)
                    Text("Drag Me")
                        .font(.headline)
                    Text("Offset: \(Int(playgroundState.dragOffset.width)), \(Int(playgroundState.dragOffset.height))")
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
                .foregroundColor(.white)
                .frame(width: 150, height: 150)
                .background(playgroundState.accentColor.gradient)
                .cornerRadius(24)
                .shadow(color: playgroundState.accentColor.opacity(playgroundState.isDragging ? 0.6 : 0.3), radius: playgroundState.isDragging ? 20 : 10)
                .offset(playgroundState.dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            playgroundState.isDragging = true
                            playgroundState.dragOffset = gesture.translation
                        }
                        .onEnded { _ in
                            playgroundState.isDragging = false
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
                                playgroundState.dragOffset = .zero
                            }
                        }
                )
            }
        }
    }

    // 4. Animations Panel (Bouncing ball & physics transitions)
    private var animationsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Animation & Physics Studio")
                .font(.headline)
                .foregroundColor(.purple)

            GroupBox {
                VStack(spacing: 16) {
                    // Ball bouncer
                    ZStack(alignment: .bottom) {
                        Color.secondary.opacity(0.04)
                            .frame(height: 120)
                            .cornerRadius(12)

                        Circle()
                            .fill(playgroundState.accentColor.gradient)
                            .frame(width: 32, height: 32)
                            .offset(y: playgroundState.isAnimatingBall ? -80 : 0)
                            .padding(.bottom, 8)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            playgroundState.isAnimatingBall = true
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Scale Factor")
                            Spacer()
                            Text(String(format: "%.2fx", playgroundState.scale))
                                .fontDesign(.monospaced)
                        }
                        Slider(value: Binding(
                            get: { playgroundState.scale },
                            set: { playgroundState.scale = $0 }
                        ), in: 0.5...2.0)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Rotation Angle")
                            Spacer()
                            Text("\(Int(playgroundState.rotation))°")
                                .fontDesign(.monospaced)
                        }
                        Slider(value: Binding(
                            get: { playgroundState.rotation },
                            set: { playgroundState.rotation = $0 }
                        ), in: 0...360)
                    }

                    // Scaled/Rotated box
                    RoundedRectangle(cornerRadius: 12)
                        .fill(playgroundState.accentColor.opacity(0.12))
                        .stroke(playgroundState.accentColor, lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: "square.stack.3d.up")
                                .font(.title)
                                .foregroundColor(playgroundState.accentColor)
                        }
                        .scaleEffect(playgroundState.scale)
                        .rotationEffect(Angle(degrees: playgroundState.rotation))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: playgroundState.scale)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: playgroundState.rotation)
                        .padding(20)
                }
                .padding(8)
            }
        }
    }

    // 5. Navigation Stack Panel
    private var navigationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Navigation Deck")
                .font(.headline)
                .foregroundColor(.purple)

            NavigationLink(value: "layout_sandbox") {
                HStack {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                    Text("Open Layout Sandbox")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(10)
            }

            NavigationLink(value: "performance_monitor") {
                HStack {
                    Image(systemName: "gauge.with.needle")
                    Text("Performance Metrics Studio")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(10)
            }
        }
        .navigationDestination(for: String.self) { val in
            if val == "layout_sandbox" {
                VStack(spacing: 16) {
                    Text("Layout Sandbox")
                        .font(.title2.bold())
                    Text("Dynamic multi-alignment demo.")
                        .font(.caption)

                    VStack(alignment: .center, spacing: 10) {
                        Text("Center Aligned")
                        HStack {
                            Text("Left")
                            Spacer()
                            Text("Right")
                        }
                    }
                    .padding()
                    .background(playgroundState.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Text("Performance Metrics")
                        .font(.title2.bold())
                    Text("Immediate frame rendering statistics.")
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frame Draw Time: 1.2ms")
                        Text("Vsync Refresh: 120Hz")
                        Text("Thread Isolation: MainActor")
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
    }
}
