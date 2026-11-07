import SwiftCodeIDECore
import SwiftUI

@MainActor
public struct RepositoryInsightsView: View {
    public var repository: GitRepository
    public var aiAnalysis: ((String) async throws -> String)?

    @State private var analyticsPeriod = "Last 30 Days"
    @State private var isGeneratingAIInsights = false
    @State private var aiInsightsReport = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var commitCount = 0
    @State private var contributorCount = 0
    @State private var topLanguage = ""
    @State private var topLanguageShare = 0.0
    @State private var topAuthorShare = 0.0

    private static let periods: [(label: String, days: Int)] = [
        ("7 Days", 7), ("30 Days", 30), ("12 Months", 365)
    ]

    public init(repository: GitRepository, aiAnalysis: ((String) async throws -> String)? = nil) {
        self.repository = repository
        self.aiAnalysis = aiAnalysis
    }

    private var periodDays: Int {
        Self.periods.first { $0.label == analyticsPeriod }?.days ?? 30
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Repository Productivity Insights")
                        .font(.headline)
                    Spacer()
                    Picker("Timeline Interval", selection: $analyticsPeriod) {
                        ForEach(Self.periods, id: \.label) { period in
                            Text(period.label).tag(period.label)
                        }
                    }
                    .frame(width: 140)
                    .onChange(of: analyticsPeriod) { _, _ in
                        Task { await loadStats() }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Key Repository Metrics")
                        .font(.headline)

                    HStack(spacing: 16) {
                        analyticsStatCard(title: "Commit Velocity", value: "\(commitCount) Commits", subtitle: "In the last \(analyticsPeriod.lowercased())", icon: "clock.fill", color: .purple)
                        analyticsStatCard(title: "Contributor Count", value: "\(contributorCount) Engineer\(contributorCount == 1 ? "" : "s")", subtitle: "Active in this period", icon: "person.3.fill", color: .orange)
                        analyticsStatCard(title: "Language Coverage", value: topLanguage.isEmpty ? "—" : "\(topLanguage) \(Int(topLanguageShare * 100))%", subtitle: "By file count", icon: "curlybraces", color: .teal)
                    }

                    HStack(spacing: 16) {
                        analyticsStatCard(title: "Code Ownership", value: topAuthorShare == 0 ? "—" : "Lead \(Int(topAuthorShare * 100))%", subtitle: "Top author's commit share", icon: "shield.fill", color: .indigo)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Repo Insight Summaries")
                        .font(.headline)

                    Text("Generate a rich natural language summary of your code ownership distributions and commit history activity trends.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await generateAIAnalytics() }
                    } label: {
                        Label(isGeneratingAIInsights ? "Synthesizing Insights…" : "Evaluate AI Insights Summary", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isGeneratingAIInsights || aiAnalysis == nil)
                    .help(aiAnalysis == nil ? "AI insights are not wired up — pass aiAnalysis to enable them." : "")

                    if isGeneratingAIInsights {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !aiInsightsReport.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Generated Summary:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(aiInsightsReport)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.top, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .task { await loadStats() }
    }

    private func analyticsStatCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.headline)
                Spacer()
            }
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        .cornerRadius(6)
    }

    private func loadStats() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let repository = repository
        let since = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date())
        let commits = await Task.detached {
            repository.log(since: since, limit: 10_000)
        }.value
        commitCount = commits.count
        contributorCount = Set(commits.map(\.authorName)).count
        let authorCounts = Dictionary(grouping: commits, by: \.authorName).mapValues(\.count)
        if let top = authorCounts.values.max(), !commits.isEmpty {
            topAuthorShare = Double(top) / Double(commits.count)
        } else {
            topAuthorShare = 0
        }
        let root = repository.root
        let languageShare = await Task.detached {
            Self.languageDistribution(root: root)
        }.value
        topLanguage = languageShare.language
        topLanguageShare = languageShare.share
    }

    private static func languageDistribution(root: URL) -> (language: String, share: Double) {
        let skipped: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods", ".cxx"]
        var counts: [String: Int] = [:]
        var total = 0
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skipped.contains(url.lastPathComponent) { enumerator?.skipDescendants() }
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }
            counts[ext, default: 0] += 1
            total += 1
        }
        guard total > 0, let top = counts.max(by: { $0.value < $1.value }) else {
            return ("", 0)
        }
        return (top.key, Double(top.value) / Double(total))
    }

    private func generateAIAnalytics() async {
        guard let aiAnalysis else { return }
        isGeneratingAIInsights = true
        defer { isGeneratingAIInsights = false }
        let prompt = """
        Summarise this repository's ownership and activity trends from the real data below:
        - Period: \(analyticsPeriod); commits: \(commitCount); contributors: \(contributorCount).
        - Top language: \(topLanguage.isEmpty ? "unknown" : "\(topLanguage) (\(Int(topLanguageShare * 100))% of files)").
        - Top author's commit share: \(Int(topAuthorShare * 100))%.
        Describe code-ownership distribution and commit-history activity trends, and flag any concentration risk.
        """
        do {
            aiInsightsReport = try await aiAnalysis(prompt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
