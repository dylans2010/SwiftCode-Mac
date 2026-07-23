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
public class MenuBarManager: NSObject {
    public static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git Controls")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

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

    @objc private func handleSelectMenuBarTab(_ notification: Notification) {
        if let button = statusItem?.button {
            if popover?.isShown != true {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(sender)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

struct MenuBarRootView: View {
    @State private var selectedTab = "Commit"

    let options = [
        "Commit", "Push", "Push Options", "Choose Branch", "Include Tags", "Force Push",
        "Fetch", "Pull", "Cherry Pick", "Clone", "Create Repository", "Create Branch",
        "Switch Branch", "Delete Branch", "Stash", "Apply Stash", "Rebase", "Merge",
        "Discard Changes", "Create PR"
    ]

    let optionsWithShortcuts: [String: String] = [
        "Commit": "C",
        "Push": "H",
        "Push Options": "O",
        "Choose Branch": "B",
        "Include Tags": "G",
        "Force Push": "Y",
        "Fetch": "E",
        "Pull": "L",
        "Cherry Pick": "K",
        "Clone": "I",
        "Create Repository": "R",
        "Create Branch": "J",
        "Switch Branch": "S",
        "Delete Branch": "D",
        "Stash": "Z",
        "Apply Stash": "V",
        "Rebase": "X",
        "Merge": "M",
        "Discard Changes": "U",
        "Create PR": "Q"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Git Menu Bar Controls")
                    .font(.headline.bold())
                Spacer()
                Button(action: {
                    openWorkspaceView()
                }) {
                    Label("Workspace", systemImage: "macwindow")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open WorkspaceView (⇧⌘0)")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Selector dropdown
            Picker("Operation", selection: $selectedTab) {
                ForEach(options, id: \.self) { opt in
                    if let key = optionsWithShortcuts[opt] {
                        Text("\(opt) (⇧⌘\(key))").tag(opt)
                    } else {
                        Text(opt).tag(opt)
                    }
                }
            }
            .pickerStyle(.menu)
            .padding()

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case "Commit": NSCommitView()
                    case "Push": NSPushView()
                    case "Push Options": NSPushOptionsView()
                    case "Choose Branch": NSChooseBranchView()
                    case "Include Tags": NSIncludeTagsView()
                    case "Force Push": NSForcePushView()
                    case "Fetch": NSFetchView()
                    case "Pull": NSPullView()
                    case "Cherry Pick": NSCherryPickView()
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
        .frame(width: 320, height: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectMenuBarTab"))) { notification in
            if let tab = notification.userInfo?["tab"] as? String {
                selectedTab = tab
            }
        }
        .background(
            ZStack {
                Button(action: {
                    openWorkspaceView()
                }) {
                    EmptyView()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)

                ForEach(options, id: \.self) { opt in
                    if let key = optionsWithShortcuts[opt] {
                        Button(action: {
                            selectedTab = opt
                        }) {
                            EmptyView()
                        }
                        .keyboardShortcut(KeyEquivalent(Character(key.lowercased())), modifiers: [.command, .shift])
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                    }
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
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

    @discardableResult
    public static func runGitCommand(arguments: [String], workingDirectory: URL? = nil) async throws -> String {
        let exe = await gitURL()
        let result = try await ProcessRunnerTool.shared.run(
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
