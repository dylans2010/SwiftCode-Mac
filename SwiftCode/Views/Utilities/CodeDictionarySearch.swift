import SwiftUI
import AppKit

public struct CodeDictionarySearch: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isFieldFocused: Bool
    @State private var hoveredItem: String? = nil
    @State private var selectedCategory = "All"

    // List of common search suggestions
    private let suggestions = [
        "VStack", "HStack", "ZStack", "State", "Binding", "Observable", "Task",
        "Actor", "URLSession", "JSONDecoder", "NavigationStack", "Environment",
        "Swift Concurrency", "ARC", "Memory Leak"
    ]

    private let categories = ["All", "UI", "Concurrency", "Git", "Tooling"]

    private var filteredSuggestions: [String] {
        let base = query.isEmpty ? suggestions : suggestions.filter { $0.localizedCaseInsensitiveContains(query) }
        switch selectedCategory {
        case "UI":
            return base.filter { ["VStack", "HStack", "ZStack", "NavigationStack", "State", "Binding"].contains($0) }
        case "Concurrency":
            return base.filter { ["Task", "Actor", "Swift Concurrency"].contains($0) }
        case "Git":
            return base.filter { ["Git", "Clone", "Push", "Pull"].contains($0) }
        case "Tooling":
            return base.filter { ["URLSession", "JSONDecoder", "Environment", "ARC", "Memory Leak"].contains($0) }
        default:
            return base
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Spotlight-style Search Input Header
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.orange.gradient)

                TextField("Search terminology, concepts, APIs...", text: $query)
                    .font(.system(.title3, design: .rounded))
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
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

            Divider()

            // Category filter pills
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        withAnimation {
                            selectedCategory = cat
                        }
                    } label: {
                        Text(cat)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedCategory == cat ? Color.orange.opacity(0.15) : Color.primary.opacity(0.05), in: Capsule())
                            .foregroundColor(selectedCategory == cat ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Spotlight Results & Suggestions List
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.isEmpty {
                        // Recent Searches section
                        let recents = DictionaryManager.shared.history.prefix(5)
                        if !recents.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "clock")
                                    Text("RECENTS")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.secondary)

                                ForEach(recents) { item in
                                    suggestionRow(item.query, isRecent: true)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        }

                        // Static suggestions section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("SUGGESTED TOPICS")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.secondary)

                            ForEach(filteredSuggestions.prefix(8), id: \.self) { sug in
                                suggestionRow(symLabel(sug), actualQuery: sug, isRecent: false)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    } else {
                        // Instant filtering section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("MATCHING SUGGESTIONS")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.secondary)

                            ForEach(filteredSuggestions, id: \.self) { sug in
                                suggestionRow(sug, isRecent: false)
                            }

                            // Raw query search row
                            suggestionRow("Search for \"\(query)\"...", actualQuery: query, isRecent: false, isCustomQuery: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxHeight: 320)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .frame(width: 520)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
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
        let isHovered = hoveredItem == label

        Button {
            performSearch(q)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isCustomQuery ? "sparkle" : (isRecent ? "clock.fill" : "doc.text.magnifyingglass"))
                    .font(.system(size: 14))
                    .foregroundColor(isCustomQuery ? .orange : (isHovered ? .orange : .secondary))
                    .frame(width: 20)

                Text(label)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(isHovered ? .orange : .primary)

                Spacer()

                Image(systemName: "return")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 0.8 : 0.3)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isHovered ? Color.orange.opacity(0.08) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.snappy(duration: 0.15)) {
                if hover {
                    hoveredItem = label
                } else if hoveredItem == label {
                    hoveredItem = nil
                }
            }
        }
    }

    private func performSearch(_ targetQuery: String) {
        let trimmed = targetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Update active text and execute search
        CodingDictionaryCoordinator.shared.searchText = trimmed
        CodingDictionaryCoordinator.shared.showingSpotlight = false
        DictionaryManager.shared.search(query: trimmed)
        dismiss()
    }
}
