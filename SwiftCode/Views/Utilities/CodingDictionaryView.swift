import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "CodingDictionaryView")

public struct CodingDictionaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = DictionaryManager.shared
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Panel
            DictionarySidebarView(searchText: $searchText, isSearchFocused: _isSearchFocused)
                .frame(width: 280)
                .background(.background.secondary)

            Divider()

            // Detail Panel
            DictionaryDetailView(searchText: $searchText, isSearchFocused: _isSearchFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .frame(minWidth: 850, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    // Selecting "New" clears the current entry and focuses the search field
                    withAnimation {
                        searchText = ""
                        manager.currentResult = nil
                        manager.errorState = nil
                        isSearchFocused = true
                    }
                } label: {
                    Label("New Search", systemImage: "plus")
                }
                .help("Clear current entry and start a new search")

                Button {
                    if let result = manager.currentResult {
                        manager.search(query: result.query)
                    } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        manager.search(query: searchText)
                    }
                } label: {
                    Label("Refresh Entry", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isLoading || (manager.currentResult == nil && searchText.isEmpty))
                .help("Refresh the current dictionary entry")

                Button {
                    withAnimation {
                        manager.clearHistory()
                    }
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(manager.history.isEmpty)
                .help("Clear all search history")
            }
        }
    }
}

// MARK: - Sidebar View

private struct DictionarySidebarView: View {
    @Bindable var manager = DictionaryManager.shared
    @Binding var searchText: Binding<String>.Value
    @FocusState var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Search Input Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Coding Dictionary")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search terminology, concepts...", text: $searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                manager.search(query: trimmed)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            .padding([.top, .horizontal], 14)

            Divider()

            // Search History Header
            HStack {
                Text("Search History")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !manager.history.isEmpty {
                    Button("Clear") {
                        withAnimation {
                            manager.clearHistory()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 14)

            // History List
            if manager.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No History Yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    // Pinned Items Section
                    let pinned = manager.history.filter { $0.isPinned }
                    if !pinned.isEmpty {
                        Section("Pinned") {
                            ForEach(pinned) { item in
                                historyRow(for: item)
                            }
                        }
                    }

                    // Recent Items Section
                    let recents = manager.history.filter { !$0.isPinned }
                    if !recents.isEmpty {
                        Section("Recents") {
                            ForEach(recents) { item in
                                historyRow(for: item)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private func historyRow(for item: DictionaryHistoryItem) -> some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.query)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            searchText = item.query
            manager.search(query: item.query)
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin Item" : "Pin Item", systemImage: item.isPinned ? "pin.slash" : "pin") {
                withAnimation {
                    manager.togglePin(id: item.id)
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation {
                    manager.deleteHistoryItem(id: item.id)
                }
            }
        }
    }
}

// MARK: - Detail View

private struct DictionaryDetailView: View {
    @Bindable var manager = DictionaryManager.shared
    @Binding var searchText: Binding<String>.Value
    @FocusState var isSearchFocused: Bool

    var body: some View {
        Group {
            if manager.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Consulting developer models...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Cancel") {
                        manager.cancelSearch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if let errorState = manager.errorState {
                DictionaryErrorView(errorState: errorState) {
                    // Retry action
                    manager.search(query: searchText)
                }
            } else if let result = manager.currentResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title Header Area
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(result.kind)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                            .foregroundStyle(.accentColor)

                                        Text(result.category)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                                            .foregroundStyle(.secondary)

                                        Text(result.difficulty)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(difficultyColor(result.difficulty).opacity(0.1)))
                                            .foregroundStyle(difficultyColor(result.difficulty))
                                    }

                                    Text(result.title)
                                        .font(.system(.title, design: .rounded).weight(.bold))
                                        .foregroundStyle(.primary)

                                    Text(result.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Confidence Indicator Card
                                ConfidenceIndicatorView(score: result.confidence)
                            }

                            Divider()
                                .padding(.top, 8)
                        }

                        // Low Confidence Banner Notice
                        if result.confidence < 75 {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.title3)
                                Text("This entry returned lower confidence score. Please double check accuracy and verify with official documentation.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
                        }

                        // Render Sections as collapsible copyable cards
                        VStack(spacing: 14) {
                            if !result.overview.isEmpty {
                                DictionarySectionCard(title: "Overview", icon: "doc.text") {
                                    Text(result.overview)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } copyText: { result.overview }
                            }

                            if !result.definition.isEmpty {
                                DictionarySectionCard(title: "Definition", icon: "book") {
                                    Text(result.definition)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } copyText: { result.definition }
                            }

                            if !result.syntax.isEmpty {
                                DictionarySectionCard(title: "Syntax", icon: "curlybraces") {
                                    DictionaryCodeBlock(code: result.syntax)
                                } copyText: { result.syntax }
                            }

                            if !result.parameters.isEmpty {
                                DictionarySectionCard(title: "Parameters", icon: "list.bullet.indent") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(result.parameters) { param in
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack {
                                                    Text(param.name)
                                                        .font(.system(.subheadline, design: .monospaced).bold())
                                                        .foregroundStyle(.primary)
                                                    if !param.type.isEmpty {
                                                        Text(": \(param.type)")
                                                            .font(.system(.caption, design: .monospaced))
                                                            .foregroundStyle(.accentColor)
                                                    }
                                                }
                                                Text(param.description)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if param.id != result.parameters.last?.id {
                                                Divider()
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: {
                                    result.parameters.map { "\($0.name): \($0.type) - \($0.description)" }.joined(separator: "\n")
                                }
                            }

                            if !result.returnValue.type.isEmpty || !result.returnValue.description.isEmpty {
                                DictionarySectionCard(title: "Return Value", icon: "arrow.uturn.down") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if !result.returnValue.type.isEmpty {
                                            Text(result.returnValue.type)
                                                .font(.system(.subheadline, design: .monospaced).bold())
                                                .foregroundStyle(.primary)
                                        }
                                        if !result.returnValue.description.isEmpty {
                                            Text(result.returnValue.description)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: {
                                    "Type: \(result.returnValue.type)\nDescription: \(result.returnValue.description)"
                                }
                            }

                            if !result.examples.isEmpty {
                                DictionarySectionCard(title: "Examples", icon: "play.circle") {
                                    VStack(alignment: .leading, spacing: 16) {
                                        ForEach(result.examples) { ex in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(ex.title)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.primary)
                                                DictionaryCodeBlock(code: ex.code)
                                            }
                                        }
                                    }
                                } copyText: {
                                    result.examples.map { "Title: \($0.title)\n\($0.code)" }.joined(separator: "\n\n")
                                }
                            }

                            if !result.bestPractices.isEmpty {
                                DictionarySectionCard(title: "Best Practices", icon: "checkmark.circle") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(result.bestPractices, id: \.self) { practice in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "star.fill")
                                                    .foregroundStyle(.yellow)
                                                    .font(.caption)
                                                    .padding(.top, 2)
                                                Text(practice)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: {
                                    result.bestPractices.joined(separator: "\n")
                                }
                            }

                            if !result.commonMistakes.isEmpty {
                                DictionarySectionCard(title: "Common Mistakes", icon: "xmark.circle") {
                                    VStack(alignment: .leading, spacing: 14) {
                                        ForEach(result.commonMistakes) { mistake in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(mistake.description)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.primary)
                                                Text("Why it happens:")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                Text(mistake.explanation)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                Text("How to fix:")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.accentColor)
                                                Text(mistake.fix)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if mistake.id != result.commonMistakes.last?.id {
                                                Divider()
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: {
                                    result.commonMistakes.map { "Mistake: \($0.description)\nExplanation: \($0.explanation)\nFix: \($0.fix)" }.joined(separator: "\n\n")
                                }
                            }

                            if !result.performanceNotes.isEmpty {
                                DictionarySectionCard(title: "Performance", icon: "speedometer") {
                                    Text(result.performanceNotes)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } copyText: { result.performanceNotes }
                            }

                            if !result.threadSafety.isEmpty {
                                DictionarySectionCard(title: "Thread Safety", icon: "lock") {
                                    Text(result.threadSafety)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } copyText: { result.threadSafety }
                            }

                            if !result.securityNotes.isEmpty {
                                DictionarySectionCard(title: "Security", icon: "shield") {
                                    Text(result.securityNotes)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } copyText: { result.securityNotes }
                            }

                            if !result.availability.isEmpty {
                                DictionarySectionCard(title: "Availability", icon: "clock") {
                                    HStack(spacing: 12) {
                                        ForEach(result.availability, id: \.self) { platform in
                                            Text(platform)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: { result.availability.joined(separator: ", ") }
                            }

                            if !result.relatedConcepts.isEmpty {
                                DictionarySectionCard(title: "Related Concepts", icon: "square.on.square") {
                                    FlowLayoutView(items: result.relatedConcepts) { concept in
                                        Button {
                                            searchText = concept
                                            manager.search(query: concept)
                                        } label: {
                                            Text(concept)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Capsule().strokeBorder(Color.accentColor.opacity(0.3)))
                                                .foregroundStyle(.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: { result.relatedConcepts.joined(separator: ", ") }
                            }

                            if !result.warnings.isEmpty {
                                DictionarySectionCard(title: "Warnings", icon: "exclamationmark.triangle") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(result.warnings, id: \.self) { warning in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(.orange)
                                                    .font(.caption)
                                                    .padding(.top, 2)
                                                Text(warning)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: { result.warnings.joined(separator: "\n") }
                            }

                            if !result.notes.isEmpty {
                                DictionarySectionCard(title: "Notes", icon: "info.circle") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(result.notes, id: \.self) { note in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "info.circle.fill")
                                                    .foregroundStyle(.blue)
                                                    .font(.caption)
                                                    .padding(.top, 2)
                                                Text(note)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: { result.notes.joined(separator: "\n") }
                            }

                            if !result.seeAlso.isEmpty {
                                DictionarySectionCard(title: "See Also", icon: "eye") {
                                    FlowLayoutView(items: result.seeAlso) { item in
                                        Button {
                                            searchText = item
                                            manager.search(query: item)
                                        } label: {
                                            Text(item)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                                                .foregroundStyle(.primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: { result.seeAlso.joined(separator: ", ") }
                            }

                            if !result.references.isEmpty {
                                DictionarySectionCard(title: "References", icon: "link") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(result.references, id: \.self) { ref in
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.up.right.circle")
                                                    .foregroundStyle(.secondary)
                                                Text(ref)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .underline()
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } copyText: { result.references.joined(separator: "\n") }
                            }
                        }
                    }
                    .frame(maxWidth: 700)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topCenter)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64, weight: .thin))
                        .foregroundStyle(.tertiary)
                    Text("Coding Dictionary")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Enter any coding question, language element, error, pattern or framework to consult standard models instantly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Focus Search") {
                        isSearchFocused = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(40)
            }
        }
        .onAppear {
            if manager.currentResult == nil {
                isSearchFocused = true
            }
        }
    }

    private func difficultyColor(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "beginner": return .green
        case "intermediate": return .blue
        case "advanced": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Confidence Indicator

private struct ConfidenceIndicatorView: View {
    let score: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text("\(score)% Match")
                .font(.caption.weight(.bold))
                .foregroundStyle(indicatorColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(indicatorColor.opacity(0.1)))
    }

    private var indicatorColor: Color {
        if score >= 95 {
            return .green
        } else if score >= 75 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Section Card

private struct DictionarySectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    let copyText: () -> String

    @State private var isCollapsed = false
    @State private var isCopied = false

    init(title: String, icon: String, @ViewBuilder content: () -> Content, copyText: @escaping () -> String) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.copyText = copyText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.accentColor)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()

                // Actions
                HStack(spacing: 12) {
                    Button {
                        let text = copyText()
                        let pasteboard = NSPasteboard.general
                        pasteboard.declareTypes([.string], owner: nil)
                        pasteboard.setString(text, forType: .string)

                        withAnimation {
                            isCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    } label: {
                        Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(isCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy content")

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand section" : "Collapse section")
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))

            // Card Content
            if !isCollapsed {
                VStack(alignment: .leading) {
                    content
                }
                .padding(14)
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity.combined(with: .move(edge: .top))))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Code Block View

private struct DictionaryCodeBlock: View {
    let code: String
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language format & copy button
            HStack {
                Text("Swift Code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(code, forType: .string)

                    withAnimation {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))

            // Content
            ScrollView(.horizontal, showsIndicators: true) {
                let attr = try? AttributedString(SyntaxHighlighter.shared.highlight(code, fileExtension: "swift"))
                Group {
                    if let attr {
                        Text(attr)
                    } else {
                        Text(code)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .textSelection(.enabled)
            }
            .background(Color.black.opacity(0.15))
        }
        .cornerRadius(8)
    }
}

// MARK: - Error View

private struct DictionaryErrorView: View {
    let errorState: DictionaryErrorState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemIcon)
                .font(.system(size: 56))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            if case .invalidJSON(let rawText) = errorState {
                ScrollView {
                    Text(rawText)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 24)
            }

            HStack(spacing: 12) {
                Button("Retry Query") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    DictionaryManager.shared.errorState = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
    }

    private var systemIcon: String {
        switch errorState {
        case .invalidJSON: return "exclamationmark.bubble"
        case .networkFailure: return "wifi.slash"
        case .modelUnavailable: return "cpu.slash"
        case .timeout: return "timer"
        case .emptyResponse: return "text.badge.xmark"
        }
    }

    private var title: String {
        switch errorState {
        case .invalidJSON: return "Decoding Error"
        case .networkFailure: return "Network Failure"
        case .modelUnavailable: return "Model Unavailable"
        case .timeout: return "Timeout"
        case .emptyResponse: return "Empty Response"
        }
    }

    private var message: String {
        switch errorState {
        case .invalidJSON:
            return "Failed to parse dictionary response from LLMService. The response did not match the required JSON schema."
        case .networkFailure(let desc):
            return "An error occurred calling LLMService: \(desc)"
        case .modelUnavailable:
            return "The selected model is currently unavailable."
        case .timeout:
            return "The request to LLMService timed out."
        case .emptyResponse:
            return "LLMService returned an empty response. Please try again with a different query."
        }
    }
}

// MARK: - Flow Layout Helper

private struct FlowLayoutView: View {
    let items: [String]
    let itemContent: (String) -> AnyView

    init<Content: View>(items: [String], @ViewBuilder itemContent: @escaping (String) -> Content) {
        self.items = items
        self.itemContent = { AnyView(itemContent($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Minimal layout - simple HStack wrapped in scroll or flow if needed.
            // Since we want standard layouts without layout loops:
            var rows: [[String]] {
                var result: [[String]] = []
                var currentRow: [String] = []
                for item in items {
                    currentRow.append(item)
                    if currentRow.count >= 4 {
                        result.append(currentRow)
                        currentRow = []
                    }
                }
                if !currentRow.isEmpty {
                    result.append(currentRow)
                }
                return result
            }

            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex], id: \.self) { item in
                        itemContent(item)
                    }
                    Spacer()
                }
            }
        }
    }
}
