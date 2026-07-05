import SwiftUI

struct DatabaseInspectorView: View {
    @State private var keys: [String] = []
    @State private var searchText = ""

    var filteredKeys: [String] {
        if searchText.isEmpty { return keys }
        return keys.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filteredKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(String(describing: UserDefaults.standard.value(forKey: key) ?? "nil"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: key)
                        loadKeys()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Database Inspector")
        .searchable(text: $searchText, prompt: "Search keys")
        .onAppear(perform: loadKeys)
        .toolbar {
            Button(role: .destructive) {
                let domain = Bundle.main.bundleIdentifier!
                UserDefaults.standard.removePersistentDomain(forName: domain)
                loadKeys()
            } label: {
                Text("Reset All")
            }
        }
    }

    private func loadKeys() {
        keys = UserDefaults.standard.dictionaryRepresentation().keys.sorted()
    }
}
