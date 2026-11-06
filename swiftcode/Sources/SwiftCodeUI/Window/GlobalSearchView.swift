// Ported from Legacy `SwiftCode/Views/Utilities/NSPersonalDocumentation/Views/GlobalSearchView.swift`
// (Dylan's own code; direct port authorised under MIT). Destination:
// SwiftCodeUI/Window/ — next to its consumer `NSPersonalDocumentationView`.
//
// Destination adaptations (the Legacy file cannot land verbatim):
// - `SearchManager.SearchResult` does not exist in production. The search
//   entry point is `PersonalDocStore.search(query:) -> [PersonalDocSearchResult]`
//   (`SwiftCodeIDEShell/PersonalDocumentationModel.swift:640`); the result
//   shape is the same (`document` + `snippet`, `document.id/.title/
//   .moduleKind`), so the view uses `[PersonalDocSearchResult]`.
// - Legacy called `coordinator.search.search(query:)`; the production
//   coordinator exposes the store as `coordinator.store`, so the call is
//   `coordinator.store.search(query:)`.
// - `result.document.moduleKind` is `PersonalDocModuleKind` (not the
//   Legacy `ModuleKind`); it has `.icon` and `.rawValue`, and `.accentColor`
//   was added alongside this port (same Legacy logic).
// - `NativeSearchField` and the `.liquidGlass` modifier already exist in
//   production; `coordinator.selectedModuleKind` / `selectedDocumentID`
//   exist on the production coordinator.
// - NOTE: `PersonalDocumentationCoordinator` lives in SwiftCodeIDEShell,
//   which SwiftCodeUI does not depend on in Package.swift yet — same gap
//   already flagged on `NSPersonalDocumentationView.swift` (G-DEPS owns
//   config). This file does not add the import; the dependency must land
//   in Package.swift first.

import SwiftUI

struct GlobalSearchView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var query = ""
    @State private var results: [PersonalDocSearchResult] = []

    var body: some View {
        VStack(spacing: 0) {
            NativeSearchField(text: $query, placeholder: "Search all personal documentation...")
                .padding(16)
                .liquidGlass(style: .subtle, cornerRadius: 0)
                .onChange(of: query) { _, _ in
                    performSearch()
                }

            Divider()

            if results.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "Start typing to search" : "No results found", systemImage: "magnifyingglass")
                } description: {
                    Text(query.isEmpty ? "Search spanning all document types, smart collections, and attachment metadata." : "Check spelling or try using different keywords.")
                }
            } else {
                List(results) { result in
                    Button {
                        coordinator.selectedModuleKind = result.document.moduleKind
                        coordinator.selectedDocumentID = result.document.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: result.document.moduleKind.icon)
                                    .foregroundStyle(result.document.moduleKind.accentColor)
                                Text(result.document.title)
                                    .font(.body.bold())
                                Spacer()
                                Text(result.document.moduleKind.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func performSearch() {
        // Production `PersonalDocStore.search(query:)` does not throw
        // (Legacy's did), so no `try?` here.
        results = coordinator.store.search(query: query)
    }
}
