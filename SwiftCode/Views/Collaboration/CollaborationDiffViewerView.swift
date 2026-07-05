import SwiftUI

struct CollaborationDiffViewerView: View {
    enum Mode: String, CaseIterable {
        case inline = "Inline"
        case sideBySide = "Side by Side"
    }

    let diff: String
    @State private var mode: Mode = .inline

    var body: some View {
        VStack {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(parsedLines.enumerated()), id: \.offset) { index, line in
                        if mode == .inline {
                            inlineRow(index: index + 1, line: line)
                        } else {
                            sideBySideRow(index: index + 1, line: line)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .padding()
            }
            .background(Color(.systemGray6))
        }
        .navigationTitle("Diff Viewer")
    }

    private var parsedLines: [String] {
        diff.components(separatedBy: .newlines)
    }

    private func inlineRow(index: Int, line: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(prefix(for: line))
                .foregroundStyle(symbolColor(for: line))
            Text(content(for: line))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(lineColor(line))
    }

    private func sideBySideRow(index: Int, line: String) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            Text(leftContent(for: line))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                .background(line.hasPrefix("-") || isContext(line) ? Color.red.opacity(line.hasPrefix("-") ? 0.12 : 0.03) : .clear)
            Text(rightContent(for: line))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                .background(line.hasPrefix("+") || isContext(line) ? Color.green.opacity(line.hasPrefix("+") ? 0.12 : 0.03) : .clear)
        }
    }

    private func prefix(for line: String) -> String {
        if line.hasPrefix("+") { return "+" }
        if line.hasPrefix("-") { return "-" }
        return " "
    }

    private func content(for line: String) -> String {
        if line.hasPrefix("+") || line.hasPrefix("-") {
            return String(line.dropFirst())
        }
        return line
    }

    private func leftContent(for line: String) -> String {
        line.hasPrefix("+") ? "" : content(for: line)
    }

    private func rightContent(for line: String) -> String {
        line.hasPrefix("-") ? "" : content(for: line)
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.15) }
        if line.hasPrefix("-") { return .red.opacity(0.15) }
        if line.hasPrefix("@@") { return .blue.opacity(0.12) }
        return .clear
    }

    private func symbolColor(for line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .secondary
    }

    private func isContext(_ line: String) -> Bool {
        !line.hasPrefix("+") && !line.hasPrefix("-")
    }
}

struct DiffViewerTestView: View {
    @ObservedObject var manager: CollaborationManager

    var body: some View {
        List {
            Section("Recent Commit Diff") {
                if let lastCommit = manager.commits.commits.first {
                    NavigationLink(lastCommit.message) {
                        CollaborationDiffViewerView(diff: lastCommit.changes.values.first ?? "No diff available")
                    }
                } else {
                    Text("No Commits Yet")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Diffs")
    }
}
