// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/GitHub/Menu Bar/MenuBarManager.swift
//
// Adapted for SwiftCode: `GitMenuBarCommandExecutor.runGitCommand`
// ran through Legacy's `ProcessRunnerTool` (missing here; audit-A
// records it COVERED-BY-REDESIGN by `SwiftCodeSubprocess.Subprocess.run`),
// so it now runs the synchronous `Subprocess.run` on a detached task
// (same helper shape as `WorkflowManager.runShell`). Everything else
// is verbatim. DANGLING DEPS, all pre-existing tree gaps, not new:
//   - RESOLVED (Q-GH2): the 17 `NS*View` cases in `MenuBarRootView`
//     are now ported verbatim-then-adapted into
//     `SwiftCodeUI/SourceControl/`; the three A4-redesigned views
//     (`NSPushOptionsView`, `NSForcePushView`, `NSCherryPickView`)
//     resolve through `MenuBarRootView.activeRepository`.
//   - `GitHubSettingsView` (in `NoLinkedRepositoryCard`) does not exist.
//     (P-GH's slice: Legacy `Views/GitHub/GitHubSettingsView.swift`.)
//   - `PreferencesStore` (git executable override) is staged in
//     staging-wire/unowned/ (F2's slice); `GitService` and
//     `SettingsViewModel` already wait on it too.
// `ProjectSessionStore` / `Project` are in `SwiftCodeIDECore`;
// `GitService` is in `SwiftCodeSDK`.

import SwiftCodeIDECore
import SwiftCodeSDK
import SwiftCodeSubprocess
import SwiftUI
import AppKit

@MainActor
public func openWorkspaceView() {
    NSApp.activate(ignoringOtherApps: true)
    for window in NSApplication.shared.windows {
        if window.className != "NSPopoverWindow" && !window.className.contains("NSStatusBarWindow") {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
public class MenuBarManager: NSObject, NSMenuDelegate {
    public static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    let options = [
        "Commit", "Push", "Push Options", "Choose Branch", "Include Tags", "Force Push",
        "Fetch", "Pull", "Cherry Pick", "Clone", "Create Repository", "Create Branch",
        "Switch Branch", "Delete Branch", "Stash", "Apply Stash", "Rebase", "Merge",
        "Discard Changes", "Create PR"
    ]

    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git Controls")
        }

        // Create native menu
        let menu = NSMenu()
        menu.delegate = self
        for opt in options {
            let item = NSMenuItem(title: opt, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        statusItem?.menu = menu

        let contentView = MenuBarRootView()

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 420)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: contentView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectMenuBarTab(_:)),
            name: NSNotification.Name("SelectMenuBarTab"),
            object: nil
        )
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        let isLinked = ProjectSessionStore.shared.activeProject?.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        for item in menu.items {
            item.isEnabled = isLinked || item.title == "Create Repository"
        }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        let title = sender.title
        NotificationCenter.default.post(
            name: NSNotification.Name("SelectMenuBarTab"),
            object: nil,
            userInfo: ["tab": title]
        )
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func handleSelectMenuBarTab(_ notification: Notification) {
        if let button = statusItem?.button {
            if popover?.isShown != true {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

struct NoLinkedRepositoryCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("No Linked Repository")
                .font(.headline)

            Text("You must link a GitHub repository to use Git operations for this project.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            NavigationLink {
                GitHubSettingsView(project: ProjectSessionStore.shared.activeProject)
            } label: {
                Label("Configure Repo", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MenuBarRootView: View {
    @State private var selectedTab = "Commit"

    /// The active project's repository for the three A4-redesigned views
    /// (`NSPushOptionsView`, `NSForcePushView`, `NSCherryPickView`), which
    /// take `init(repository:)` instead of Legacy's parameterless init.
    /// Resolved on demand (one `git rev-parse`); nil with no active
    /// project or no git checkout — those tabs then show an empty pane.
    private var activeRepository: GitRepository? {
        ProjectSessionStore.shared.activeProject.flatMap { GitRepository(containing: $0.directoryURL) }
    }

    let options = [
        "Commit", "Push", "Push Options", "Choose Branch", "Include Tags", "Force Push",
        "Fetch", "Pull", "Cherry Pick", "Clone", "Create Repository", "Create Branch",
        "Switch Branch", "Delete Branch", "Stash", "Apply Stash", "Rebase", "Merge",
        "Discard Changes", "Create PR"
    ]

    private var isRepositoryLinked: Bool {
        ProjectSessionStore.shared.activeProject?.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isRepositoryLinked {
                    NoLinkedRepositoryCard()
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Git: \(selectedTab)")
                                .font(.headline.bold())
                            Spacer()
                        }
                        .padding()
                        .liquidGlass(style: .subtle, cornerRadius: 10)

                        Divider()

                        VStack(spacing: 0) {
                            Group {
                                switch selectedTab {
                                case "Commit": NSCommitView()
                                case "Push": NSPushView()
                                case "Push Options": if let repository = activeRepository { NSPushOptionsView(repository: repository) } else { EmptyView() }
                                case "Choose Branch": NSChooseBranchView()
                                case "Include Tags": NSIncludeTagsView()
                                case "Force Push": if let repository = activeRepository { NSForcePushView(repository: repository) } else { EmptyView() }
                                case "Fetch": NSFetchView()
                                case "Pull": NSPullView()
                                case "Cherry Pick": if let repository = activeRepository { NSCherryPickView(repository: repository) } else { EmptyView() }
                                case "Clone": NSCloneView()
                                case "Create Repository": NSCreateRepositoryView()
                                case "Create Branch": NSCreateBranchView()
                                case "Switch Branch": NSSwitchBranchView()
                                case "Delete Branch": NSDeleteBranchView()
                                case "Stash": NSStashView()
                                case "Apply Stash": NSApplyStashView()
                                case "Rebase": NSRebaseView()
                                case "Merge": NSMergeView()
                                case "Discard Changes": NSDiscardAllChangesView()
                                case "Create PR": NSCreatePRView()
                                default: EmptyView()
                                }
                            }
                            .transition(.opacity)
                            .id(selectedTab)
                        }
                    }
                }
            }
            .frame(width: 320, height: 420)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectMenuBarTab"))) { notification in
                if let tab = notification.userInfo?["tab"] as? String {
                    selectedTab = tab
                }
            }
        }
    }
}

// MARK: - No Active Project Fallback View
public struct NoActiveProjectView: View {
    public var title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: "folder.badge.questionmark")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("No active project is open in SwiftCode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Please open or import a project in the workspace to perform Git actions.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(width: 280, height: 200)
    }
}

// MARK: - Git Menu Bar Command Executor
public enum GitMenuBarError: LocalizedError {
    case noActiveProject
    case gitError(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveProject:
            return "No active project is currently open."
        case .gitError(let message):
            return message
        }
    }
}

public struct GitMenuBarCommandExecutor {
    public static func gitURL() async -> URL {
        if let customPath = await PreferencesStore.shared.get(forKey: "git_executable_path") as? String {
            return URL(fileURLWithPath: customPath)
        }
        let commonPaths = [
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/usr/bin/git"
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    /// Run a git command to completion via `SwiftCodeSubprocess`
    /// (the production successor of Legacy's `ProcessRunnerTool`):
    /// `Subprocess.run` is synchronous, so it runs on a detached task
    /// to stay off the main thread.
    private static func runProcess(executableURL: URL, arguments: [String], workingDirectory: URL?) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let output = try await Task.detached {
            try Subprocess.run(executableURL.path, arguments, currentDirectory: workingDirectory)
        }.value
        return (output.stdoutText, output.stderrText, output.status)
    }

    @discardableResult
    public static func runGitCommand(arguments: [String], workingDirectory: URL? = nil) async throws -> String {
        let exe = await gitURL()
        let result = try await runProcess(
            executableURL: exe,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        guard result.exitCode == 0 else {
            let errMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalMsg = errMsg.isEmpty ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : errMsg
            throw GitMenuBarError.gitError(finalMsg.isEmpty ? "Git exit code \(result.exitCode)" : finalMsg)
        }
        return result.stdout
    }

    @discardableResult
    public static func runGit(args: [String]) async throws -> String {
        guard let project = await MainActor.run(body: { ProjectSessionStore.shared.activeProject }) else {
            throw GitMenuBarError.noActiveProject
        }
        return try await runGitCommand(arguments: args, workingDirectory: project.directoryURL)
    }

    public static func getBranchesList() async -> [String] {
        guard let project = await MainActor.run(body: { ProjectSessionStore.shared.activeProject }) else {
            return ["main"]
        }
        do {
            let branches = try await GitService.shared.getBranches(repositoryURL: project.directoryURL)
            let list = branches.map { $0.name }
            return list.isEmpty ? ["main"] : list
        } catch {
            return ["main"]
        }
    }

    public static func getCurrentBranchName() async throws -> String {
        guard let project = await MainActor.run(body: { ProjectSessionStore.shared.activeProject }) else {
            throw GitMenuBarError.noActiveProject
        }
        let branch = try await runGitCommand(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], workingDirectory: project.directoryURL)
        return branch.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
