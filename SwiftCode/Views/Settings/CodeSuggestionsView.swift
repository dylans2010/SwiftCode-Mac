import SwiftUI

struct CodeSuggestionsView: View {
    @EnvironmentObject private var suggestions: CodeSuggestionsML

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Intro card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("A.I. Code Suggestions", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        Text("Review real-time smart suggestions compiled dynamically to streamline your codebase.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Suggestions Categories
                ForEach(CodeSuggestionCategory.allCases, id: \.self) { category in
                    if let items = suggestions.groupedSuggestions[category], !items.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label(category.rawValue, systemImage: "lightbulb.fill")
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                    Spacer()
                                }

                                VStack(spacing: 12) {
                                    ForEach(items) { suggestion in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(suggestion.title)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            Text(suggestion.detail)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineSpacing(4)

                                            if let filePath = suggestion.filePath {
                                                HStack {
                                                    Image(systemName: "doc.text")
                                                        .font(.caption)
                                                        .foregroundStyle(.tertiary)
                                                    Text(filePath)
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .padding(.top, 2)
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(10)
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Code Suggestions")
    }
}
