import SwiftUI

struct ErrorsPanelView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var errors: [CodeError] = []
    @State private var filterSeverity: CodeError.Severity?

    var filteredErrors: [CodeError] {
        if let severity = filterSeverity {
            return errors.filter { $0.severity == severity }
        }
        return errors
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Severity filter
                HStack(spacing: 8) {
                    filterButton(nil, label: "All", count: errors.count)
                    filterButton(.error, label: "Errors", count: errors.filter { $0.severity == .error }.count)
                    filterButton(.warning, label: "Warnings", count: errors.filter { $0.severity == .warning }.count)
                    filterButton(.info, label: "Info", count: errors.filter { $0.severity == .info }.count)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().opacity(0.3)

                if filteredErrors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green.opacity(0.6))
                        Text("No Issues Found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredErrors) { error in
                        Button {
                            navigateToError(error)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: error.severity.icon)
                                    .foregroundStyle(colorForSeverity(error.severity))
                                    .font(.system(size: 14))
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Text(error.fileName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.orange)
                                        Text("Line \(error.lineNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.cyan)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(error.message)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(error.severity.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(colorForSeverity(error.severity))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(colorForSeverity(error.severity).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                        Text(error.source.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(error.filePath)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Errors & Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        analyzeProject()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { analyzeProject() }
        }
    }

    private func filterButton(_ severity: CodeError.Severity?, label: String, count: Int) -> some View {
        Button {
            filterSeverity = severity
        } label: {
            Text("\(label) (\(count))")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    filterSeverity == severity
                        ? Color.orange.opacity(0.3)
                        : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(filterSeverity == severity ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func colorForSeverity(_ severity: CodeError.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .blue
        }
    }

    private func analyzeProject() {
        guard let project = projectManager.activeProject else { return }

        Task {
            do {
                let result = try await BinaryManager.shared.runSwiftLint(at: project.directoryURL.path)
                let parsed = parseSwiftLint(result.stdout, projectRoot: project.directoryURL.path)
                await MainActor.run {
                    errors = parsed
                }
            } catch {
                await MainActor.run {
                    errors = []
                }
            }
        }
    }

    private func parseSwiftLint(_ output: String, projectRoot: String) -> [CodeError] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 5 else { return nil }
            let filePath = String(parts[0]).replacingOccurrences(of: projectRoot + "/", with: "")
            let fileName = URL(fileURLWithPath: String(parts[0])).lastPathComponent
            let lineNumber = Int(parts[1]) ?? 1
            let kind = String(parts[3]).lowercased()
            let severity: CodeError.Severity = kind.contains("error") ? .error : (kind.contains("warning") ? .warning : .info)
            let message = String(parts[4]).trimmingCharacters(in: .whitespaces)
            return CodeError(
                fileName: fileName,
                filePath: filePath,
                lineNumber: lineNumber,
                message: message,
                severity: severity,
                source: .syntaxAnalysis
            )
        }
    }

    private func navigateToError(_ error: CodeError) {
        let node = FileNode(name: error.fileName, path: error.filePath, isDirectory: false)
        projectManager.openFile(node)
        dismiss()
    }
}
