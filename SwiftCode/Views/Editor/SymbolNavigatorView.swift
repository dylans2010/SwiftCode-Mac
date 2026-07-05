import SwiftUI

struct SymbolNavigatorView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var symbols: [IndexEntry] = []
    @State private var searchText = ""
    @State private var filterKind: IndexEntry.SymbolKind?

    var filteredSymbols: [IndexEntry] {
        var result = symbols
        if let kind = filterKind {
            result = result.filter { $0.kind == kind }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter Symbols", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Kind filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        kindFilterButton(nil, label: "All")
                        ForEach(IndexEntry.SymbolKind.allCases, id: \.self) { kind in
                            kindFilterButton(kind, label: kind.rawValue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                Divider().opacity(0.3)

                // Symbols list
                if filteredSymbols.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(symbols.isEmpty ? "No Symbols Found" : "No Matching Symbols")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredSymbols) { symbol in
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: symbol.kind.icon)
                                    .foregroundStyle(colorForKind(symbol.kind))
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(symbol.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text(symbol.snippet)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(":\(symbol.lineNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Symbols")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadSymbols() }
        }
    }

    private func kindFilterButton(_ kind: IndexEntry.SymbolKind?, label: String) -> some View {
        Button {
            filterKind = kind
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    filterKind == kind
                        ? Color.orange.opacity(0.3)
                        : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(filterKind == kind ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func colorForKind(_ kind: IndexEntry.SymbolKind) -> Color {
        switch kind {
        case .function: return .purple
        case .structType: return .blue
        case .classType: return .yellow
        case .enumType: return .green
        case .variable: return .cyan
        case .constant: return .teal
        case .importDecl: return .gray
        case .protocolType: return .orange
        case .extensionType: return .indigo
        }
    }

    private func loadSymbols() {
        guard let content = projectManager.activeFileNode != nil ? projectManager.activeFileContent : nil,
              let filePath = projectManager.activeFileNode?.path else { return }
        symbols = CodeIndexService.shared.indexFile(content: content, filePath: filePath)
    }
}
