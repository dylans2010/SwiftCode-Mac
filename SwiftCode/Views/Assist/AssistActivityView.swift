import SwiftUI
import AppKit

public struct AssistActivityView: View {
    public let activityGroup: AssistActivityGroup
    @State private var isExpanded: Bool
    @State private var selectedFileDiffPath: String?

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
        self._isExpanded = State(initialValue: activityGroup.isExecuting)
    }

    public var body: some View {
        if !activityGroup.hasContent {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                headerButton

                if isExpanded {
                    expandedContent
                }
            }
        }
    }

    private var summaryText: String {
        if !activityGroup.recoveries.isEmpty {
            let resolvedCount = activityGroup.recoveries.filter { $0.isResolved }.count
            return "Recovered from \(resolvedCount) error\(resolvedCount == 1 ? "" : "s")"
        }
        if !activityGroup.workers.isEmpty {
            return "\(activityGroup.workers.count) Worker\(activityGroup.workers.count == 1 ? "" : "s")"
        }
        if let lastBuild = activityGroup.builds.last {
            return lastBuild.status == .completed ? "Build passed" : "Build failed"
        }
        if let lastTest = activityGroup.tests.last {
            return "\(lastTest.passedCount) test\(lastTest.passedCount == 1 ? "" : "s") passed"
        }
        let actionCount = activityGroup.tools.count + activityGroup.terminalCommands.count
        if actionCount > 0 && !activityGroup.files.isEmpty {
            return "\(actionCount) action\(actionCount == 1 ? "" : "s") · \(activityGroup.files.count) file\(activityGroup.files.count == 1 ? "" : "s")"
        }
        if !activityGroup.files.isEmpty {
            return "\(activityGroup.files.count) file\(activityGroup.files.count == 1 ? "" : "s") changed"
        }
        if actionCount > 0 {
            return "\(actionCount) action\(actionCount == 1 ? "" : "s")"
        }
        return "Activity"
    }

    private var headerButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text("Activity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)

                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if activityGroup.isExecuting {
                    ProgressView()
                        .scaleEffect(0.35)
                        .tint(.secondary)
                        .padding(.leading, 2)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide activity details" : "Show activity details")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activityGroup.isExecuting {
                currentStateLine
            }

            if !activityGroup.tools.isEmpty {
                toolsSection
            }

            if !activityGroup.files.isEmpty {
                filesSection
            }

            if !activityGroup.terminalCommands.isEmpty {
                terminalSection
            }

            if !activityGroup.builds.isEmpty {
                buildsSection
            }

            if !activityGroup.tests.isEmpty {
                testsSection
            }

            if !activityGroup.workers.isEmpty {
                workersSection
            }

            if !activityGroup.recoveries.isEmpty {
                recoverySection
            }

            if !activityGroup.verifications.isEmpty {
                verificationsSection
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var currentStateLine: some View {
        HStack(spacing: 5) {
            ProgressView()
                .scaleEffect(0.4)
                .tint(.secondary)
            Text("Current: \(currentStateText)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var currentStateText: String {
        if let lastTool = activityGroup.tools.last, lastTool.status == .running {
            return "Running \(lastTool.toolId)…"
        }
        if let lastBuild = activityGroup.builds.last, lastBuild.status == .running {
            return "Building…"
        }
        if let lastWorker = activityGroup.workers.last, lastWorker.status == .running {
            return "Worker \(lastWorker.name)…"
        }
        if let lastTest = activityGroup.tests.last, lastTest.status == .running {
            return "Running tests…"
        }
        return "Working…"
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Tools", count: activityGroup.tools.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.tools.prefix(10)) { tool in
                    HStack(spacing: 6) {
                        Image(systemName: tool.status.iconName)
                            .font(.system(size: 9))
                            .foregroundStyle(statusColor(tool.status))

                        Text(tool.toolId)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text(tool.purpose)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        if tool.duration > 0 {
                            Text(String(format: "%.1fs", tool.duration))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if activityGroup.tools.count > 10 {
                Text("and \(activityGroup.tools.count - 10) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 15)
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Files", count: activityGroup.files.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.files.prefix(8)) { file in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(file.operation.uppercased())
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))

                            Text(file.filePath)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            if file.addedLines > 0 {
                                Text("+\(file.addedLines)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            if file.deletedLines > 0 {
                                Text("-\(file.deletedLines)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.red)
                            }

                            if file.diffSummary != nil {
                                Button {
                                    if selectedFileDiffPath == file.filePath {
                                        selectedFileDiffPath = nil
                                    } else {
                                        selectedFileDiffPath = file.filePath
                                    }
                                } label: {
                                    Image(systemName: selectedFileDiffPath == file.filePath ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if selectedFileDiffPath == file.filePath, let diff = file.diffSummary {
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(diff.components(separatedBy: "\n").prefix(15), id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(line.hasPrefix("+") ? .green : (line.hasPrefix("-") ? .red : .secondary))
                                    }
                                }
                                .padding(4)
                                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if activityGroup.files.count > 8 {
                Text("and \(activityGroup.files.count - 8) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 15)
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Terminal", count: activityGroup.terminalCommands.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.terminalCommands.prefix(5)) { term in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(term.command)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }

                        if !term.output.isEmpty {
                            Text(term.output)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(3)
                                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
            }

            if activityGroup.terminalCommands.count > 5 {
                Text("and \(activityGroup.terminalCommands.count - 5) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 15)
            }
        }
    }

    private var buildsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Build", count: activityGroup.builds.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.builds.prefix(3)) { build in
                    HStack(spacing: 6) {
                        Image(systemName: build.status == .completed ? "checkmark.circle" : "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(build.status == .completed ? .green : .red)

                        Text(build.status == .completed ? "Build succeeded" : "Build failed (\(build.errorCount) errors)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if build.duration > 0 {
                            Text(String(format: "%.1fs", build.duration))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var testsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Tests", count: activityGroup.tests.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.tests.prefix(3)) { test in
                    HStack(spacing: 6) {
                        Image(systemName: test.failedCount == 0 ? "checkmark.circle" : "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(test.failedCount == 0 ? .green : .red)

                        Text("\(test.suiteName): \(test.passedCount) passed\(test.failedCount > 0 ? ", \(test.failedCount) failed" : "")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
            }
        }
    }

    private var workersSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Workers", count: activityGroup.workers.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.workers.prefix(5)) { worker in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(worker.status == .running ? Color.orange : Color.green)
                            .frame(width: 5, height: 5)

                        Text(worker.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Text("· \(worker.role)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(worker.status.rawValue)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Recovery", count: activityGroup.recoveries.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.recoveries.prefix(3)) { recovery in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)

                        Text("Recovered from \(recovery.domain)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(recovery.attemptNumber)/\(recovery.maxAttempts)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var verificationsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("Verification", count: activityGroup.verifications.count)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(activityGroup.verifications.prefix(5)) { verification in
                    HStack(spacing: 6) {
                        Image(systemName: verification.isPassed ? "checkmark.shield" : "xmark.shield")
                            .font(.system(size: 9))
                            .foregroundStyle(verification.isPassed ? .green : .red)

                        Text(verification.checkName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(verification.details)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("\(count)")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 3)
                .padding(.vertical, 0)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
    }

    private func statusColor(_ status: ActivityStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .retrying: return .orange
        case .skipped: return .secondary
        }
    }
}
