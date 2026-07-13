import SwiftUI

@MainActor
struct GitHubToolbar: View {
    let currentSelection: GitHubSidebarItem
    let isProjectConnected: Bool
    let isPerformingAction: Bool

    // Callbacks
    var onRefresh: () -> Void
    var onClone: () -> Void
    var onPull: (() -> Void)? = nil
    var onPush: (() -> Void)? = nil
    var onFetch: (() -> Void)? = nil
    var onSync: (() -> Void)? = nil
    var onNewBranch: (() -> Void)? = nil
    var onNewPullRequest: (() -> Void)? = nil
    var onNewIssue: (() -> Void)? = nil

    @State private var searchQuery = ""

    var body: some View {
        HStack(spacing: 12) {
            // Contextual Actions
            Group {
                Button {
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh Current View")
                .disabled(isPerformingAction)

                Button {
                    onClone()
                } label: {
                    Label("Clone", systemImage: "arrow.down.doc.fill")
                }
                .help("Clone Repository")

                if isProjectConnected {
                    Divider()
                        .frame(height: 16)

                    Button {
                        onPull?()
                    } label: {
                        Label("Pull", systemImage: "arrow.down.circle")
                    }
                    .help("Git Pull")
                    .disabled(isPerformingAction)

                    Button {
                        onPush?()
                    } label: {
                        Label("Push", systemImage: "arrow.up.circle")
                    }
                    .help("Git Push")
                    .disabled(isPerformingAction)

                    Button {
                        onFetch?()
                    } label: {
                        Label("Fetch", systemImage: "arrow.down.and.line.horizontal")
                    }
                    .help("Git Fetch")
                    .disabled(isPerformingAction)

                    Button {
                        onSync?()
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Sync Branches and Commits")
                    .disabled(isPerformingAction)
                }
            }

            Spacer()

            // Selection-specific contextual creation buttons
            Group {
                if currentSelection == .branches {
                    Button {
                        onNewBranch?()
                    } label: {
                        Label("New Branch", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                } else if currentSelection == .pullRequests {
                    Button {
                        onNewPullRequest?()
                    } label: {
                        Label("New PR", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else if currentSelection == .issues {
                    Button {
                        onNewIssue?()
                    } label: {
                        Label("New Issue", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
