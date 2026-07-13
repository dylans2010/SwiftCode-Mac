import SwiftUI

@MainActor
struct DiscussionsView: View {
    let project: Project?

    private var context: RepositoryContext {
        RepositoryContext.shared
    }

    var body: some View {
        VStack(spacing: 0) {
            if context.displayMode == .connectedRepository && context.connectedRepository == nil {
                disconnectedPlaceholder
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        GitHubEmptyStateView(
            title: "Discussions Not Activated",
            description: "Activate and setup GitHub Discussions on your repository to share ideas, ask questions, and chat with community members.",
            systemImage: "bubble.left.and.bubble.right.fill",
            accentColor: .purple,
            actionTitle: "Configure Discussions"
        ) {
            if let repo = context.connectedRepository {
                if let url = URL(string: "https://github.com/\(repo)/discussions") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var disconnectedPlaceholder: some View {
        GitHubEmptyStateView(
            title: "No Repository Connected",
            description: "Connect a remote GitHub repository to this project to view and manage Discussions.",
            systemImage: "bubble.left.and.bubble.right.fill",
            accentColor: .orange
        )
    }
}
