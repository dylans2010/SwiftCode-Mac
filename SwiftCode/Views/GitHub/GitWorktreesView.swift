import SwiftUI
import AppKit

struct GitWorktreesView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore

    // Core Managers & ViewModel Reference
    @State private var manager = WorktreeManager.shared

    // UI state
    @State private var selectedWorktree: GitWorktree? = nil
    @State private var searchQuery = ""
    @State private var filterCategory = "All"
    @State private var sortOption: SortOption = .name

    // Guided wizard creation states
    @State private var showCreateWizard = false
    @State private var newWorktreePath = ""
    @State private var newWorktreeBranch = ""
    @State private var isCreatingNewBranch = false
    @State private var customNewBranchName = ""

    // Additional sheets
    @State private var showLockReasonSheet = false
    @State private var lockReasonText = ""
    @State private var worktreeToLock: GitWorktree? = nil

    enum SortOption: String, CaseIterable, Identifiable {
        case branch = "Branch"
        case repository = "Repository"
        case name = "Name"
        case path = "Path"
        case lastCommit = "Last Commit"
        case recentlyOpened = "Recently Opened"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

    // Filter categories mapping
    let filterCategories = [
        "All", "Main Worktrees", "Dirty", "Clean", "Locked", "Favorites"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // GroupBox 1: Global Actions & Utilities
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Worktree Management Hub", systemImage: "arrow.triangle.branch")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Text("Manage separate Git worktrees linked to the active project workspace. You can work on multiple branches simultaneously without stash conflicts.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Divider()

                            HStack(spacing: 12) {
                                Button {
                                    showCreateWizard = true
                                } label: {
                                    Label("Add Worktree", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)

                                Button {
                                    refreshWorktrees()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    pruneStale()
                                } label: {
                                    Label("Prune Stale", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    repairWorktrees()
                                } label: {
                                    Label("Repair", systemImage: "wrench.and.screwdriver")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox 2: Catalog & Filter Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Repository Worktrees Catalog", systemImage: "folder.badge.gearshape")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            // Search & Sort parameters
                            HStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search worktrees...", text: $searchQuery)
                                        .textFieldStyle(.plain)
                                        .autocorrectionDisabled()

                                    if !searchQuery.isEmpty {
                                        Button {
                                            searchQuery = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                                Picker("Sort", selection: $sortOption) {
                                    ForEach(SortOption.allCases) { opt in
                                        Text(opt.rawValue).tag(opt)
                                    }
                                }
                                .frame(width: 140)
                            }

                            // Filter Category picker
                            Picker("Filter Category", selection: $filterCategory) {
                                ForEach(filterCategories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .pickerStyle(.segmented)

                            Divider()

                            // Worktree List Rows
                            if manager.isRefreshing && manager.worktrees.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView("Scanning repository worktrees...").controlSize(.small)
                                    Spacer()
                                }
                                .padding()
                            } else if filteredWorktrees.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No worktrees matching current query.")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .padding()
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(filteredWorktrees) { wt in
                                        worktreeRow(wt)
                                        if wt != filteredWorktrees.last {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox 3: Selected Worktree Inspector & Details
                    if let wt = selectedWorktree {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Selected Worktree Inspector", systemImage: "info.circle")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Spacer()

                                    Button {
                                        selectedWorktree = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(wt.relativePath)
                                    .font(.title2.bold())

                                Text(wt.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Divider()

                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                                    GridRow {
                                        Text("Branch:").bold()
                                        Text(wt.branch ?? "Detached HEAD")
                                            .foregroundColor(wt.isDetached ? .red : .primary)
                                    }
                                    GridRow {
                                        Text("HEAD Commit:").bold()
                                        Text(wt.headSHA)
                                            .font(.caption.monospaced())
                                    }
                                    if !wt.commitMessage.isEmpty {
                                        GridRow {
                                            Text("Commit Msg:").bold()
                                            Text(wt.commitMessage).italic()
                                        }
                                    }
                                    GridRow {
                                        Text("Lock Status:").bold()
                                        Text(wt.isLocked ? "Locked (\(wt.lockReason ?? ""))" : "Unlocked")
                                            .foregroundColor(wt.isLocked ? .red : .green)
                                    }
                                }
                                .font(.subheadline)

                                Divider()

                                FlowLayout(spacing: 8) {
                                    Button {
                                        openWorktreeInSwiftCode(wt)
                                    } label: {
                                        Label("Open in SwiftCode", systemImage: "laptopcomputer")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)

                                    Button {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: wt.path)
                                    } label: {
                                        Label("Reveal in Finder", systemImage: "folder")
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        openInTerminal(wt.path)
                                    } label: {
                                        Label("Terminal", systemImage: "terminal")
                                    }
                                    .buttonStyle(.bordered)

                                    if wt.isLocked {
                                        Button {
                                            unlockWorktree(wt)
                                        } label: {
                                            Label("Unlock", systemImage: "lock.open")
                                        }
                                        .buttonStyle(.bordered)
                                    } else {
                                        Button {
                                            worktreeToLock = wt
                                            lockReasonText = ""
                                            showLockReasonSheet = true
                                        } label: {
                                            Label("Lock", systemImage: "lock")
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    Button(role: .destructive) {
                                        removeWorktree(wt)
                                    } label: {
                                        Label("Remove...", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // GroupBox 4: Background Execution Log Stream
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Live Output Log Stream", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }

                            ScrollView {
                                Text(manager.liveCommandLogs.isEmpty ? "No active background logs." : manager.liveCommandLogs)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.12))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 120)

                            if manager.activeProcess != nil {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Executing background Git Process...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Cancel Operation") {
                                        manager.cancelActiveProcess()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .navigationTitle("Git Worktrees")
        }
        .onAppear {
            if let activeURL = sessionStore.activeProject?.directoryURL {
                Task {
                    await manager.refresh(repositoryURL: activeURL)
                }
            }
        }
        .sheet(isPresented: $showCreateWizard) {
            creationWizardView
        }
        .sheet(isPresented: $showLockReasonSheet) {
            lockReasonInputSheet
        }
    }

    // MARK: - Row Subview

    private func worktreeRow(_ wt: GitWorktree) -> some View {
        let isSelected = selectedWorktree?.path == wt.path
        let isActive = sessionStore.activeProject?.directoryURL.path == wt.path

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(wt.relativePath)
                        .font(.subheadline.bold())
                        .foregroundColor(isSelected ? .accentColor : .primary)

                    if wt.isMain {
                        Text("MAIN")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }

                Text(wt.branch ?? "Detached HEAD")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if wt.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.red)
            }

            // Favorite/Pin actions
            Button {
                manager.toggleFavorite(for: wt)
            } label: {
                Image(systemName: wt.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(wt.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            Button("Inspect") {
                selectedWorktree = wt
                manager.updateLastOpened(for: wt)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Guided Wizard Creation Sheet

    private var creationWizardView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create Guided Worktree Wizard")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showCreateWizard = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Source & Path Configuration", systemImage: "slider.horizontal.3")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            Toggle("Create Brand New Branch instead of existing", isOn: $isCreatingNewBranch)

                            if isCreatingNewBranch {
                                TextField("Custom Brand New Branch Name", text: $customNewBranchName)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            } else {
                                TextField("Existing Branch Name (e.g. main, feature-x)", text: $newWorktreeBranch)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            TextField("Destination Folder Absolute Path", text: $newWorktreePath)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()

                            Button("Auto Suggest Destination Folder") {
                                if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                                    let suffix = isCreatingNewBranch ? customNewBranchName : newWorktreeBranch
                                    let sanitizedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
                                    newWorktreePath = docs.appendingPathComponent("Projects/Worktrees-\(sanitizedSuffix.isEmpty ? "new" : sanitizedSuffix)").path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    Button("Create Worktree") {
                        triggerCreateWorktree()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newWorktreePath.isEmpty || (isCreatingNewBranch ? customNewBranchName.isEmpty : newWorktreeBranch.isEmpty))
                }
                .padding()
            }
        }
        .frame(width: 580, height: 460)
    }

    // MARK: - Lock Reason Sheet

    private var lockReasonInputSheet: some View {
        VStack(spacing: 16) {
            Text("Lock Worktree")
                .font(.headline)
            Text("Provide a reason explaining why this worktree is locked. Locked worktrees cannot be accidentally removed or pruned.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Lock Reason Description", text: $lockReasonText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showLockReasonSheet = false
                    worktreeToLock = nil
                }
                .buttonStyle(.bordered)

                Button("Lock Worktree") {
                    if let wt = worktreeToLock {
                        Task {
                            do {
                                if let activeURL = sessionStore.activeProject?.directoryURL {
                                    try await manager.lockWorktree(worktreePath: wt.path, reason: lockReasonText, repositoryURL: activeURL)
                                }
                            } catch {
                                // Handled via log stream
                            }
                            showLockReasonSheet = false
                            worktreeToLock = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(lockReasonText.isEmpty)
            }
        }
        .padding()
        .frame(width: 380, height: 200)
    }

    // MARK: - Filtering & Sorting Logic

    private var filteredWorktrees: [GitWorktree] {
        var list = manager.worktrees

        // Search Filter
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter {
                $0.relativePath.lowercased().contains(q) ||
                $0.path.lowercased().contains(q) ||
                ($0.branch?.lowercased().contains(q) ?? false)
            }
        }

        // Category Filter
        switch filterCategory {
        case "Main Worktrees":
            list = list.filter { $0.isMain }
        case "Dirty":
            list = list.filter { $0.isDirty }
        case "Clean":
            list = list.filter { !$0.isDirty }
        case "Locked":
            list = list.filter { $0.isLocked }
        case "Favorites":
            list = list.filter { $0.isFavorite }
        default:
            break
        }

        // Sorting
        switch sortOption {
        case .branch:
            list.sort { ($0.branch ?? "") < ($1.branch ?? "") }
        case .repository:
            list.sort { $0.repositoryName < $1.repositoryName }
        case .name:
            list.sort { $0.relativePath < $1.relativePath }
        case .path:
            list.sort { $0.path < $1.path }
        case .lastCommit:
            list.sort { ($0.commitDate ?? Date.distantPast) > ($1.commitDate ?? Date.distantPast) }
        case .recentlyOpened:
            list.sort { ($0.lastOpenedDate ?? Date.distantPast) > ($1.lastOpenedDate ?? Date.distantPast) }
        case .favorites:
            list.sort { $0.isFavorite && !$1.isFavorite }
        }

        return list
    }

    // MARK: - Actions Operations

    private func refreshWorktrees() {
        if let activeURL = sessionStore.activeProject?.directoryURL {
            Task {
                await manager.refresh(repositoryURL: activeURL)
            }
        }
    }

    private func pruneStale() {
        if let activeURL = sessionStore.activeProject?.directoryURL {
            Task {
                try? await manager.pruneWorktrees(repositoryURL: activeURL)
            }
        }
    }

    private func repairWorktrees() {
        if let activeURL = sessionStore.activeProject?.directoryURL {
            Task {
                try? await manager.repairWorktree(repositoryURL: activeURL)
            }
        }
    }

    private func triggerCreateWorktree() {
        guard let activeURL = sessionStore.activeProject?.directoryURL else { return }
        showCreateWizard = false

        let path = newWorktreePath
        let branch = isCreatingNewBranch ? customNewBranchName : newWorktreeBranch

        Task {
            do {
                try await manager.createWorktree(
                    at: path,
                    branch: branch,
                    fromExisting: !isCreatingNewBranch,
                    isNewBranch: isCreatingNewBranch,
                    repositoryURL: activeURL
                )
            } catch {
                // Already reported to logs
            }
        }
    }

    private func unlockWorktree(_ wt: GitWorktree) {
        guard let activeURL = sessionStore.activeProject?.directoryURL else { return }
        Task {
            try? await manager.unlockWorktree(worktreePath: wt.path, repositoryURL: activeURL)
        }
    }

    private func removeWorktree(_ wt: GitWorktree) {
        guard let activeURL = sessionStore.activeProject?.directoryURL else { return }

        let alert = NSAlert()
        alert.messageText = "Remove Worktree"
        alert.informativeText = "Are you sure you want to completely remove this worktree from the repository disk footprint? This action is non-reversible."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                try? await manager.removeWorktree(worktreePath: wt.path, force: true, repositoryURL: activeURL)
                if selectedWorktree?.path == wt.path {
                    selectedWorktree = nil
                }
            }
        }
    }

    private func openWorktreeInSwiftCode(_ wt: GitWorktree) {
        let proj = Project(name: wt.path)
        Task {
            await sessionStore.openProject(proj)
        }
    }

    private func openInTerminal(_ path: String) {
        let script = "tell application \"Terminal\" to do script \"cd '\(path)'\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary? = nil
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Supporting FlowLayout for Buttons

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxRowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            currentX += size.width + spacing
            maxRowHeight = max(maxRowHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return CGSize(width: totalWidth, height: currentY + maxRowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var maxRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            maxRowHeight = max(maxRowHeight, size.height)
        }
    }
}
