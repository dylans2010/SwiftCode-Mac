import SwiftUI

struct BuildStatusView: View {
    let project: Project
    let owner: String
    let repo: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("github_repo_url") private var savedRepoURL: String = ""

    @State private var workflowRuns: [WorkflowRun] = []
    @State private var releases: [GitHubRelease] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedRun: WorkflowRun?
    @State private var logsText: String?
    @State private var showLogs = false
    @State private var autoRefreshTimer: Timer?
    @State private var showCIBuild = false
    @State private var showPrepareCompile = false
    @State private var showBuildGuide = false
    @State private var showStartCompileConfirmation = false
    @State private var lastBuildTriggerAt: Date?
    private let deduplicationWindow: TimeInterval = 8

    // Compile action state
    @State private var isCompiling = false
    @State private var compileBuildStarted: Date?
    @State private var compileStatus: String = ""
    @State private var compileWorkflowStage: String = ""
    @State private var compileResult: CompileResultStatus = .idle

    enum CompileResultStatus: Equatable {
        case idle, queued, running, success, failed
    }

    private var hasToken: Bool {
        !(KeychainService.shared.get(forKey: KeychainService.githubToken) ?? "").isEmpty
    }

    private var activeRepoURL: URL? {
        if let directURL = URL(string: savedRepoURL), !savedRepoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return directURL
        }
        if !owner.isEmpty, !repo.isEmpty {
            return URL(string: "https://github.com/\(owner)/\(repo)")
        }
        return nil
    }

    private var activeOwnerRepo: (owner: String, repo: String)? {
        guard let url = activeRepoURL else { return nil }
        if let host = url.host, !host.lowercased().contains("github.com") {
            return nil
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }
        let resolvedOwner = pathComponents[0]
        let resolvedRepo = pathComponents[1].replacingOccurrences(of: ".git", with: "")
        guard !resolvedOwner.isEmpty, !resolvedRepo.isEmpty else { return nil }
        return (resolvedOwner, resolvedRepo)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.07, blue: 0.12),
                        Color(red: 0.08, green: 0.08, blue: 0.12),
                        Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if activeOwnerRepo == nil {
                    noRepoView
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Step 1: Repository Connection
                            VStack(alignment: .leading, spacing: 12) {
                                stepHeader(number: 1, title: "Repository Connection", icon: "link")
                                repoHeaderSection
                            }

                            // Step 2: Preparation
                            VStack(alignment: .leading, spacing: 12) {
                                stepHeader(number: 2, title: "Asset Preparation", icon: "wrench.and.screwdriver")
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Prepare Xcode Project files using the internal tool powered by GitHub Actions.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        showPrepareCompile = true
                                    } label: {
                                        Label("Prepare Compiling", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding()
                                .buildStatusCard()
                            }

                            // Step 3: Execution
                            VStack(alignment: .leading, spacing: 12) {
                                stepHeader(number: 3, title: "Build Execution", icon: "play.fill")
                                compileSection

                                Text("Or trigger a full CI workflow for distribution.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)

                                Button {
                                    showCIBuild = true
                                } label: {
                                    Label("Build With CI", systemImage: "cpu")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .padding()
                                .buildStatusCard()
                            }

                            // Step 4: Monitoring & Results
                            VStack(alignment: .leading, spacing: 12) {
                                stepHeader(number: 4, title: "Monitoring & Results", icon: "gauge.with.needle")
                                liveStatusFeed
                                workflowRunsSection
                                releasesSection
                            }

                            Divider().padding(.vertical)

                            localBuildSection
                            buildGuideSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Build Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || activeOwnerRepo == nil)
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .alert("Start Compiling?", isPresented: $showStartCompileConfirmation) {
                Button("Start") { triggerCompile() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will trigger a CI build.")
            }
            .sheet(isPresented: $showLogs) {
                logsSheet
            }
            .sheet(isPresented: $showCIBuild) {
                CIBuildView(project: project)
            }
            .sheet(isPresented: $showPrepareCompile) {
                PrepareCompileWaitingView(project: project)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBuildGuide) {
                BuildGuideView()
            }
            .onAppear {
                loadData()

                autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                    if workflowRuns.contains(where: { $0.isRunning }) || compileResult == .queued || compileResult == .running {
                        loadData()
                    }
                }
            }
            .onDisappear {
                autoRefreshTimer?.invalidate()
                autoRefreshTimer = nil
            }
        }
    }

    // MARK: - Subviews

    private var repoHeaderSection: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "externaldrive.connected.to.line.below.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(activeOwnerRepo.map { "\($0.owner)/\($0.repo)" } ?? "Repository Not Available")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Connected Repository")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if let actionsURL = activeRepoURL?.appending(path: "actions") {
                Link(destination: actionsURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Actions")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.blue)
                }
            }

            if isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding()
        .buildStatusCard()
    }

    // MARK: - Compile Section

    private var compileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Compile", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.white)

            if compileResult != .idle {
                VStack(alignment: .leading, spacing: 8) {
                    if let started = compileBuildStarted {
                        HStack {
                            Text("Started:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(started, style: .time)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }

                    HStack {
                        Text("Status:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(compileStatusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(compileStatusColor)
                    }

                    if !compileWorkflowStage.isEmpty {
                        HStack {
                            Text("Stage:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(compileWorkflowStage)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }

                    if let started = compileBuildStarted {
                        HStack {
                            Text("Duration:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(started, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            Button {
                showStartCompileConfirmation = true
            } label: {
                HStack {
                    if isCompiling {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
                    Text(isCompiling ? "Compiling..." : "Compile")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isCompiling ? Color.gray : Color.orange, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isCompiling)
        }
        .buildStatusCard()
    }

    private var compileStatusLabel: String {
        switch compileResult {
        case .idle: return "Idle"
        case .queued: return "Queued"
        case .running: return "Running"
        case .success: return "Success"
        case .failed: return "Failed"
        }
    }

    private var compileStatusColor: Color {
        switch compileResult {
        case .idle: return .secondary
        case .queued: return .blue
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }

    private var localBuildSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Local Build (Beta)", systemImage: "macmini.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Build your app using a Mac on your local network.")
                .font(.caption)
                .foregroundStyle(.secondary)

            NavigationLink {
                LocalBuildView()
            } label: {
                HStack {
                    Image(systemName: "wifi")
                    Text("Scan For Macs")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .buildStatusCard()
    }

    private var liveStatusFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live Status Feed", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                Text("Current:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(compileStatusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(compileStatusColor)
                Spacer()
                if let lastRun = workflowRuns.first {
                    Text(lastRun.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(logsText.map { String($0.prefix(140)) } ?? "No logs loaded yet. Open a run to preview logs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .buildStatusCard()
    }



    private var ciBuildSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cloud Build (CI)", systemImage: "cpu.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Prepare compilation assets or open CI workflow setup directly from Build Status.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    showPrepareCompile = true
                } label: {
                    Label("Prepare Compiling", systemImage: "wrench.and.screwdriver")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    showCIBuild = true
                } label: {
                    Label("Build With CI", systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .buildStatusCard()
    }

    private var buildGuideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Build Guide", systemImage: "book.fill")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                guideStep(number: 1, text: "Connect a repository in GitHub view (owner/repo).")
                guideStep(number: 2, text: "Run Prepare Compiling to set up the app using Xcode tools.")
                guideStep(number: 3, text: "Use Build With CI to generate or run workflow builds in GitHub Actions.")
                guideStep(number: 4, text: "Monitor Workflow Runs and open logs until build succeeds.")
                guideStep(number: 5, text: "Download artifacts or releases from this screen once complete.")
            }

            Button {
                showBuildGuide = true
            } label: {
                Label("Open Guide View", systemImage: "book")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .buildStatusCard()
    }

    private func stepHeader(number: Int, title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var noRepoView: some View {
        VStack(spacing: 20) {
            Image(systemName: hasToken ? "link.badge.plus" : "key.slash.fill")
                .font(.system(size: 52))
                .foregroundStyle(hasToken ? Color.orange : Color.red)

            Text(hasToken ? "No Repository Connected" : "GitHub Not Configured")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(
                hasToken
                    ? "Open the GitHub panel (the ↺ button in the toolbar) and paste your repository URL to connect."
                    : "Add your GitHub Personal Access Token in Settings, then connect a repository via the GitHub panel."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "1.circle.fill").foregroundStyle(.orange)
                    Text(hasToken ? "Tap the ↺ button in the workspace toolbar" : "Go to Settings → GitHub → add your token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "2.circle.fill").foregroundStyle(.orange)
                    Text(hasToken ? "Enter your repository URL (e.g. https://github.com/owner/repo)" : "Return here after connecting a repository")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Button { dismiss() } label: {
                Label("Close", systemImage: "xmark.circle")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var workflowRunsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Workflow Runs", systemImage: "hammer.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                }
            }

            VStack(spacing: 12) {
                if workflowRuns.isEmpty && !isLoading {
                    Text("No Workflow Runs Found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(workflowRuns.prefix(10)) { run in
                        BuildRunCard(run: run) {
                            selectedRun = run
                            loadLogs(for: run)
                        }
                    }
                }
            }
        }
    }

    private var releasesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Releases", systemImage: "shippingbox.fill")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                if releases.isEmpty && !isLoading {
                    Text("No Releases Yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(releases.prefix(5)) { release in
                        ReleaseRow(release: release)
                    }
                }
            }
        }
    }


    private var logsSheet: some View {
        NavigationStack {
            ScrollView {
                if let logs = logsText {
                    Text(logs)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.85, green: 0.85, blue: 0.85))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView("Loading Logs...")
                        .padding()
                }
            }
            .background(Color(red: 0.11, green: 0.11, blue: 0.14))
            .navigationTitle("Build Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showLogs = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func loadData() {
        guard let repository = activeOwnerRepo else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                async let runsResult = GitHubService.shared.listWorkflowRuns(owner: repository.owner, repo: repository.repo)
                async let relsResult = GitHubService.shared.listReleases(owner: repository.owner, repo: repository.repo)

                let fetchedRuns: [WorkflowRun]
                let fetchedReleases: [GitHubRelease]
                do {
                    fetchedRuns = try await runsResult
                } catch {
                    fetchedRuns = []
                    await MainActor.run {
                        errorMessage = "Workflow Runs: \(error.localizedDescription)"
                    }
                }
                do {
                    fetchedReleases = try await relsResult
                } catch {
                    fetchedReleases = []
                    if await MainActor.run(body: { errorMessage }) == nil {
                        await MainActor.run {
                            errorMessage = "Releases: \(error.localizedDescription)"
                        }
                    }
                }

                await MainActor.run {
                    workflowRuns = fetchedRuns
                    releases = fetchedReleases
                    isLoading = false
                    if let msg = errorMessage {
                        self.errorMessage = msg
                        showError = true
                    }
                }
            }
        }
    }

    private func loadLogs(for run: WorkflowRun) {
        logsText = nil
        showLogs = true
        guard let repository = activeOwnerRepo else { return }
        Task {
            do {
                let logsURL = try await GitHubService.shared.getWorkflowRunLogsURL(
                    owner: repository.owner,
                    repo: repository.repo,
                    runID: run.id
                )
                let (data, _) = try await URLSession.shared.data(from: logsURL)
                let text = String(data: data, encoding: .utf8) ?? "Unable to decode logs."
                await MainActor.run { logsText = text }
            } catch {
                await MainActor.run {
                    logsText = "Error loading logs: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Compile

    private func triggerCompile() {
        guard let repository = activeOwnerRepo else { return }
        if isCompiling { return }
        if let lastBuildTriggerAt, Date().timeIntervalSince(lastBuildTriggerAt) < deduplicationWindow {
            errorMessage = "Duplicate trigger ignored. Please wait a few seconds before starting another build."
            showError = true
            return
        }

        isCompiling = true
        lastBuildTriggerAt = Date()
        compileBuildStarted = Date()
        compileResult = .queued
        compileWorkflowStage = "Triggering Workflow..."

        Task {
            do {
                // Push changes first using GitCommands
                if let project = await ProjectManager.shared.activeProject {
                    compileWorkflowStage = "Pushing Changes..."
                    try await GitCommands.shared.push(
                        project: project,
                        commitMessage: "Build Triggered From SwiftCode"
                    )
                }

                await MainActor.run {
                    compileResult = .running
                    compileWorkflowStage = "Waiting For Workflow..."
                }

                // Poll for the latest workflow run
                try await Task.sleep(nanoseconds: 5_000_000_000)
                try await pollBuildStatus(owner: repository.owner, repo: repository.repo)
            } catch {
                await MainActor.run {
                    compileResult = .failed
                    compileWorkflowStage = "Error: \(error.localizedDescription)"
                    isCompiling = false
                }
            }
        }
    }

    private func pollBuildStatus(owner: String, repo: String) async throws {
        var attempts = 0
        let maxAttempts = 60 // Poll for up to ~5 minutes

        while attempts < maxAttempts {
            let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)

            if let latestRun = runs.first {
                await MainActor.run {
                    workflowRuns = runs
                    compileWorkflowStage = latestRun.name ?? "Build #\(latestRun.runNumber)"

                    switch latestRun.status {
                    case "queued":
                        compileResult = .queued
                    case "in_progress":
                        compileResult = .running
                    case "completed":
                        compileResult = latestRun.conclusion == "success" ? .success : .failed
                        isCompiling = false
                        return
                    default:
                        compileResult = .running
                    }
                }
            }

            try await Task.sleep(nanoseconds: 5_000_000_000)
            attempts += 1
        }

        await MainActor.run {
            compileResult = .failed
            compileWorkflowStage = "Polling Timed Out"
            isCompiling = false
        }
    }
}

// MARK: - Build Run Card

struct BuildRunCard: View {
    let run: WorkflowRun
    let onViewLogs: () -> Void

    var statusColor: Color {
        switch run.conclusion ?? run.status {
        case "success": return .green
        case "failure": return .red
        case "cancelled": return .gray
        case "in_progress", "queued": return .blue
        default: return .secondary
        }
    }

    var statusLabel: String {
        (run.conclusion ?? run.status).replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                if run.isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(statusColor)
                } else {
                    Image(systemName: run.statusBadge)
                        .foregroundStyle(statusColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(run.name ?? "Build #\(run.runNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(run.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onViewLogs()
            } label: {
                Text("Logs")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Release Row

struct ReleaseRow: View {
    let release: GitHubRelease

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text(release.name ?? release.tagName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                Text(release.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Download IPA if available
            if let ipaAsset = release.assets.first(where: { $0.name.hasSuffix(".ipa") }),
               let ipaURL = URL(string: ipaAsset.browserDownloadUrl) {
                Link(destination: ipaURL) {
                    Label("IPA", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.3), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            if let releaseURL = URL(string: release.htmlUrl) {
                Link(destination: releaseURL) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}


struct BuildGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("SwiftCode Build Flow") {
                    guideRow(1, "Connect your repository in the GitHub view.")
                    guideRow(2, "Run Prepare Compiling to verify signing assets and build config.")
                    guideRow(3, "Tap Build With CI to generate/run the workflow.")
                    guideRow(4, "Use Build Status to monitor workflow progress and open logs.")
                    guideRow(5, "Download artifacts/releases once the workflow completes.")
                }

                Section("Tips") {
                    Text("If builds fail, inspect run logs first, then confirm repository secrets and signing files are valid.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func guideRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}


private extension View {
    func buildStatusCard() -> some View {
        self
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
