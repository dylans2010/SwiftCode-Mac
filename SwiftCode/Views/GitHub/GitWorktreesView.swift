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
    @State private var isPerformingAction = false
    @State private var actionProgressTitle = ""

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
        case lastModified = "Last Modified"
        case favorites = "Favorites"
        case pinned = "Pinned"

        var id: String { rawValue }
    }

    // Filter categories mapping
    let filterCategories = [
        "All", "Main Worktrees", "Feature Branches", "Release Branches",
        "Hotfix Branches", "Dirty", "Clean", "Locked", "Detached HEAD",
        "Favorites", "Recently Opened", "Current Workspace"
    ]

    var body: some View {
        HSplitView {
            // Left Panel: Worktrees Directory & Filters
            VStack(spacing: 0) {
                // Toolbar & Search Area
                searchAndSortHeader

                Divider()

                // Worktrees Scrollable Grid/List
                if manager.isRefreshing && manager.worktrees.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Scanning repository worktrees...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredWorktrees.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Worktrees Found")
                            .font(.headline)
                        Text("Try clearing your search query or selecting another filter category.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)

                        Button {
                            showCreateWizard = true
                        } label: {
                            Label("Create Worktree", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredWorktrees) { wt in
                                worktreeCard(wt)
                            }
                        }
                        .padding(16)
                    }
                }

                Divider()

                // Live Log Stream & Actions Bar
                liveCommandLogConsole
            }
            .frame(minWidth: 400, idealWidth: 500)

            // Right Panel: Details View
            Group {
                if let wt = selectedWorktree {
                    worktreeDetailsPanel(wt)
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Select a worktree from the catalog to inspect detailed parameters, contributor timelines, ahead/behind counts, and local modifications.")
                    )
                }
            }
            .frame(minWidth: 420, idealWidth: 480)
        }
        .background(Color(NSColor.windowBackgroundColor))
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

    // MARK: - Core Components

    private var searchAndSortHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Search Input
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
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                // Sort Picker
                Picker("", selection: $sortOption) {
                    ForEach(SortOption.allCases) { opt in
                        Text("Sort by: \(opt.rawValue)").tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            // Category Filter Scrollbar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filterCategories, id: \.self) { cat in
                        Button {
                            withAnimation(.spring()) {
                                filterCategory = cat
                            }
                        } label: {
                            Text(cat)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(filterCategory == cat ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(filterCategory == cat ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Global Actions
            HStack(spacing: 8) {
                Button {
                    showCreateWizard = true
                } label: {
                    Label("Add Worktree", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    if let activeURL = sessionStore.activeProject?.directoryURL {
                        Task {
                            await manager.refresh(repositoryURL: activeURL)
                        }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    if let activeURL = sessionStore.activeProject?.directoryURL {
                        Task {
                            try? await manager.pruneWorktrees(repositoryURL: activeURL)
                        }
                    }
                } label: {
                    Label("Prune Stale", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button {
                    if let activeURL = sessionStore.activeProject?.directoryURL {
                        Task {
                            try? await manager.repairWorktree(repositoryURL: activeURL)
                        }
                    }
                } label: {
                    Label("Repair", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Worktree Card

    private func worktreeCard(_ wt: GitWorktree) -> some View {
        let isSelected = selectedWorktree?.path == wt.path
        let isActive = sessionStore.activeProject?.directoryURL.path == wt.path

        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title3)
                        .foregroundStyle(wt.isMain ? Color.orange : Color.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(wt.relativePath)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)

                            if wt.isMain {
                                Text("MAIN")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .cornerRadius(4)
                            }

                            if wt.isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .help(wt.lockReason ?? "Locked")
                            }

                            if isActive {
                                Text("ACTIVE WORKSPACE")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }

                        Text(wt.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Favorite & Pin indicators
                    HStack(spacing: 8) {
                        Button {
                            manager.toggleFavorite(for: wt)
                        } label: {
                            Image(systemName: wt.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(wt.isFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            manager.togglePinned(for: wt)
                        } label: {
                            Image(systemName: wt.isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(wt.isPinned ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                HStack {
                    // Branch & Status
                    Label(wt.branch ?? "Detached HEAD", systemImage: wt.isDetached ? "personalhotspot" : "arrow.triangle.branch")
                        .font(.caption.bold())
                        .foregroundStyle(wt.isDetached ? .red : .primary)

                    Spacer()

                    // Ahead/Behind counts
                    if wt.aheadCount > 0 || wt.behindCount > 0 {
                        Text("↑ \(wt.aheadCount) ↓ \(wt.behindCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Modification badges
                    if wt.isDirty {
                        HStack(spacing: 6) {
                            if wt.modifiedCount > 0 {
                                Badge(count: wt.modifiedCount, color: .orange, icon: "pencil")
                            }
                            if wt.stagedCount > 0 {
                                Badge(count: wt.stagedCount, color: .green, icon: "checkmark.circle")
                            }
                            if wt.untrackedCount > 0 {
                                Badge(count: wt.untrackedCount, color: .blue, icon: "questionmark.circle")
                            }
                        }
                    } else {
                        Text("Clean")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedWorktree = wt
                manager.updateLastOpened(for: wt)
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(8)
        .contextMenu {
            contextMenuOptions(wt)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuOptions(_ wt: GitWorktree) -> some View {
        Button {
            openWorktreeInSwiftCode(wt)
        } label: {
            Label("Open in SwiftCode", systemImage: "laptopcomputer")
        }

        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: wt.path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            openInTerminal(wt.path)
        } label: {
            Label("Open in Terminal", systemImage: "terminal")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(wt.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        if let br = wt.branch {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(br, forType: .string)
            } label: {
                Label("Copy Branch", systemImage: "arrow.triangle.branch")
            }
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(wt.headSHA, forType: .string)
        } label: {
            Label("Copy Commit SHA", systemImage: "square.dashed")
        }

        Divider()

        if wt.isLocked {
            Button {
                unlockWorktree(wt)
            } label: {
                Label("Unlock Worktree", systemImage: "lock.open")
            }
        } else {
            Button {
                worktreeToLock = wt
                lockReasonText = ""
                showLockReasonSheet = true
            } label: {
                Label("Lock Worktree...", systemImage: "lock")
            }
        }

        Button(role: .destructive) {
            removeWorktree(wt)
        } label: {
            Label("Remove Worktree...", systemImage: "trash")
        }
    }

    // MARK: - Worktree Details Panel

    private func worktreeDetailsPanel(_ wt: GitWorktree) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title Area
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(wt.relativePath)
                            .font(.title2.bold())
                        Text(wt.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }

                Divider()

                // Specifications Grid
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Worktree Parameters", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Branch:")
                                    .foregroundStyle(.secondary)
                                Text(wt.branch ?? "Detached HEAD")
                                    .fontWeight(.semibold)
                            }
                            if let remote = wt.remoteBranch {
                                GridRow {
                                    Text("Remote upstream:")
                                        .foregroundStyle(.secondary)
                                    Text(remote)
                                        .font(.caption.monospaced())
                                }
                            }
                            GridRow {
                                Text("HEAD Commit:")
                                    .foregroundStyle(.secondary)
                                Text(wt.headSHA)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            if !wt.commitMessage.isEmpty {
                                GridRow {
                                    Text("Commit Message:")
                                        .foregroundStyle(.secondary)
                                    Text(wt.commitMessage)
                                        .italic()
                                }
                            }
                            if !wt.commitAuthor.isEmpty {
                                GridRow {
                                    Text("Author:")
                                        .foregroundStyle(.secondary)
                                    Text(wt.commitAuthor)
                                }
                            }
                            if let date = wt.commitDate {
                                GridRow {
                                    Text("Commit Date:")
                                        .foregroundStyle(.secondary)
                                    Text(date.formatted())
                                }
                            }
                            GridRow {
                                Text("Lock Status:")
                                    .foregroundStyle(.secondary)
                                Text(wt.isLocked ? "Locked (\(wt.lockReason ?? ""))" : "Unlocked")
                                    .foregroundStyle(wt.isLocked ? .red : .green)
                            }
                            if let opened = wt.lastOpenedDate {
                                GridRow {
                                    Text("Last Opened:")
                                        .foregroundStyle(.secondary)
                                    Text(opened.formatted())
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Health & Diagnostics
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Repository Health Check", systemImage: "shield.checkered")
                            .font(.headline)
                            .foregroundStyle(.green)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Worktree Integrity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(wt.isLocked ? "Suspended (Locked)" : "Healthy")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(wt.isLocked ? .red : .green)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Files count")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Local changes: \(wt.modifiedCount) files")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(wt.isDirty ? .orange : .secondary)
                            }
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Command Quick Launch
                VStack(alignment: .leading, spacing: 10) {
                    Text("Operations Quick Actions")
                        .font(.headline)

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

                        Button {
                            duplicateWorktree(wt)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
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
                                Label("Lock...", systemImage: "lock")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            removeWorktree(wt)
                        } label: {
                            Label("Remove Worktree...", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Live Output Console

    private var liveCommandLogConsole: some View {
        VStack(spacing: 0) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(manager.liveCommandLogs)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.12))
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                        .frame(height: 120)
                        .onChange(of: manager.liveCommandLogs.count) {
                            proxy.scrollTo("bottom")
                        }
                    }

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
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.secondary)
                    Text("Live Execution Log Stream")
                        .font(.headline)
                    Spacer()
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Creation Wizard Sheet

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
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Path conflict Diagnostics", systemImage: "shield.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Text("Preview Location: \(newWorktreePath)")
                                .font(.caption.monospaced())

                            if FileManager.default.fileExists(atPath: newWorktreePath) {
                                Text("⚠ Destination folder already exists! Merge conflict or permission failures are likely.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("✓ Path is clear and empty. Fully safe to proceed.")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(8)
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
        .frame(width: 580, height: 500)
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
        case "Feature Branches":
            list = list.filter { $0.branch?.hasPrefix("feature/") ?? false }
        case "Release Branches":
            list = list.filter { $0.branch?.hasPrefix("release/") ?? false }
        case "Hotfix Branches":
            list = list.filter { $0.branch?.hasPrefix("hotfix/") ?? false }
        case "Dirty":
            list = list.filter { $0.isDirty }
        case "Clean":
            list = list.filter { !$0.isDirty }
        case "Locked":
            list = list.filter { $0.isLocked }
        case "Detached HEAD":
            list = list.filter { $0.isDetached }
        case "Favorites":
            list = list.filter { $0.isFavorite }
        case "Recently Opened":
            list = list.filter { $0.lastOpenedDate != nil }
        case "Current Workspace":
            list = list.filter { sessionStore.activeProject?.directoryURL.path == $0.path }
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
        case .lastModified:
            list.sort { $0.isDirty && !$1.isDirty }
        case .favorites:
            list.sort { $0.isFavorite && !$1.isFavorite }
        case .pinned:
            list.sort { $0.isPinned && !$1.isPinned }
        }

        return list
    }

    // MARK: - Actions Operations

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

    private func duplicateWorktree(_ wt: GitWorktree) {
        guard let activeURL = sessionStore.activeProject?.directoryURL else { return }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dupPath = docs.appendingPathComponent("Projects/Worktrees-\(wt.relativePath)-dup-\(Int(Date().timeIntervalSince1970) % 1000)").path
            Task {
                do {
                    try await manager.duplicateWorktree(sourcePath: wt.path, destinationPath: dupPath, repositoryURL: activeURL)
                } catch {
                    // Reported to logs
                }
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
        // Switching workspace natively
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

// MARK: - Badge View

struct Badge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text("\(count)")
                .font(.system(size: 8, weight: .bold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .cornerRadius(4)
    }
}
