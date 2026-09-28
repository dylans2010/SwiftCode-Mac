import SwiftUI
import AppKit

/// Native macOS disclosure control for displaying Assist technical execution details.
public struct AssistActivityView: View {
    public let activityGroup: AssistActivityGroup
    @State private var isExpanded: Bool
    @State private var selectedFileDiffPath: String?

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
        // Default to expanded while actively executing, collapsed when finished
        self._isExpanded = State(initialValue: activityGroup.isExecuting)
    }

    public var body: some View {
        if !activityGroup.hasContent {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Header / Disclosure Toggle
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text("Activity")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("·")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)

                        Text(activityGroup.collapsedSummary)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)

                        if activityGroup.isExecuting {
                            ProgressView()
                                .scaleEffect(0.4)
                                .tint(.orange)
                                .padding(.leading, 2)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide Assist activity" : "Show Assist activity")
                .accessibilityHint("Toggles execution disclosure details")

                // Expanded Disclosure Content
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        // 1. Actions Section
                        if !activityGroup.tools.isEmpty {
                            actionsSection
                        }

                        // 2. Modified Files & Diffs Section
                        if !activityGroup.files.isEmpty {
                            filesSection
                        }

                        // 3. Terminal Commands Section
                        if !activityGroup.terminalCommands.isEmpty {
                            terminalSection
                        }

                        // 4. Build Activity Section
                        if !activityGroup.builds.isEmpty {
                            buildsSection
                        }

                        // 5. Test Activity Section
                        if !activityGroup.tests.isEmpty {
                            testsSection
                        }

                        // 6. Workers Section
                        if !activityGroup.workers.isEmpty {
                            workersSection
                        }

                        // 7. Recovery Section
                        if !activityGroup.recoveries.isEmpty {
                            recoverySection
                        }

                        // 8. Verification Section
                        if !activityGroup.verifications.isEmpty {
                            verificationsSection
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Subsections

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actions")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(activityGroup.tools) { tool in
                    HStack(spacing: 8) {
                        Image(systemName: tool.status.iconName)
                            .font(.caption)
                            .foregroundStyle(tool.status == .completed ? Color.green : (tool.status == .failed ? Color.red : Color.orange))

                        Text(tool.toolId)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text(tool.purpose)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Text(tool.status.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tool.status == .completed ? .green : (tool.status == .failed ? .red : .secondary))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Modified Files")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(activityGroup.files.count)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(activityGroup.files) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(file.operation.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))

                            Text(file.filePath)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            if file.addedLines > 0 {
                                Text("+\(file.addedLines)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            if file.deletedLines > 0 {
                                Text("-\(file.deletedLines)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                                    Text(selectedFileDiffPath == file.filePath ? "Hide Diff" : "View Diff")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View file diff for \(file.filePath)")
                            }
                        }

                        // Expandable inline Diff view
                        if selectedFileDiffPath == file.filePath, let diff = file.diffSummary {
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(diff.components(separatedBy: "\n").prefix(20), id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(line.hasPrefix("+") ? Color.green : (line.hasPrefix("-") ? Color.red : Color.secondary))
                                    }
                                }
                                .padding(6)
                                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .frame(maxHeight: 120)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terminal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            ForEach(activityGroup.terminalCommands) { term in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                        Text(term.command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }

                    if !term.output.isEmpty {
                        Text(term.output)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(4)
                            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private var buildsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            ForEach(activityGroup.builds) { build in
                HStack(spacing: 8) {
                    Image(systemName: build.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(build.status == .completed ? Color.green : Color.red)

                    Text(build.status == .completed ? "Build Succeeded" : "Build Failed (\(build.errorCount) errors)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
            }
        }
    }

    private var testsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tests")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            ForEach(activityGroup.tests) { test in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)

                    Text("\(test.suiteName): \(test.passedCount) passed, \(test.failedCount) failed")
                        .font(.system(size: 11, weight: .medium))

                    Spacer()
                }
            }
        }
    }

    private var workersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Workers")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(activityGroup.workers.count) Active")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            ForEach(activityGroup.workers) { worker in
                HStack(spacing: 8) {
                    Circle()
                        .fill(worker.status == .running ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(worker.name)
                            .font(.system(size: 11, weight: .bold))
                        Text("\(worker.role) · \(worker.scope)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(worker.status.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            ForEach(activityGroup.recoveries) { recovery in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.shield.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recovered from \(recovery.domain)")
                            .font(.system(size: 11, weight: .semibold))
                        Text(recovery.strategy)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(recovery.attemptNumber)/\(recovery.maxAttempts)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }

    private var verificationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            ForEach(activityGroup.verifications) { verification in
                HStack(spacing: 8) {
                    Image(systemName: verification.isPassed ? "checkmark.shield.fill" : "xmark.shield.fill")
                        .foregroundStyle(verification.isPassed ? Color.green : Color.red)

                    Text(verification.checkName)
                        .font(.system(size: 11, weight: .medium))

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
