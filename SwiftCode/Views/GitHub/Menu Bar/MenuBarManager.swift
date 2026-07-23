import SwiftUI
import AppKit

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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Git Menu Bar Controls")
                    .font(.headline.bold())
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Selector dropdown
            Picker("Operation", selection: $selectedTab) {
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
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
    }
}
