import SwiftUI

struct SymbolIndexView: View {
    @StateObject private var engine = SymbolIndexingEngine.shared
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var query = ""

    var filtered: [IndexedSymbol] {
        guard !query.isEmpty else { return engine.symbols }
        return engine.symbols.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        AdvancedToolScreen(title: "Symbol Index") {
            AdvancedToolCard(title: "Search Symbols") {
                TextField("Search Symbol", text: $query)
                    .textFieldStyle(.roundedBorder)
            }

            AdvancedToolCard(title: "Indexed Symbols", subtitle: "Open a symbol to jump to file") {
                ForEach(filtered) { symbol in
                    Button("\(symbol.kind): \(symbol.name) — \(symbol.file):\(symbol.line)") {
                        if let node = projectManager.activeProject?.files.flatMapDeep().first(where: { $0.path == symbol.file }) {
                            projectManager.openFile(node)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .onAppear { engine.index(project: projectManager.activeProject) }
    }
}

private extension Array where Element == FileNode {
    func flatMapDeep() -> [FileNode] {
        flatMap { $0.isDirectory ? [$0] + $0.children.flatMapDeep() : [$0] }
    }
}
