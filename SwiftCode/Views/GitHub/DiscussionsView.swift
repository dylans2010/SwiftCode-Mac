import SwiftUI

@MainActor
struct DiscussionsView: View {
    let project: Project?

    var body: some View {
        GitHubEmptyStateView(
            title: "Discussions Not Activated",
            description: "Activate and setup GitHub Discussions on your repository to share ideas, ask questions, and chat with community members.",
            systemImage: "bubble.left.and.bubble.right.fill",
            accentColor: .purple,
            actionTitle: "Configure Discussions"
        ) {
            if let repo = project?.githubRepo {
                if let url = URL(string: "https://github.com/\(repo)/discussions") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
