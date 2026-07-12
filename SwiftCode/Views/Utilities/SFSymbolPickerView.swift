import SwiftUI
import AppKit

// MARK: - Enums & Wrappers

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

// MARK: - Model

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
            // Safe fallback if bundled files are not resolved in bundle
            let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("SwiftCode/Resources/Symbols/\(filename).txt")
            if let content = try? String(contentsOf: fallbackURL, encoding: .utf8) {
                return parseContent(content, version: version)
            }
            return []
        }

        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return parseContent(content, version: version)
        }
        return []
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

// MARK: - SFSymbolPickerView

struct SFSymbolPickerView: View {
    @StateObject private var viewModel = SFSymbolPickerViewModel()
    @State private var selectedSymbol: SFSymbolRecord? = nil
    @State private var isShowingDetail = false
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 110), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Configuration & Search Hub
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Search & Filters", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                Picker("SF Symbols Version", selection: $viewModel.selectedVersion) {
                                    Text("SF Symbols 6").tag(6)
                                    Text("SF Symbols 5").tag(5)
                                    Text("SF Symbols 4").tag(4)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: viewModel.selectedVersion) { _, _ in
                                    viewModel.loadSymbols()
                                }
                                .frame(width: 320)

                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search \(viewModel.symbols.count) symbols...", text: $viewModel.searchQuery)
                                        .textFieldStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Symbols Display Grid Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Symbol Directory", systemImage: "square.grid.2x2.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            if viewModel.isSearching {
                                VStack {
                                    ProgressView()
                                        .controlSize(.large)
                                    Text("Loading symbols from source file...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 200)
                            } else if viewModel.filteredSymbols.isEmpty {
                                ContentUnavailableView(
                                    "No Symbols Found",
                                    systemImage: "doc.text.magnifyingglass",
                                    description: Text("Try adjusting your query or filter.")
                                )
                                .frame(maxWidth: .infinity, minHeight: 200)
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(viewModel.filteredSymbols) { symbol in
                                        symbolCell(symbol)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("SF Symbols Browser")
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
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 52, height: 52)

                    Image(systemName: symbol.name)
                        .font(.title2)
                        .foregroundStyle(.primary)
                }

                Text(symbol.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 24)
            }
            .padding(8)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Sheet

struct SFSymbolDetailSheet: View {
    let symbol: SFSymbolRecord
    @ObservedObject var viewModel: SFSymbolPickerViewModel
    @Environment(\.dismiss) private var dismiss

    // Configuration controls
    @State private var renderingMode: CustomSymbolRenderingMode = .monochrome
    @State private var symbolWeight: PickerSymbolWeightOption = .regular
    @State private var symbolScale: PickerSymbolScaleOption = .large
    @State private var primaryColor: Color = .orange
    @State private var secondaryColor: Color = .blue
    @State private var effectTrigger = false
    @State private var activeEffect = "Pulse"

    // Animation list
    let effects = ["Bounce", "Pulse", "Scale", "Appear", "Disappear"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large Animated Preview Card
                    GroupBox {
                        VStack(spacing: 16) {
                            Text("Animated Live Preview")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.secondary.opacity(0.08))
                                    .frame(width: 140, height: 140)

                                animatedPreviewSymbol()
                            }

                            HStack(spacing: 12) {
                                Button("Trigger Animation") {
                                    effectTrigger.toggle()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)

                                Picker("Effect", selection: $activeEffect) {
                                    ForEach(effects, id: \.self) { effect in
                                        Text(effect).tag(effect)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Symbol Specifications Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Symbol Metadata", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack {
                                Text("Symbol Name")
                                Spacer()
                                Text(symbol.name)
                                    .bold()
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }

                            HStack {
                                Text("SF Symbols Version")
                                Spacer()
                                Text("v\(symbol.version).0")
                                    .bold()
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Button("Copy Symbol Name") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(symbol.name, forType: .string)
                                }
                                .buttonStyle(.bordered)

                                Button(action: {
                                    viewModel.toggleFavorite(symbol.name)
                                }) {
                                    Label(viewModel.favorites.contains(symbol.name) ? "Favorited" : "Add Favorite", systemImage: viewModel.favorites.contains(symbol.name) ? "star.fill" : "star")
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(viewModel.favorites.contains(symbol.name) ? .yellow : .primary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Rendering Adjustments Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Rendering Customization", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Rendering Mode")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Rendering Mode", selection: $renderingMode) {
                                    ForEach(CustomSymbolRenderingMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Symbol Weight")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Weight", selection: $symbolWeight) {
                                    ForEach(PickerSymbolWeightOption.allCases) { weight in
                                        Text(weight.rawValue).tag(weight)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Symbol Scale")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Scale", selection: $symbolScale) {
                                    ForEach(PickerSymbolScaleOption.allCases) { scale in
                                        Text(scale.rawValue).tag(scale)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if renderingMode == .palette {
                                HStack(spacing: 16) {
                                    ColorPicker("Primary Color", selection: $primaryColor)
                                    ColorPicker("Secondary Color", selection: $secondaryColor)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Generated SwiftUI Code Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Generated SwiftUI Code", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(generateSwiftUICode(), forType: .string)
                                }) {
                                    Label("Copy Code", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text(generateSwiftUICode())
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle(symbol.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private func generateSwiftUICode() -> String {
        var code = "Image(systemName: \"\(symbol.name)\")\n"

        let weightStr: String = {
            switch symbolWeight {
            case .ultraLight: return ".ultraLight"
            case .thin: return ".thin"
            case .light: return ".light"
            case .regular: return ".regular"
            case .medium: return ".medium"
            case .semibold: return ".semibold"
            case .bold: return ".bold"
            case .heavy: return ".heavy"
            case .black: return ".black"
            }
        }()

        let scaleStr: String = {
            switch symbolScale {
            case .small: return ".small"
            case .medium: return ".medium"
            case .large: return ".large"
            }
        }()

        code += "    .font(.system(size: 64, weight: \(weightStr)))\n"
        code += "    .imageScale(\(scaleStr))\n"

        switch renderingMode {
        case .monochrome:
            code += "    .symbolRenderingMode(.monochrome)\n"
            code += "    .foregroundStyle(Color.\(primaryColor.description))"
        case .hierarchical:
            code += "    .symbolRenderingMode(.hierarchical)\n"
            code += "    .foregroundStyle(Color.\(primaryColor.description))"
        case .palette:
            code += "    .symbolRenderingMode(.palette)\n"
            code += "    .foregroundStyle(Color.\(primaryColor.description), Color.\(secondaryColor.description))"
        case .multicolor:
            code += "    .symbolRenderingMode(.multicolor)"
        }

        return code
    }

    // MARK: - Animated Symbol Generator

    @ViewBuilder
    private func animatedPreviewSymbol() -> some View {
        let baseImg = Image(systemName: symbol.name)
            .font(.system(size: 64, weight: symbolWeight.fontWeight))
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
}
