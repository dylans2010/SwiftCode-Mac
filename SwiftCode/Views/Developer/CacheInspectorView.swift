import SwiftUI

struct CacheInspectorView: View {
    @State private var items = [
        CacheItem(name: "Syntax Highlighting Map", size: "2.4 MB"),
        CacheItem(name: "GitHub Repository Metadata", size: "1.1 MB"),
        CacheItem(name: "LLM Completion History", size: "450 KB"),
        CacheItem(name: "Project File Icons", size: "8.2 MB")
    ]

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.headline)
                            Text(item.size).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear") { items.removeAll { $0.id == item.id } }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("In-Memory Caches")
            }

            Section {
                Button(role: .destructive) { items.removeAll() } label: {
                    Label("Purge All Caches", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Cache Inspector")
    }
}

struct CacheItem: Identifiable {
    let id = UUID()
    let name: String
    let size: String
}
