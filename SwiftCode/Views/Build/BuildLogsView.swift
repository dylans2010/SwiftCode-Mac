import SwiftUI
import UIKit

// MARK: - Structured Log Entry

struct StructuredLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let detail: String?

    enum LogLevel: String, CaseIterable {
        case info = "Info"
        case warning = "Warning"
        case error = "Error"
        case debug = "Debug"

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .debug: return "ant.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .yellow
            case .error: return .red
            case .debug: return .secondary
            }
        }
    }

    enum LogCategory: String, CaseIterable {
        case build = "Build"
        case fileEdit = "File Edit"
        case dependency = "Dependency"
        case agent = "Agent"
        case system = "System"

        var icon: String {
            switch self {
            case .build: return "hammer.fill"
            case .fileEdit: return "doc.text.fill"
            case .dependency: return "shippingbox.fill"
            case .agent: return "sparkles"
            case .system: return "gear"
            }
        }
    }


}


// MARK: - Build Log Manager

@MainActor
final class BuildLogManager: ObservableObject {
    static let shared = BuildLogManager()
    @Published var entries: [StructuredLogEntry] = []

    private init() {}

    func log(_ message: String, level: StructuredLogEntry.LogLevel = .info,
             category: StructuredLogEntry.LogCategory = .system, detail: String? = nil) {
        let entry = StructuredLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            detail: detail
        )
        entries.append(entry)
    }

    func clear() {
        entries = []
    }
}

// MARK: - Build Logs View

struct BuildLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let owner: String
    let repo: String

    @StateObject private var logManager = BuildLogManager.shared
    @State private var logs: [BuildLogEntry] = []
    @State private var isLoading = false
    @State private var selectedRun: WorkflowRunInfo?
    @State private var filterLevel: StructuredLogEntry.LogLevel?

    // AI Chat Assistant state
    @State private var showAssistant = false
    @State private var assistantMessages: [AssistantMessage] = []
    @State private var isAnalyzing = false
    @State private var rawLogsForAnalysis: String = ""
    @State private var lastAnalysisPrompt: String = ""
    @State private var copiedMessageID: UUID?

    struct AssistantMessage: Identifiable {
        let id = UUID()
        let role: Role
        let content: String

        enum Role {
            case system, user, assistant
        }
    }

    struct WorkflowRunInfo {
        let runNumber: Int
        let name: String?
        let status: String
        let conclusion: String?
        let createdAt: Date
    }

    struct BuildLogEntry: Identifiable {
        let id = UUID()
        let runNumber: Int
        let name: String
        let status: String
        let conclusion: String?
        let createdAt: Date
    }

    private var filteredLocalLogs: [StructuredLogEntry] {
        guard let level = filterLevel else { return logManager.entries }
        return logManager.entries.filter { $0.level == level }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        levelFilterButton(nil, label: "All")
                        ForEach(StructuredLogEntry.LogLevel.allCases, id: \.rawValue) { level in
                            levelFilterButton(level, label: level.rawValue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Divider().opacity(0.3)

                if isLoading {
                    ProgressView("Loading Build Logs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredLocalLogs.isEmpty && logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("No Build Logs Available")
                            .foregroundStyle(.secondary)
                        if owner.isEmpty || repo.isEmpty {
                            Text("Connect a GitHub repository to view build logs")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Structured local logs
                        if !filteredLocalLogs.isEmpty {
                            Section("Local Logs") {
                                ForEach(filteredLocalLogs.reversed()) { entry in
                                    structuredLogRow(entry)
                                }
                            }
                        }

                        // Remote CI logs
                        if !logs.isEmpty {
                            Section("CI Builds") {
                                ForEach(logs) { log in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Circle()
                                                .fill(colorForConclusion(log.conclusion))
                                                .frame(width: 8, height: 8)
                                            Text("Build #\(log.runNumber)")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text(log.status)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack {
                                            Text(log.name)
                                                .font(.caption)
                                            Spacer()
                                            Text(log.createdAt, style: .relative)
                                                .font(.caption2)
                                        }
                                        .foregroundStyle(.secondary)

                                        if let conclusion = log.conclusion {
                                            Text(conclusion.capitalized)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(colorForConclusion(log.conclusion).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                                .foregroundStyle(colorForConclusion(log.conclusion))
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Build Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            analyzeLogsWithAssistant()
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        Button {
                            loadLogs()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear { loadLogs() }
            .sheet(isPresented: $showAssistant) {
                buildAssistantSheet
            }
        }
    }

    private func structuredLogRow(_ entry: StructuredLogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.level.icon)
                .foregroundStyle(entry.level.color)
                .font(.system(size: 12))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(Self.timestampFormatter.string(from: entry.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("[\(entry.category.rawValue)]")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(entry.level.color)
                }
                Text(entry.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func levelFilterButton(_ level: StructuredLogEntry.LogLevel?, label: String) -> some View {
        Button {
            filterLevel = level
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    filterLevel == level
                        ? Color.orange.opacity(0.3)
                        : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(filterLevel == level ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func colorForConclusion(_ conclusion: String?) -> Color {
        switch conclusion {
        case "success": return .green
        case "failure": return .red
        case "cancelled": return .yellow
        default: return .blue
        }
    }

    private func loadLogs() {
        guard !owner.isEmpty, !repo.isEmpty else { return }
        isLoading = true
        Task {
            do {
                let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
                await MainActor.run {
                    logs = runs.prefix(20).map { run in
                        BuildLogEntry(
                            runNumber: run.runNumber,
                            name: run.name ?? "Workflow",
                            status: run.status,
                            conclusion: run.conclusion,
                            createdAt: run.createdAt
                        )
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    // MARK: - AI Build Assistant

    private var buildAssistantSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if assistantMessages.isEmpty && !isAnalyzing {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)
                        Text("Build Log Assistant")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text("Analyzes build logs to detect failures,\nexplain errors, and suggest fixes.")
                            .multilineTextAlignment(.center)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button {
                            analyzeLogsWithAssistant()
                        } label: {
                            Label("Analyze Build Logs", systemImage: "wand.and.stars")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.purple.opacity(0.3), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(assistantMessages) { message in
                                assistantMessageBubble(message)
                            }
                            if isAnalyzing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Analyzing Logs...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Build Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showAssistant = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        regenerateAssistantAnalysis()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isAnalyzing || lastAnalysisPrompt.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func assistantMessageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: message.role == .assistant ? "sparkles" : "person.fill")
                        .font(.caption2)
                        .foregroundStyle(message.role == .assistant ? .purple : .orange)
                    Text(message.role == .assistant ? "Assistant" : "You")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                    markdownText(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))

                    if message.role == .assistant {
                        HStack(spacing: 10) {
                            Button {
                                copyAssistantMessage(message)
                            } label: {
                                Label(copiedMessageID == message.id ? "Copied" : "Copy", systemImage: copiedMessageID == message.id ? "checkmark" : "doc.on.doc")
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(copiedMessageID == message.id ? .green : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(
                    message.role == .assistant
                        ? Color.purple.opacity(0.15)
                        : Color.orange.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    private func analyzeLogsWithAssistant() {
        showAssistant = true
        isAnalyzing = true
        copiedMessageID = nil

        Task {
            var logContent = ""

            // 1. Gather local logs
            if !logManager.entries.isEmpty {
                logContent += "--- LOCAL BUILD LOGS ---\n"
                for entry in logManager.entries.suffix(50) {
                    logContent += "[\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)\n"
                    if let detail = entry.detail {
                        logContent += "  Detail: \(detail)\n"
                    }
                }
                logContent += "\n"
            }

            // 2. Gather CI logs from GitHub Actions
            if !owner.isEmpty && !repo.isEmpty {
                do {
                    let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
                    if let failedRun = runs.first(where: { $0.conclusion == "failure" }) {
                        logContent += "--- GITHUB ACTIONS LOGS (Run #\(failedRun.runNumber)) ---\n"
                        let jobs = try await GitHubService.shared.listWorkflowJobs(owner: owner, repo: repo, runID: failedRun.id)
                        for job in jobs where job.conclusion == "failure" {
                            logContent += "\nJob: \(job.name)\n"
                            let logs = try await GitHubService.shared.getJobLogs(owner: owner, repo: repo, jobID: job.id)
                            // Clean logs to remove noise (timestamps, etc. if possible, or just truncate)
                            logContent += logs.suffix(10000) // Get the last 10k characters which usually contain the error
                        }
                    }
                } catch {
                    logContent += "\n[Note: Could not fetch CI logs: \(error.localizedDescription)]\n"
                }
            }

            if logContent.isEmpty {
                logContent = "No build logs available to analyze."
            }

            await MainActor.run {
                let prompt = "Analyze the current build logs and identify any issues."
                lastAnalysisPrompt = prompt
                assistantMessages.append(AssistantMessage(
                    role: .user,
                    content: prompt
                ))
            }

            // 3. Perform AI analysis using OpenRouter (Llama 3.3 70B)
            do {
                let systemPrompt = """
                You are the SwiftCode Build Assistant, an expert in Swift, SwiftUI, and iOS development.
                Your task is to analyze build logs (local and CI) to identify why a build failed.
                Explain the root cause clearly and suggest specific code fixes or configuration changes.
                If there are multiple errors, prioritize the first one that likely caused subsequent failures.
                Be concise but thorough.
                """

                let messages = [
                    AIMessage(role: "user", content: "Analyze these logs:\n\n\(logContent)")
                ]

                let analysis = try await OpenRouterService.shared.chat(
                    messages: messages,
                    model: settings.selectedModel,
                    systemPrompt: systemPrompt
                )

                await MainActor.run {
                    assistantMessages.append(AssistantMessage(
                        role: .assistant,
                        content: analysis
                    ))
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    assistantMessages.append(AssistantMessage(
                        role: .assistant,
                        content: "I encountered an error while analyzing the logs: \(error.localizedDescription)"
                    ))
                    isAnalyzing = false
                }
            }
        }
    }


    private func regenerateAssistantAnalysis() {
        guard !isAnalyzing, !lastAnalysisPrompt.isEmpty else { return }
        analyzeLogsWithAssistant()
    }

    private func markdownText(_ content: String) -> Text {
        if let attributed = try? AttributedString(markdown: content) {
            return Text(attributed)
        }
        return Text(content)
    }

    private func copyAssistantMessage(_ message: AssistantMessage) {
        UIPasteboard.general.string = message.content
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                if copiedMessageID == message.id {
                    copiedMessageID = nil
                }
            }
        }
    }

}
