import SwiftUI

// MARK: - Registry search (Open VSX, real results only)

public struct ExtensionsSearchView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var runExtensionId: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search extensions…", text: $query, onCommit: search)
                    .textFieldStyle(.roundedBorder)
                Button("Search", action: search)
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            Divider()
            if manager.isSearching && manager.searchResults.isEmpty {
                ProgressView("Searching the registry…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let searchError = manager.searchError {
                ContentUnavailableView(
                    "Registry unavailable",
                    systemImage: "wifi.slash",
                    description: Text(searchError))
            } else if manager.searchResults.isEmpty {
                ContentUnavailableView(
                    "Search Open VSX",
                    systemImage: "magnifyingglass",
                    description: Text("Results come from the configured registry. Nothing here is hardcoded."))
            } else {
                List(manager.searchResults) { result in
                    let installed = manager.installed.first { $0.id == result.id }
                    ExtensionSidebarRow(
                        metadata: result,
                        state: installed?.state ?? .notInstalled,
                        isInstalling: manager.installingIDs.contains(result.id),
                        onInstall: {
                            Task {
                                do { try await manager.install(metadata: result) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        },
                        onOpen: installed == nil ? nil : {
                            runExtensionId = installed?.id
                        })
                }
                .listStyle(.plain)
                if manager.searchResults.count >= 20 {
                    Button("Load more") { manager.loadMoreSearchResults() }
                        .padding()
                }
            }
        }
        .alert(
            "Installation failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: Binding(
            get: { runExtensionId.map(ExtV2SearchRunSheetID.init(id:)) },
            set: { runExtensionId = $0?.id }
        )) { sheet in
            ExtensionRunView(extensionId: sheet.id)
        }
    }

    private func search() {
        manager.search(query: query)
    }
}

private struct ExtV2SearchRunSheetID: Identifiable {
    let id: String
}
