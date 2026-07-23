import SwiftUI
import AppKit

// MARK: - Enums & Options

enum CustomSymbolRenderingMode: String, CaseIterable, Identifiable {
    case monochrome = "Monochrome"
    case hierarchical = "Hierarchical"
    case palette = "Palette"
    case multicolor = "Multicolor"

    var id: String { rawValue }

    var nativeMode: SwiftUI.SymbolRenderingMode {
        switch self {
        case .monochrome: return .monochrome
        case .hierarchical: return .hierarchical
        case .palette: return .palette
        case .multicolor: return .multicolor
        }
    }
}

enum PickerSymbolWeightOption: String, CaseIterable, Identifiable {
    case ultraLight = "Ultra Light"
    case thin = "Thin"
    case light = "Light"
    case regular = "Regular"
    case medium = "Medium"
    case semibold = "Semibold"
    case bold = "Bold"
    case heavy = "Heavy"
    case black = "Black"

    var id: String { rawValue }

    var fontWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

enum PickerSymbolScaleOption: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var id: String { rawValue }

    var imageScale: Image.Scale {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }
}

// MARK: - Models

struct SFSymbolRecord: Identifiable, Hashable, Sendable {
    let id: String // Symbol name
    let version: Int // 4, 5, or 6
    let isMulticolor: Bool

    var name: String { id }
}

// MARK: - Resource Loader

final class SFSymbolResourceLoader: Sendable {
    static let shared = SFSymbolResourceLoader()
    private init() {}

    func loadSymbols(version: Int) -> [SFSymbolRecord] {
        let filename = "sfsymbol\(version)"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "txt") else {
            let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("SwiftCode/Resources/Symbols/\(filename).txt")
            if let content = try? String(contentsOf: fallbackURL, encoding: .utf8) {
                return parseContent(content, version: version)
            }
            return fallbackSymbols(version: version)
        }

        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return parseContent(content, version: version)
        }
        return fallbackSymbols(version: version)
    }

    private func parseContent(_ content: String, version: Int) -> [SFSymbolRecord] {
        var records: [SFSymbolRecord] = []
        var seen = Set<String>()

        let lines = content.split(separator: "\n")
        for line in lines {
            let lineStr = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineStr.isEmpty else { continue }

            let parts = lineStr.split(separator: ",")
            let name = String(parts[0])

            guard !seen.contains(name) else { continue }
            seen.insert(name)

            let isMulticolor = parts.count > 1 && parts[1].contains("multicolor")
            records.append(SFSymbolRecord(id: name, version: version, isMulticolor: isMulticolor))
        }
        return records
    }

    private func fallbackSymbols(version: Int) -> [SFSymbolRecord] {
        return [
            SFSymbolRecord(id: "star.fill", version: version, isMulticolor: false),
            SFSymbolRecord(id: "heart.fill", version: version, isMulticolor: true),
            SFSymbolRecord(id: "gearshape.fill", version: version, isMulticolor: false),
            SFSymbolRecord(id: "arrow.triangle.branch", version: version, isMulticolor: false),
            SFSymbolRecord(id: "terminal.fill", version: version, isMulticolor: false),
            SFSymbolRecord(id: "sparkles", version: version, isMulticolor: true),
            SFSymbolRecord(id: "lock.fill", version: version, isMulticolor: false)
        ]
    }
}

// MARK: - Cache Manager

actor SFSymbolCacheManager {
    static let shared = SFSymbolCacheManager()
    private var cache: [Int: [SFSymbolRecord]] = [:]

    private init() {}

    func getSymbols(version: Int) -> [SFSymbolRecord] {
        if let cached = cache[version] {
            return cached
        }
        let loaded = SFSymbolResourceLoader.shared.loadSymbols(version: version)
        cache[version] = loaded
        return loaded
    }
}

// MARK: - ViewModel

@MainActor
final class SFSymbolPickerViewModel: ObservableObject {
    @Published var selectedVersion = 6 // 4, 5, or 6
    @Published var searchQuery = ""
    @Published var isSearching = false
    @Published var symbols: [SFSymbolRecord] = []
    @Published var favorites: Set<String> = []
    @Published var recents: [String] = []

    private static let favoritesKey = "com.swiftcode.symbols.favorites"
    private static let recentsKey = "com.swiftcode.symbols.recents"

    init() {
        loadPersistence()
        loadSymbols()
    }

    func loadSymbols() {
        isSearching = true
        let version = selectedVersion

        Task {
            let loaded = await SFSymbolCacheManager.shared.getSymbols(version: version)
            await MainActor.run {
                self.symbols = loaded
                self.isSearching = false
            }
        }
    }

    var filteredSymbols: [SFSymbolRecord] {
        if searchQuery.isEmpty {
            return symbols
        }
        let query = searchQuery.lowercased()
        return symbols.filter { $0.name.lowercased().contains(query) }
    }

    func toggleFavorite(_ name: String) {
        if favorites.contains(name) {
            favorites.remove(name)
        } else {
            favorites.insert(name)
        }
        savePersistence()
    }

    func addToRecents(_ name: String) {
        recents.removeAll { $0 == name }
        recents.insert(name, at: 0)
        recents = Array(recents.prefix(12))
        savePersistence()
    }

    private func loadPersistence() {
        if let favs = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) {
            favorites = Set(favs)
        }
        recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    private func savePersistence() {
        UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }
}

// MARK: - Modernized SFSymbolPickerView

struct SFSymbolPickerView: View {
    @StateObject private var viewModel = SFSymbolPickerViewModel()
    @State private var selectedSymbol: SFSymbolRecord? = nil
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // High layout density header using native picker
                HStack(spacing: 16) {
                    Picker("Version", selection: $viewModel.selectedVersion) {
                        Text("SF Symbols 6").tag(6)
                        Text("SF Symbols 5").tag(5)
                        Text("SF Symbols 4").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.selectedVersion) { _, _ in
                        viewModel.loadSymbols()
                    }
                    .frame(width: 320)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Symbol browser grid
                ScrollView {
                    if viewModel.isSearching {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading symbols index...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    } else if viewModel.filteredSymbols.isEmpty {
                        ContentUnavailableView("No Symbols Matched", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, minHeight: 250)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.filteredSymbols) { symbol in
                                symbolCell(symbol)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .navigationTitle("SF Symbols Browser")
            .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer, prompt: "Search \(viewModel.symbols.count) symbols...")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSymbol) { symbol in
                SFSymbolDetailSheet(symbol: symbol, viewModel: viewModel)
            }
        }
    }

    private func symbolCell(_ symbol: SFSymbolRecord) -> some View {
        Button {
            selectedSymbol = symbol
            viewModel.addToRecents(symbol.name)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                        .frame(width: 48, height: 48)

                    Image(systemName: symbol.name)
                        .font(.title3)
                        .foregroundStyle(.primary)
                }

                Text(symbol.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 80)
            }
            .padding(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Redesigned SFSymbolDetailSheet (Symbol Inspector)

struct SFSymbolDetailSheet: View {
    let symbol: SFSymbolRecord
    @ObservedObject var viewModel: SFSymbolPickerViewModel
    @Environment(\.dismiss) private var dismiss

    // Configuration controls
    @State private var renderingMode: CustomSymbolRenderingMode = .monochrome
    @State private var symbolWeight: PickerSymbolWeightOption = .regular
    @State private var symbolScale: PickerSymbolScaleOption = .large
    @State private var fontSize: CGFloat = 48
    @State private var variableValue: Double = 0.5
    @State private var primaryColor: Color = .orange
    @State private var secondaryColor: Color = .blue
    @State private var backgroundOption = "Default"
    @State private var selectedTemplate = "Basic Image"

    // Animation list
    @State private var effectTrigger = false
    @State private var activeEffect = "Bounce"
    let effects = ["Bounce", "Pulse", "Scale", "Appear", "Disappear"]

    // Background list
    let backgrounds = ["Default", "Light", "Dark", "Accent"]

    // Templates
    let codeTemplates = [
        "Basic Image", "Label", "Button", "ToolbarItem",
        "Navigation", "List Row", "Menu", "Context Menu",
        "TabView", "Widget", "Lock Screen Widget", "macOS Toolbar", "iOS Toolbar"
    ]

    var body: some View {
        NavigationStack {
            HSplitView {
                // Left Panel: Interactive Live Preview & Background Settings
                VStack(spacing: 16) {
                    // Background Toggles & Preview Card
                    GroupBox {
                        VStack(spacing: 12) {
                            Picker("Background", selection: $backgroundOption) {
                                ForEach(backgrounds, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            ZStack {
                                previewColorBackground()
                                    .frame(height: 160)
                                    .cornerRadius(8)

                                animatedPreviewSymbol()
                            }
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Live Previews inside common SwiftUI components
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Component Integration Preview")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Divider()

                            // Label
                            Label("Notification Alert", systemImage: symbol.name)
                                .font(.headline)

                            // Button
                            Button(action: {}) {
                                HStack {
                                    Image(systemName: symbol.name)
                                    Text("Action Button")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            // List Row representation
                            HStack {
                                Image(systemName: symbol.name)
                                    .foregroundStyle(.blue)
                                Text("System Preferences Module")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(4)
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Metadata Info Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Symbol Parameters").font(.caption.bold()).foregroundStyle(.secondary)
                            Divider()
                            LabeledContent("Name", value: symbol.name).font(.caption)
                            LabeledContent("Category", value: "General, Core, Multi-Device").font(.caption)
                            LabeledContent("Availability", value: "iOS 13.0+ | macOS 10.15+").font(.caption)
                            LabeledContent("Variable Value Support", value: symbol.isMulticolor ? "Yes (iOS 16.0+)" : "No").font(.caption)
                            LabeledContent("Accessibility Support", value: "Primary Screenreader Compliant").font(.caption)
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                .padding(16)

                // Right Panel: Rendering Adjustments & Generated Code Multi-Templates
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Specifications Configurations Card
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Symbol Parameters", systemImage: "slider.horizontal.3")
                                        .font(.headline)
                                        .foregroundStyle(.green)

                                    Divider()

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Font Size: \(Int(fontSize))pt").font(.caption.bold()).foregroundStyle(.secondary)
                                        Slider(value: $fontSize, in: 24...120)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Variable Value: \(variableValue, specifier: "%.2f")").font(.caption.bold()).foregroundStyle(.secondary)
                                        Slider(value: $variableValue, in: 0...1.0)
                                    }

                                    Picker("Rendering Mode", selection: $renderingMode) {
                                        ForEach(CustomSymbolRenderingMode.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    .pickerStyle(.menu)

                                    Picker("Symbol Weight", selection: $symbolWeight) {
                                        ForEach(PickerSymbolWeightOption.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    .pickerStyle(.menu)

                                    Picker("Symbol Scale", selection: $symbolScale) {
                                        ForEach(PickerSymbolScaleOption.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    .pickerStyle(.segmented)

                                    if renderingMode == .palette {
                                        HStack {
                                            ColorPicker("Primary", selection: $primaryColor)
                                            ColorPicker("Secondary", selection: $secondaryColor)
                                        }
                                    }
                                }
                                .padding(6)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Animations Config
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Animations & SF Effects", systemImage: "sparkles")
                                        .font(.headline)
                                        .foregroundStyle(.orange)

                                    Divider()

                                    HStack {
                                        Picker("Effect", selection: $activeEffect) {
                                            ForEach(effects, id: \.self) { Text($0).tag($0) }
                                        }
                                        .pickerStyle(.menu)

                                        Button("Play Effect") {
                                            effectTrigger.toggle()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                    }
                                }
                                .padding(6)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Generated Code Template Selector & Copy Block
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label("SwiftUI Code Generator", systemImage: "doc.text.fill")
                                            .font(.headline)
                                            .foregroundStyle(.purple)
                                        Spacer()

                                        Button("Copy Code") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(generateSwiftUICode(), forType: .string)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Picker("Template", selection: $selectedTemplate) {
                                        ForEach(codeTemplates, id: \.self) { Text($0).tag($0) }
                                    }
                                    .pickerStyle(.menu)

                                    Text(generateSwiftUICode())
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.12))
                                        .cornerRadius(6)
                                        .textSelection(.enabled)
                                }
                                .padding(6)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .padding(16)
                    }
                }
                .frame(minWidth: 320, idealWidth: 380)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle(symbol.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 850, height: 600)
    }

    // MARK: - Animated Symbol Preview Generator

    @ViewBuilder
    private func animatedPreviewSymbol() -> some View {
        let baseImg = Image(systemName: symbol.name, variableValue: variableValue)
            .font(.system(size: fontSize, weight: symbolWeight.fontWeight))
            .imageScale(symbolScale.imageScale)

        let styledImg: AnyView = {
            switch renderingMode {
            case .monochrome:
                return AnyView(
                    baseImg
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(primaryColor)
                )
            case .hierarchical:
                return AnyView(
                    baseImg
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(primaryColor)
                )
            case .palette:
                return AnyView(
                    baseImg
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(primaryColor, secondaryColor)
                )
            case .multicolor:
                return AnyView(
                    baseImg
                        .symbolRenderingMode(.multicolor)
                )
            }
        }()

        if activeEffect == "Bounce" {
            styledImg.symbolEffect(.bounce, value: effectTrigger)
        } else if activeEffect == "Pulse" {
            styledImg.symbolEffect(.pulse, value: effectTrigger)
        } else if activeEffect == "Scale" {
            styledImg.symbolEffect(.scale, isActive: effectTrigger)
        } else if activeEffect == "Appear" {
            styledImg.symbolEffect(.appear, isActive: effectTrigger)
        } else {
            styledImg.symbolEffect(.disappear, isActive: effectTrigger)
        }
    }

    // MARK: - Previews Color

    private func previewColorBackground() -> Color {
        switch backgroundOption {
        case "Light": return .white
        case "Dark": return .black
        case "Accent": return Color.accentColor.opacity(0.18)
        default: return Color.secondary.opacity(0.08)
        }
    }

    // MARK: - Generated Code Template Parser

    private func generateSwiftUICode() -> String {
        let weightStr = ".\(symbolWeight.rawValue.replacingOccurrences(of: " ", with: "").lowercased())"
        let scaleStr = ".\(symbolScale.rawValue.lowercased())"

        var baseImageDeclaration = "Image(systemName: \"\(symbol.name)\""
        if symbol.isMulticolor {
            baseImageDeclaration += ", variableValue: \(variableValue)"
        }
        baseImageDeclaration += ")\n"
        baseImageDeclaration += "    .font(.system(size: \(Int(fontSize)), weight: \(weightStr)))\n"
        baseImageDeclaration += "    .imageScale(\(scaleStr))\n"

        switch renderingMode {
        case .monochrome:
            baseImageDeclaration += "    .symbolRenderingMode(.monochrome)\n"
        case .hierarchical:
            baseImageDeclaration += "    .symbolRenderingMode(.hierarchical)\n"
        case .palette:
            baseImageDeclaration += "    .symbolRenderingMode(.palette)\n"
            baseImageDeclaration += "    .foregroundStyle(.orange, .blue)\n"
        case .multicolor:
            baseImageDeclaration += "    .symbolRenderingMode(.multicolor)\n"
        }

        switch selectedTemplate {
        case "Label":
            return "Label {\n    Text(\"Notification Alert\")\n} icon: {\n    \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n    "))\n}"
        case "Button":
            return "Button {\n    // Trigger Action\n} label: {\n    HStack {\n        \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n        "))\n        Text(\"Action Button\")\n    }\n}"
        case "ToolbarItem":
            return "ToolbarItem(placement: .primaryAction) {\n    Button(action: {}) {\n        \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n        "))\n    }\n}"
        case "Navigation":
            return "NavigationLink(destination: Text(\"Next View\")) {\n    \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n    "))\n}"
        case "List Row":
            return "HStack {\n    \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n    "))\n    Text(\"List Row Header\")\n}"
        case "Menu":
            return "Menu {\n    Button(\"Action Option\", action: {})\n} label: {\n    \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n    "))\n}"
        case "Context Menu":
            return ".contextMenu {\n    Button(action: {}) {\n        Label(\"Action\", image: \"\(symbol.name)\")\n    }\n}"
        case "TabView":
            return "TabView {\n    Text(\"Home Tab View\")\n        .tabItem {\n            \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n            "))\n            Text(\"Home\")\n        }\n}"
        case "Widget":
            return "struct SimpleWidgetEntryView : View {\n    var body: some View {\n        VStack {\n            \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n            "))\n        }\n    }\n}"
        case "Lock Screen Widget":
            return "struct LockScreenWidgetView : View {\n    var body: some View {\n        \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n        "))\n    }\n}"
        case "macOS Toolbar":
            return "NSToolbarItem {\n    // custom AppKit toolbar representation\n}"
        case "iOS Toolbar":
            return ".toolbar {\n    ToolbarItem(placement: .bottomBar) {\n        \(baseImageDeclaration.replacingOccurrences(of: "\n", with: "\n        "))\n    }\n}"
        default:
            return baseImageDeclaration
        }
    }
}
