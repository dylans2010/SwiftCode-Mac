import SwiftUI

struct GitStrategy: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let commandSequence: String
    let useCase: String
}

public struct GitBranchingStrategiesView: View {
    private let strategies = [
        GitStrategy(
            name: "GitHub Flow",
            description: "A lightweight, branch-based workflow supporting regular, rapid production deployments.",
            commandSequence: "git checkout -b feature/auth\n# ... make and commit changes ...\ngit push origin feature/auth\n# ... open PR, merge, and deploy 'main' ...",
            useCase: "Ideal for continuous integration and web-apps where main is always in a deployable status."
        ),
        GitStrategy(
            name: "GitFlow",
            description: "A strict branching model designed around project releases with permanent main and develop branches.",
            commandSequence: "git checkout -b feature/billing develop\ngit checkout develop\ngit merge feature/billing\ngit checkout -b release/1.4.0 develop\ngit checkout main\ngit merge release/1.4.0\ngit tag -a v1.4.0",
            useCase: "Best for boxed software, mobile apps, or teams needing structured, versioned releases."
        ),
        GitStrategy(
            name: "Trunk-Based Development",
            description: "Developers merge small, frequent updates into a single core 'trunk' branch, bypassing long-lived feature branches.",
            commandSequence: "git checkout main\ngit pull origin main\ngit checkout -b quick-fix-auth\n# ... 1-2 small commits ...\ngit checkout main\ngit merge quick-fix-auth\ngit push origin main",
            useCase: "Best for highly collaborative, mature engineering teams with strong unit tests and CI integration."
        )
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Git Branching Strategy Playbook")
                        .font(.title.bold())
                    Text("A reference guide for choosing the ideal branch model for collaborative software development cycles.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(strategies) { strat in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(strat.name)
                                .font(.headline)
                                .foregroundColor(.blue)

                            Text(strat.description)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("SAMPLE COMMAND FLOW")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                Text(strat.commandSequence)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.25))
                                    .cornerRadius(6)
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text(strat.useCase)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
