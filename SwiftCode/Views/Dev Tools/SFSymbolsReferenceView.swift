import SwiftUI

struct SymbolCatalogItem: Identifiable, Hashable {
    let id = UUID()
    let systemName: String
    let category: String
}

public struct SFSymbolsReferenceView: View {
    @State private var filterQuery = ""
    @State private var selectedCategory = "All"

    private let categories = ["All", "Navigation", "Devices", "Security", "Formatting", "Media"]

    private let symbols = [
        SymbolCatalogItem(systemName: "chevron.right", category: "Navigation"),
        SymbolCatalogItem(systemName: "arrow.left.and.right", category: "Navigation"),
        SymbolCatalogItem(systemName: "magnifyingglass", category: "Navigation"),
        SymbolCatalogItem(systemName: "iphone", category: "Devices"),
        SymbolCatalogItem(systemName: "ipad", category: "Devices"),
        SymbolCatalogItem(systemName: "macbook.and.iphone", category: "Devices"),
        SymbolCatalogItem(systemName: "shield.fill", category: "Security"),
        SymbolCatalogItem(systemName: "lock.shield", category: "Security"),
        SymbolCatalogItem(systemName: "key.fill", category: "Security"),
        SymbolCatalogItem(systemName: "text.alignleft", category: "Formatting"),
        SymbolCatalogItem(systemName: "bold", category: "Formatting"),
        SymbolCatalogItem(systemName: "italic", category: "Formatting"),
        SymbolCatalogItem(systemName: "play.circle.fill", category: "Media"),
        SymbolCatalogItem(systemName: "pause.fill", category: "Media"),
        SymbolCatalogItem(systemName: "speaker.wave.3", category: "Media")
    ]

    private var filteredSymbols: [SymbolCatalogItem] {
        symbols.filter { s in
            let matchesCategory = selectedCategory == "All" || s.category == selectedCategory
            let matchesFilter = filterQuery.isEmpty || s.systemName.lowercased().contains(filterQuery.lowercased())
            return matchesCategory && matchesFilter
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label("SF Symbols Library", systemImage: "sparkles")
                    .font(.title2.bold())
                Text("Reference catalog of standard SF Symbols categories with instant copy button helpers.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search symbol systemName...", text: $filterQuery)
                            .textFieldStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    Picker("Category Filter", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            List {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    ForEach(filteredSymbols) { item in
                        VStack(spacing: 10) {
                            Image(systemName: item.systemName)
                                .font(.system(size: 24))
                                .frame(height: 40)
                                .foregroundColor(.orange)

                            Text(item.systemName)
                                .font(.system(size: 10, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundColor(.primary)

                            Button("Copy Name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.systemName, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 10)
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
