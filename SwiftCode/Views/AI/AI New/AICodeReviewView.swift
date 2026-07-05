import SwiftUI

// MARK: - Code Review View

struct AICodeReviewView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var reviewManager = AgentCodeReviewManager.shared

    @State private var selectedResult: CodeReviewResult?
    @State private var showIssueDetail: CodeReviewIssue?
    @State private var selectedSeverityFilter: CodeReviewIssue.Severity?
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.06, blue: 0.18),
                             Color(red: 0.10, green: 0.10, blue: 0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if reviewManager.isReviewing {
                    reviewingView
                } else if let result = reviewManager.currentResult {
                    resultView(result)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Code Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHistory.toggle()
                    } label: {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await startReview() }
                    } label: {
                        Label("Review", systemImage: "magnifyingglass.circle.fill")
                            .foregroundStyle(.purple)
                    }
                    .disabled(reviewManager.isReviewing || projectManager.activeFileNode == nil)
                }
            }
            .sheet(item: $showIssueDetail) { issue in
                AICodeReviewIssueDetailSheet(issue: issue)
            }
            .sheet(isPresented: $showHistory) {
                reviewHistorySheet
            }
            .alert("Review Error", isPresented: .constant(reviewManager.errorMessage != nil), presenting: reviewManager.errorMessage) { _ in
                Button("OK") { reviewManager.errorMessage = nil }
            } message: { msg in Text(msg) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 52))
                .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))

            Text("AI Code Review")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Open a Swift file and tap Review to get an AI-powered code review with issue detection, suggestions, and a quality score.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if projectManager.activeFileNode != nil {
                Button {
                    Task { await startReview() }
                } label: {
                    Label("Review Current File", systemImage: "magnifyingglass.circle.fill")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    // MARK: - Reviewing State

    private var reviewingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.purple)
            Text("AI is reviewing your code…")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Analyzing structure, patterns, and potential issues")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result View

    private func resultView(_ result: CodeReviewResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Score card
                scoreCard(result)

                // Severity filter
                severityFilter(result)

                // Issues list
                let filtered = filteredIssues(result)
                if filtered.isEmpty {
                    Text("No issues found for this filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(filtered) { issue in
                        AICodeReviewIssueRowView(issue: issue) {
                            showIssueDetail = issue
                        } onResolve: {
                            reviewManager.markResolved(issue, in: result)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }

    private func scoreCard(_ result: CodeReviewResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.fileName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    Text(result.reviewedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(scoreColor(result.overallScore).opacity(0.3), lineWidth: 4)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: CGFloat(result.overallScore) / 100)
                        .stroke(scoreColor(result.overallScore), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    Text("\(result.overallScore)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(result.overallScore))
                }
            }

            Text(result.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statBadge(label: "Critical", count: result.criticalCount, color: .red)
                statBadge(label: "Warnings", count: result.warningCount, color: .orange)
                statBadge(label: "Unresolved", count: result.unresolvedCount, color: .yellow)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func severityFilter(_ result: CodeReviewResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", count: result.issues.count, isSelected: selectedSeverityFilter == nil) {
                    selectedSeverityFilter = nil
                }
                ForEach(CodeReviewIssue.Severity.allCases, id: \.rawValue) { severity in
                    let count = result.issues.filter { $0.severity == severity }.count
                    if count > 0 {
                        filterChip(label: severity.rawValue, count: count, isSelected: selectedSeverityFilter == severity) {
                            selectedSeverityFilter = selectedSeverityFilter == severity ? nil : severity
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple.opacity(0.4) : Color.white.opacity(0.06), in: Capsule())
            .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func filteredIssues(_ result: CodeReviewResult) -> [CodeReviewIssue] {
        guard let filter = selectedSeverityFilter else { return result.issues }
        return result.issues.filter { $0.severity == filter }
    }

    // MARK: - Review History Sheet

    private var reviewHistorySheet: some View {
        NavigationStack {
            List {
                ForEach(reviewManager.reviewResults) { result in
                    Button {
                        reviewManager.currentResult = result
                        showHistory = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.fileName)
                                    .font(.callout.bold())
                                    .foregroundStyle(.primary)
                                Text(result.reviewedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(result.overallScore)")
                                .font(.title3.bold())
                                .foregroundStyle(scoreColor(result.overallScore))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.forEach { idx in
                        reviewManager.deleteResult(reviewManager.reviewResults[idx])
                    }
                }
            }
            .navigationTitle("Review History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showHistory = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    private func startReview() async {
        guard let node = projectManager.activeFileNode,
              !projectManager.activeFileContent.isEmpty else { return }
        await reviewManager.reviewCode(
            code: projectManager.activeFileContent,
            fileName: node.name
        )
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func statBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.caption.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Issue Row View

struct AICodeReviewIssueRowView: View {
    let issue: CodeReviewIssue
    let onDetail: () -> Void
    let onResolve: () -> Void

    var body: some View {
        Button(action: onDetail) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: issue.severity.icon)
                    .foregroundStyle(severityColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(issue.category.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(severityColor.opacity(0.2), in: Capsule())
                            .foregroundStyle(severityColor)
                        if let line = issue.lineNumber {
                            Text("Line \(line)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if issue.isResolved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(issue.description)
                        .font(.caption)
                        .foregroundStyle(issue.isResolved ? .secondary : .primary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(severityColor.opacity(0.2), lineWidth: 1)
            )
            .opacity(issue.isResolved ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !issue.isResolved {
                Button { onResolve() } label: {
                    Label("Mark Resolved", systemImage: "checkmark.circle")
                }
            }
            Button { onDetail() } label: {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .critical: return .red
        case .warning:  return .orange
        case .info:     return .blue
        case .style:    return .purple
        }
    }
}

// MARK: - Issue Detail Sheet

struct AICodeReviewIssueDetailSheet: View {
    let issue: CodeReviewIssue
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: issue.severity.icon)
                            .foregroundStyle(severityColor)
                        Text(issue.severity.rawValue)
                            .font(.headline)
                            .foregroundStyle(severityColor)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(issue.category.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let line = issue.lineNumber {
                        Label("Line \(line)", systemImage: "number.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Group {
                        Text("Issue").font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(issue.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    Divider().opacity(0.3)

                    Group {
                        Text("Suggestion").font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(issue.suggestion)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    if let snippet = issue.codeSnippet, !snippet.isEmpty {
                        Divider().opacity(0.3)
                        Text("Code").font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                        ScrollView(.horizontal) {
                            Text(snippet)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(10)
                        }
                        .background(Color(red: 0.11, green: 0.11, blue: 0.15), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea())
            .navigationTitle("Issue Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var severityColor: Color {
        switch issue.severity {
        case .critical: return .red
        case .warning:  return .orange
        case .info:     return .blue
        case .style:    return .purple
        }
    }
}
