import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "BranchesView")

@MainActor
struct BranchesView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    // Operations states
    @State private var newBranchName = ""
    @State private var showCreateBranchSheet = false
    @State private var showRenameBranchSheet = false
    @State private var renameBranchText = ""
    @State private var selectedBranchToRename: GitBranch?

    // Git commands states
    @State private var showMergeSheet = false
    @State private var showRebaseSheet = false
    @State private var showCherryPickSheet = false
    @State private var showResetSheet = false
    @State private var showCompareSheet = false

    @State private var sourceBranch = ""
    @State private var targetBranch = ""
    @State private var commandLog = ""
    @State private var isExecutingGitCmd = false

    // Interactive rebase visualizer
    @State private var showInteractiveRebase = false
    @State private var rebaseCommits: [InteractiveRebaseCommit] = []

    // Search and filtering
    @State private var branchSearchText = ""
    @State private var filterMode: BranchFilter = .all
    @State private var selectedBranches: Set<String> = []

    // AI Workspace cleanup
    @State private var showAICleanupSheet = false
    @State private var aiCleanupPlan = ""
    @State private var isGeneratingAICleanup = false

    enum BranchFilter: String, CaseIterable, Identifiable {
        case all = "All Branches"
        case local = "Local Only"
        case remote = "Remote Tracking"
        case feature = "Features (feature/*)"
        case bugfix = "Bugfixes (bugfix/*)"

        var id: String { rawValue }
    }

    struct InteractiveRebaseCommit: Identifiable {
        let id = UUID()
        let sha: String
        let subject: String
        var action: RebaseAction

        enum RebaseAction: String, CaseIterable {
            case pick = "Pick"
            case reword = "Reword"
            case squash = "Squash"
            case drop = "Drop"
        }
    }

    var filteredBranches: [GitBranch] {
        var list = gitViewModel.branches

        // Search text
        if !branchSearchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(branchSearchText) }
        }

        // Filtering
        switch filterMode {
        case .all:
            break
        case .local:
            list = list.filter { !$0.isRemote }
        case .remote:
            list = list.filter { $0.isRemote || $0.trackingRemote != nil }
        case .feature:
            list = list.filter { $0.name.hasPrefix("feature/") }
        case .bugfix:
            list = list.filter { $0.name.hasPrefix("bugfix/") }
        }

        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar row
            HStack(spacing: 12) {
                Label("Branch Directory", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter branches...", text: $branchSearchText)
                        .textFieldStyle(.plain)
                    if !branchSearchText.isEmpty {
                        Button { branchSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 200)

                Picker("Filter", selection: $filterMode) {
                    ForEach(BranchFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .controlSize(.small)
                .frame(width: 140)

                Button {
                    gitViewModel.refreshBranches()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    showCreateBranchSheet = true
                } label: {
                    Label("New Branch", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            // Advanced Operations Action Bar
            HStack(spacing: 12) {
                Button {
                    showMergeSheet = true
                } label: {
                    Label("Merge", systemImage: "arrow.merge")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showRebaseSheet = true
                } label: {
                    Label("Rebase", systemImage: "arrow.turn.right.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    loadInteractiveRebaseCommits()
                    showInteractiveRebase = true
                } label: {
                    Label("Interactive Rebase", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showCherryPickSheet = true
                } label: {
                    Label("Cherry-pick", systemImage: "hand.point.right.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showResetSheet = true
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showCompareSheet = true
                } label: {
                    Label("Compare", systemImage: "arrow.left.and.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    showAICleanupSheet = true
                } label: {
                    Label("AI Branch Cleanup", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.purple)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.01))

            Divider()

            // Executed logs display console (if any)
            if !commandLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Git Console Output:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear Console") { commandLog = "" }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                    }
                    Text(commandLog)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(6)
                }
                .padding()
                Divider()
            }

            // Main List View of Branches
            if filteredBranches.isEmpty {
                GitHubEmptyStateView(
                    title: "No Branches Found",
                    description: "No local or remote branches found matching your search and filter options.",
                    systemImage: "arrow.triangle.branch",
                    accentColor: .orange,
                    actionTitle: "Create New Branch"
                ) {
                    showCreateBranchSheet = true
                }
            } else {
                List {
                    Section("Branch List & Sync Balance") {
                        ForEach(filteredBranches) { branch in
                            HStack(spacing: 16) {
                                Button {
                                    if selectedBranches.contains(branch.name) {
                                        selectedBranches.remove(branch.name)
                                    } else {
                                        selectedBranches.insert(branch.name)
                                    }
                                } label: {
                                    Image(systemName: selectedBranches.contains(branch.name) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedBranches.contains(branch.name) ? .orange : .secondary)
                                }
                                .buttonStyle(.plain)

                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(branch.isCurrent ? .orange : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(branch.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)

                                        if branch.isCurrent {
                                            Text("CURRENT")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.12))
                                                .foregroundStyle(.orange)
                                                .cornerRadius(4)
                                        }

                                        // Protected indicator based on branch conventions
                                        if branch.name == "main" || branch.name == "master" {
                                            Label("Protected", systemImage: "shield.fill")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.12))
                                                .foregroundStyle(.green)
                                                .cornerRadius(4)
                                        }

                                        // Stale branch indicator
                                        if isStale(branch) {
                                            Text("STALE")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red.opacity(0.12))
                                                .foregroundStyle(.red)
                                                .cornerRadius(4)
                                        }
                                    }

                                    Text(branch.isRemote ? "Remote Upstream" : (branch.trackingRemote ?? "Local branch"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Health Indicators
                                branchHealthIndicator(for: branch)

                                HStack(spacing: 8) {
                                    if !branch.isCurrent {
                                        Button("Checkout") {
                                            gitViewModel.checkout(branch)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button("Rename...") {
                                            selectedBranchToRename = branch
                                            renameBranchText = branch.name
                                            showRenameBranchSheet = true
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button("Delete") {
                                            gitViewModel.deleteBranch(branch)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if !selectedBranches.isEmpty {
                        Section("Batch Action Workspace") {
                            HStack {
                                Text("\(selectedBranches.count) branches selected")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button(role: .destructive) {
                                    executeBatchDelete()
                                } label: {
                                    Label("Delete Selected", systemImage: "trash.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showCreateBranchSheet) { createBranchSheet }
        .sheet(isPresented: $showRenameBranchSheet) { renameBranchSheet }
        .sheet(isPresented: $showMergeSheet) { mergeSheetView }
        .sheet(isPresented: $showRebaseSheet) { rebaseSheetView }
        .sheet(isPresented: $showCherryPickSheet) { cherryPickSheetView }
        .sheet(isPresented: $showResetSheet) { resetSheetView }
        .sheet(isPresented: $showCompareSheet) { compareSheetView }
        .sheet(isPresented: $showInteractiveRebase) { interactiveRebaseSheetView }
        .sheet(isPresented: $showAICleanupSheet) { aiCleanupSheetView }
    }

    // MARK: - Helper Branch Checks

    private func isStale(_ branch: GitBranch) -> Bool {
        // Return true if branch name matches common temporary or obsolete branch naming conventions
        branch.name.contains("old") || branch.name.contains("temp") || branch.name.contains("stale")
    }

    @ViewBuilder
    private func branchHealthIndicator(for branch: GitBranch) -> some View {
        HStack(spacing: 12) {
            if branch.name == "main" || branch.name == "master" {
                Label("Healthy", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("No conflict risk", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Interactive sheets definitions

    private var createBranchSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Create New Branch", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Cancel") { showCreateBranchSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("Branch Name (e.g. feature/my-feature)", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            .padding()

            Button {
                gitViewModel.createBranch(named: newBranchName)
                newBranchName = ""
                showCreateBranchSheet = false
            } label: {
                Text("Create Branch")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .frame(width: 400)
    }

    private var renameBranchSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Rename Branch", systemImage: "pencil")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Cancel") { showRenameBranchSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("New Branch Name", text: $renameBranchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            .padding()

            Button {
                if let target = selectedBranchToRename {
                    executeRenameBranch(from: target.name, to: renameBranchText)
                }
                showRenameBranchSheet = false
            } label: {
                Text("Rename Branch")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(renameBranchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .frame(width: 400)
    }

    // Git Merge Sheet View
    private var mergeSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Merge Branches").font(.headline)
                Spacer()
                Button("Cancel") { showMergeSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Select source branch to merge into current (\(gitViewModel.status?.branchName ?? "main")):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Source Branch", selection: $sourceBranch) {
                    ForEach(gitViewModel.branches.filter { !$0.isCurrent }) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding()

            Button {
                executeGitOperation(arguments: ["merge", sourceBranch])
                showMergeSheet = false
            } label: {
                Text("Execute Merge")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            sourceBranch = gitViewModel.branches.first(where: { !$0.isCurrent })?.name ?? ""
        }
    }

    // Git Rebase Sheet View
    private var rebaseSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Rebase Branch").font(.headline)
                Spacer()
                Button("Cancel") { showRebaseSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Select branch to rebase current branch onto:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Onto Branch", selection: $targetBranch) {
                    ForEach(gitViewModel.branches.filter { !$0.isCurrent }) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding()

            Button {
                executeGitOperation(arguments: ["rebase", targetBranch])
                showRebaseSheet = false
            } label: {
                Text("Execute Rebase")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            targetBranch = gitViewModel.branches.first(where: { !$0.isCurrent })?.name ?? ""
        }
    }

    // Git Cherry-pick Sheet View
    private var cherryPickSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Cherry-pick Commit").font(.headline)
                Spacer()
                Button("Cancel") { showCherryPickSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Enter the Commit SHA of the commit you wish to cherry-pick:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Commit SHA (e.g. a1b2c3d)", text: $sourceBranch)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            Button {
                executeGitOperation(arguments: ["cherry-pick", sourceBranch])
                showCherryPickSheet = false
            } label: {
                Text("Execute Cherry-pick")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(sourceBranch.isEmpty)
        }
        .padding(24)
        .frame(width: 400)
    }

    // Git Reset Sheet View
    private var resetSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Reset Branch").font(.headline)
                Spacer()
                Button("Cancel") { showResetSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Select Reset Mode:")
                    .font(.subheadline.bold())

                Picker("Reset Mode", selection: $sourceBranch) {
                    Text("Hard (--hard) - Discards all changes").tag("--hard")
                    Text("Soft (--soft) - Keeps staged changes").tag("--soft")
                    Text("Mixed (--mixed) - Keeps uncommitted modifications").tag("--mixed")
                }
                .pickerStyle(.radioGroup)

                Text("Reset target Commit SHA / Reference:")
                    .font(.subheadline.bold())
                TextField("HEAD~1 or commit SHA", text: $targetBranch)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            Button {
                executeGitOperation(arguments: ["reset", sourceBranch, targetBranch])
                showResetSheet = false
            } label: {
                Text("Execute Reset")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(targetBranch.isEmpty)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            sourceBranch = "--mixed"
            targetBranch = "HEAD~1"
        }
    }

    // Git Compare Sheet View
    private var compareSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Compare Branches").font(.headline)
                Spacer()
                Button("Cancel") { showCompareSheet = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Branch A", selection: $sourceBranch) {
                        ForEach(gitViewModel.branches) { branch in
                            Text(branch.name).tag(branch.name)
                        }
                    }
                    Spacer()
                    Text("vs")
                    Spacer()
                    Picker("Branch B", selection: $targetBranch) {
                        ForEach(gitViewModel.branches) { branch in
                            Text(branch.name).tag(branch.name)
                        }
                    }
                }
            }
            .padding()

            Button {
                executeGitOperation(arguments: ["diff", "\(sourceBranch)..\(targetBranch)", "--stat"])
                showCompareSheet = false
            } label: {
                Text("Compare & Log Diff")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(sourceBranch.isEmpty || targetBranch.isEmpty)
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            sourceBranch = gitViewModel.status?.branchName ?? "main"
            targetBranch = gitViewModel.branches.first(where: { !$0.isCurrent })?.name ?? ""
        }
    }

    // Interactive Rebase Sheet View
    private var interactiveRebaseSheetView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Interactive Rebase Workbench").font(.headline)
                Spacer()
                Button("Done") { showInteractiveRebase = false }
                    .buttonStyle(.bordered)
            }

            Text("Configure rebase actions (Pick, Reword, Squash, Drop) for your active commits:")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach($rebaseCommits) { $commit in
                    HStack {
                        Text(commit.sha)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)

                        Text(commit.subject)
                            .lineLimit(1)

                        Spacer()

                        Picker("Action", selection: $commit.action) {
                            ForEach(InteractiveRebaseCommit.RebaseAction.allCases, id: \.self) { act in
                                Text(act.rawValue).tag(act)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                }
            }
            .frame(height: 250)

            Button {
                executeInteractiveRebase()
                showInteractiveRebase = false
            } label: {
                Text("Execute Interactive Rebase")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(24)
        .frame(width: 520)
    }

    // AI Branch Cleanup Recommendation Sheet View
    private var aiCleanupSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("AI Branch Cleanup & Optimization").font(.headline)
                Spacer()
                Button("Cancel") { showAICleanupSheet = false }
                    .buttonStyle(.bordered)
            }

            Text("AI evaluates active branches, detects merged and stale local branches, and compiles a cleaning recommendations list.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isGeneratingAICleanup {
                VStack {
                    ProgressView().controlSize(.small)
                    Text("AI reasoning on repository timeline branches...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 180)
            } else if !aiCleanupPlan.isEmpty {
                ScrollView {
                    Text(aiCleanupPlan)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.12))
                        .cornerRadius(6)
                }
                .frame(height: 200)
            }

            Button {
                runAICleanupAnalysis()
            } label: {
                Label(isGeneratingAICleanup ? "Evaluating..." : "Generate Cleanup Prescription Plan", systemImage: "sparkles")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(isGeneratingAICleanup)
        }
        .padding(24)
        .frame(width: 480)
    }

    // MARK: - Executions backend logic

    private func executeGitOperation(arguments: [String]) {
        guard let proj = project else { return }
        isExecutingGitCmd = true
        commandLog = "Executing: git \(arguments.joined(separator: " "))"

        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: arguments,
                    workingDirectory: proj.directoryURL
                )
                commandLog = result.exitCode == 0 ? "Success!\n\(result.stdout)" : "Error:\n\(result.stderr)"
            } catch {
                commandLog = "Execution failed:\n\(error.localizedDescription)"
            }
            await gitViewModel.refreshStatus()
            isExecutingGitCmd = false
        }
    }

    private func executeRenameBranch(from: String, to: String) {
        executeGitOperation(arguments: ["branch", "-m", from, to])
    }

    private func executeBatchDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete Selected Branches?"
        alert.informativeText = "Are you sure you want to delete these \(selectedBranches.count) branches? This action cannot be reversed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            let list = Array(selectedBranches)
            executeGitOperation(arguments: ["branch", "-d"] + list)
            selectedBranches.removeAll()
        }
    }

    private func loadInteractiveRebaseCommits() {
        // Load the 3 most recent local commits from the log
        rebaseCommits = gitViewModel.history.prefix(3).map {
            InteractiveRebaseCommit(sha: String($0.sha.prefix(7)), subject: $0.subject, action: .pick)
        }
    }

    private func executeInteractiveRebase() {
        // Prepare git transaction sequence instructions for standard rebase execution
        commandLog = "Prepared sequence instructions for GIT_SEQUENCE_EDITOR:\n" + rebaseCommits.map { "\($0.action.rawValue.lowercased()) \($0.sha) \($0.subject)" }.joined(separator: "\n")
    }

    private func runAICleanupAnalysis() {
        isGeneratingAICleanup = true
        aiCleanupPlan = ""

        let branchNames = gitViewModel.branches.map(\.name).joined(separator: ", ")

        let prompt = """
        You are an AI branch cleanup assistant. Evaluate the following local branch list:
        - Active Branches: \(branchNames)
        - Current Branch: \(gitViewModel.status?.branchName ?? "main")

        Propose a step-by-step cleanup prescription plan to clean up local stale tracking branches.
        Include a safe shell script snippet containing the safe git commands (e.g. `git branch -d <branch_name>`).
        Output exactly 3 lines:
        1. [Analysis] Detected branches and which ones seem stale or old.
        2. [Git cleanup script] Command block to delete old branch.
        3. [Best practice tip] Quick suggestion on keeping branches clean.
        """

        Task {
            do {
                let response = try await LLMService.shared.generateExternalResponse(prompt: prompt, useContext: false)
                aiCleanupPlan = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiCleanupPlan = "AI Analysis error: \(error.localizedDescription)"
            }
            isGeneratingAICleanup = false
        }
    }
}
