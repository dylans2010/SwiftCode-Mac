import SwiftUI

struct SearchSidebarView: View {
    @State private var searchText = ""
    @State private var searchResults: [String] = []

    var body: some View {
        VStack {
            TextField("Search in project", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit {
                    performSearch()
                }

            List(searchResults, id: \.self) { result in
                Text(result)
            }

            if searchResults.isEmpty && !searchText.isEmpty {
                Text("No results found")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func performSearch() {
        // Real logic using grep or similar tool
        Task {
            let tool = GrepTool()
            // Assume we are in a project context - for now search from root
            let results = try? await tool.run(pattern: searchText, directory: ".")
            searchResults = results?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
        }
    }
}
