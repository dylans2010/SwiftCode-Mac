import SwiftUI
import AppKit

public struct CodeDictionarySearch: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var manager = DictionaryManager.shared
    @State private var query = ""
    @FocusState private var isFieldFocused: Bool

    // List of common search suggestions
    private let suggestions = [
        "VStack", "HStack", "ZStack", "State", "Binding", "Observable", "Task",
        "Actor", "URLSession", "JSONDecoder", "NavigationStack", "Environment",
        "Swift Concurrency", "ARC", "Memory Leak"
    ]

    private var filteredSuggestions: [String] {
        if query.isEmpty { return suggestions }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Spotlight-style Search Input Header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundColor(.secondary)

                TextField("Search terminology, concepts, APIs...", text: $query)
                    .font(.title2)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        performSearch(query)
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("ESC")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider()

            // Spotlight Results & Suggestions List
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if query.isEmpty {
                        // Recent Searches section
                        let recents = manager.history.prefix(5)
                        if !recents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("RECENTS")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.secondary)

                                ForEach(recents) { item in
                                    suggestionRow(item.query, isRecent: true)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }

                        // Static suggestions section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SUGGESTED TOPICS")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)

                            ForEach(suggestions.prefix(8), id: \.self) { sug in
                                suggestionRow(symLabel(sug), actualQuery: sug, isRecent: false)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    } else {
                        // Instant filtering section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MATCHING SUGGESTIONS")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)

                            ForEach(filteredSuggestions, id: \.self) { sug in
                                suggestionRow(sug, isRecent: false)
                            }

                            // Raw query search row
                            suggestionRow("Search for \"\(query)\"...", actualQuery: query, isRecent: false, isCustomQuery: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 280)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .frame(width: 500)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 25, x: 0, y: 15)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func symLabel(_ term: String) -> String {
        return term
    }

    @ViewBuilder
    private func suggestionRow(_ label: String, actualQuery: String? = nil, isRecent: Bool, isCustomQuery: Bool = false) -> some View {
        let q = actualQuery ?? label
        Button {
            performSearch(q)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isCustomQuery ? "sparkles" : (isRecent ? "clock" : "doc.text.magnifyingglass"))
                    .foregroundColor(isCustomQuery ? .purple : .secondary)

                Text(label)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "return")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func performSearch(_ targetQuery: String) {
        let trimmed = targetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Update active text and execute search
        CodingDictionaryCoordinator.shared.searchText = trimmed
        manager.search(query: trimmed)
        dismiss()
    }
}
