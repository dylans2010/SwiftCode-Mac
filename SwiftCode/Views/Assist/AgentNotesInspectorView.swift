import SwiftUI
import AppKit

/// Native macOS desktop inspector for viewing and verifying temporary autonomous execution notes (`agent_notes.md`).
public struct AgentNotesInspectorView: View {
    @Bindable private var notesManager = AgentNotesManager.shared
    @Bindable private var phaseCoordinator = AgentPhaseCoordinator.shared

    @State private var selectedTab: InspectorTab = .formatted
    @State private var searchText: String = ""
    @State private var copiedConfirmation = false

    public enum InspectorTab: String, CaseIterable, Identifiable {
        case formatted = "Formatted Notes"
        case rawMarkdown = "Raw Markdown"
        case phaseTimeline = "350-Phase Matrix"

        public var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentBody
            Divider()
            footerBar
        }
        .frame(minWidth: 550, minHeight: 450)
        .background(.background)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("agent_notes.md")
                        .font(.headline)
                        .fontWeight(.semibold)

                    // Git exclusion badge
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Git-Excluded")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: Capsule())

                    if let timestamp = notesManager.lastSavedTimestamp {
                        Text("• Updated \(timestamp, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let activePhase = phaseCoordinator.activePhase {
                    Text("Active Phase: [\(activePhase.phaseId)] \(activePhase.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Temporary Execution State & Verification Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("View Mode", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        switch selectedTab {
        case .formatted:
            formattedNotesView
        case .rawMarkdown:
            rawMarkdownView
        case .phaseTimeline:
            phaseMatrixView
        }
    }

    // MARK: - Formatted Notes View

    private var formattedNotesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if notesManager.currentNotesMarkdown.isEmpty {
                    ContentUnavailableView(
                        "No Active Notes",
                        systemImage: "doc.badge.gearshape",
                        description: Text("agent_notes.md will be automatically generated upon starting an autonomous engineering task.")
                    )
                    .padding(.top, 40)
                } else {
                    let sections = parseNotesSections(markdown: notesManager.currentNotesMarkdown)
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(section.title)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                            }
                            .padding(.bottom, 2)

                            Text(section.content)
                                .font(.system(size: 12, design: section.isMonospaced ? .monospaced : .default))
                                .foregroundStyle(Color.primary)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Raw Markdown View

    private var rawMarkdownView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
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
            .background(Color.secondary.opacity(0.06))

            Divider()

            ScrollView {
                Text(filteredMarkdown)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var filteredMarkdown: String {
        let text = notesManager.currentNotesMarkdown
        guard !searchText.isEmpty else { return text.isEmpty ? "No active notes." : text }
        let lines = text.components(separatedBy: .newlines)
        let matched = lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return matched.joined(separator: "\n")
    }

    // MARK: - 350-Phase Matrix View

    private var phaseMatrixView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                let completed = phaseCoordinator.completedPhases.count
                let total = phaseCoordinator.phases.count
                Text("Progress: \(completed) / \(total) Phases (\(Int(Double(completed)/Double(total) * 100))%)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(completed), total: Double(total))
                    .tint(.green)
                    .frame(maxWidth: 200)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.04))

            Divider()

            List(phaseCoordinator.phases) { phase in
                HStack(alignment: .top, spacing: 10) {
                    statusIcon(for: phase.status)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(phase.phaseId)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(phase.status == .inProgress ? Color.accentColor : Color.primary)
                            Text("— \(phase.name)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let dur = phase.duration {
                                Text(String(format: "%.2fs", dur))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Text(phase.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        if let evidence = phase.evidence, !evidence.isEmpty {
                            Text("Evidence: \(evidence)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: PhaseStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary.opacity(0.4))
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            if let savedURL = notesManager.lastSavedURL {
                Text(savedURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Stored strictly in ephemeral memory / excluded path.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(notesManager.currentNotesMarkdown, forType: .string)
                copiedConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedConfirmation = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedConfirmation ? "checkmark" : "doc.on.doc")
                    Text(copiedConfirmation ? "Copied" : "Copy Notes")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: - Section Parser

    private struct ParsedSection {
        let title: String
        let content: String
        let isMonospaced: Bool
    }

    private func parseNotesSections(markdown: String) -> [ParsedSection] {
        var sections: [ParsedSection] = []
        let lines = markdown.components(separatedBy: .newlines)
        var currentTitle = "Summary"
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if !currentLines.isEmpty {
                    let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    let isMono = currentTitle.contains("Files") || currentTitle.contains("Tools") || currentTitle.contains("Verification")
                    sections.append(ParsedSection(title: currentTitle, content: content, isMonospaced: isMono))
                    currentLines.removeAll()
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if !line.hasPrefix("# ") {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let isMono = currentTitle.contains("Files") || currentTitle.contains("Tools") || currentTitle.contains("Verification")
            sections.append(ParsedSection(title: currentTitle, content: content, isMonospaced: isMono))
        }

        return sections
    }
}
