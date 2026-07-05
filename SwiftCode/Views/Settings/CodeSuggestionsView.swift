import SwiftUI

struct CodeSuggestionsView: View {
    @EnvironmentObject private var suggestions: CodeSuggestionsML

    var body: some View {
        NavigationStack {
            List {
                ForEach(CodeSuggestionCategory.allCases, id: \.self) { category in
                    if let items = suggestions.groupedSuggestions[category], !items.isEmpty {
                        Section(category.rawValue) {
                            ForEach(items) { suggestion in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(suggestion.title)
                                        .font(.headline)
                                    Text(suggestion.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let filePath = suggestion.filePath {
                                        Label(filePath, systemImage: "doc.text")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Code Suggestions")
        }
    }
}
