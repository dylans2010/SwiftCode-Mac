import SwiftUI

public struct AssistDiffView: View {
    let plan: AssistPlan
    @Environment(\.dismiss) private var dismiss

    public init(plan: AssistPlan) {
        self.plan = plan
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(plan.steps) { step in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.description)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                ForEach(step.actions, id: \.path) { action in
                                    DiffActionView(action: action)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Diff Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct DiffActionView: View {
    let action: AssistAction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForAction(action))
                    .foregroundStyle(colorForAction(action))
                Text(action.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Spacer()
                Text(typeForAction(action))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colorForAction(action))
            }

            if case .modifyFile(_, let patch) = action {
                DiffHunkView(patch: patch)
            } else if case .createFile(_, let content) = action {
                DiffHunkView(patch: content)
            }
        }
        .padding(.top, 4)
    }

    private func iconForAction(_ action: AssistAction) -> String {
        switch action {
        case .createFile: return "plus.circle.fill"
        case .modifyFile: return "pencil.circle.fill"
        case .deleteFile: return "trash.circle.fill"
        case .renameFile: return "arrow.right.circle.fill"
        case .runTest: return "play.circle.fill"
        }
    }

    private func colorForAction(_ action: AssistAction) -> Color {
        switch action {
        case .createFile: return .green
        case .modifyFile: return .blue
        case .deleteFile: return .red
        case .renameFile: return .purple
        case .runTest: return .orange
        }
    }

    private func typeForAction(_ action: AssistAction) -> String {
        switch action {
        case .createFile: return "CREATE"
        case .modifyFile: return "MODIFY"
        case .deleteFile: return "DELETE"
        case .renameFile: return "RENAME"
        case .runTest: return "TEST"
        }
    }
}

struct DiffHunkView: View {
    let patch: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                VStack(alignment: .leading, spacing: 0) {
                    Text(hunk.header)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)

                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var hunks: [(header: String, lines: [String])] {
        let allLines = patch.components(separatedBy: "\n")
        var result: [(header: String, lines: [String])] = []
        var currentHeader = ""
        var currentLines: [String] = []

        for line in allLines {
            if line.hasPrefix("@@") {
                if !currentHeader.isEmpty || !currentLines.isEmpty {
                    result.append((header: currentHeader, lines: currentLines))
                }
                currentHeader = line
                currentLines = []
            } else if !line.hasPrefix("---") && !line.hasPrefix("+++") && !line.hasPrefix("(No changes") {
                currentLines.append(line)
            }
        }
        if !currentHeader.isEmpty || !currentLines.isEmpty {
            result.append((header: currentHeader, lines: currentLines))
        }
        return result
    }
}

struct DiffLineView: View {
    let line: String

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 16, alignment: .trailing)

            Text(content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .background(backgroundColor)
    }

    private var prefix: String {
        if line.hasPrefix("+") { return "+" }
        if line.hasPrefix("-") { return "-" }
        if line.hasPrefix(" ") { return " " }
        return " "
    }

    private var content: String {
        if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
            return String(line.dropFirst())
        }
        return line
    }

    private var prefixColor: Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .secondary
    }

    private var lineColor: Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .primary
    }

    private var backgroundColor: Color {
        if line.hasPrefix("+") { return .green.opacity(0.08) }
        if line.hasPrefix("-") { return .red.opacity(0.08) }
        return .clear
    }
}
