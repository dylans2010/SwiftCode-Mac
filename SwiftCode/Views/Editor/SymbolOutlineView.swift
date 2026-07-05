import SwiftUI

struct SymbolOutlineView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var symbols: [CodeSymbol] = []
    @State private var searchText = ""
    @State private var selectedKindFilter: CodeSymbol.SymbolKind?

    private var filteredSymbols: [CodeSymbol] {
        symbols
            .filter { selectedKindFilter == nil || $0.kind == selectedKindFilter }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var kindGroups: [CodeSymbol.SymbolKind] {
        Array(Set(symbols.map { $0.kind })).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

                if symbols.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        kindFilterBar
                        Divider().opacity(0.3)
                        symbolList
                    }
                }
            }
            .navigationTitle("Symbol Outline")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Filter Symbols")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    statsMenu
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { analyzeCurrentFile() }
        .onChange(of: projectManager.activeFileContent) { _, _ in analyzeCurrentFile() }
    }

    // MARK: - Kind Filter Bar

    private var kindFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: selectedKindFilter == nil) {
                    selectedKindFilter = nil
                }
                ForEach(kindGroups, id: \.rawValue) { kind in
                    let count = symbols.filter { $0.kind == kind }.count
                    filterChip(
                        label: "\(kind.rawValue.capitalized) (\(count))",
                        isSelected: selectedKindFilter == kind
                    ) {
                        selectedKindFilter = selectedKindFilter == kind ? nil : kind
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.orange.opacity(0.3) : Color.white.opacity(0.07), in: Capsule())
                .foregroundStyle(isSelected ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Symbol List

    private var symbolList: some View {
        List(filteredSymbols) { symbol in
            Button {
                jumpToSymbol(symbol)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol.kind.icon)
                        .font(.caption)
                        .foregroundStyle(kindColor(symbol.kind))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(symbol.name)
                                .font(.callout)
                                .foregroundStyle(symbol.isPrivate ? .secondary : .primary)
                            if symbol.isPrivate {
                                Text("private")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.gray.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text("\(symbol.kind.rawValue.capitalized) · Line \(symbol.lineNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.white.opacity(0.03))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.6))
            Text(projectManager.activeFileNode == nil
                 ? "No File Open"
                 : "No Symbols Found")
                .font(.headline)
                .foregroundStyle(.white)
            Text(projectManager.activeFileNode == nil
                 ? "Open a Swift file to see its symbol outline."
                 : "This file has no detectable symbols (classes, structs, functions, etc.).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Stats Menu

    private var statsMenu: some View {
        Menu {
            let stats = CodeStructureAnalyzer.shared.statistics(for: projectManager.activeFileContent)
            Text("Lines: \(stats.totalLines)")
            Text("Non Empty: \(stats.nonEmptyLines)")
            Text("Comments: \(stats.commentLines)")
            Text("Functions: \(stats.functionCount)")
            Text("Classes: \(stats.classCount)")
            Text("Structs: \(stats.structCount)")
            Text("Complexity Score: \(stats.complexityScore)")
        } label: {
            Image(systemName: "chart.bar")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Logic

    private func analyzeCurrentFile() {
        let content = projectManager.activeFileContent
        guard !content.isEmpty else { symbols = []; return }
        symbols = CodeStructureAnalyzer.shared.analyze(content)
    }

    private func jumpToSymbol(_ symbol: CodeSymbol) {
        // Navigate to the line in the editor via a notification
        NotificationCenter.default.post(
            name: Notification.Name("JumpToLine"),
            object: nil,
            userInfo: ["line": symbol.lineNumber]
        )
    }

    private func kindColor(_ kind: CodeSymbol.SymbolKind) -> Color {
        switch kind {
        case .class:       return .blue
        case .struct:      return .cyan
        case .enum:        return .purple
        case .protocol:    return .green
        case .extension:   return .teal
        case .function:    return .orange
        case .variable:    return .yellow
        case .constant:    return .mint
        case .typeAlias:   return .indigo
        }
    }
}
