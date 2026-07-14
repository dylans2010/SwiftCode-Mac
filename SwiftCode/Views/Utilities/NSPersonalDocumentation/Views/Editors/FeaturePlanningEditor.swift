import SwiftUI

public struct FeaturePlanningEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var targetQuarter = "Q3 2026"
    @State private var leadDeveloper = ""
    @State private var estimatedStoryPoints = "5"
    @State private var teamAlignment = "Core Platform"
    @State private var riskLevel = "Medium"
    @State private var customerImpact = "All Public Users"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .featurePlanning,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 8) {
                    Button {
                        insertStories()
                    } label: {
                        Label("Stories List", systemImage: "person.2.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        insertMilestones()
                    } label: {
                        Label("Milestones", systemImage: "flag.fill")
                    }
                    .buttonStyle(.bordered)
                }
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Target Quarter:")
                            .font(.caption.bold())
                        Picker("", selection: $targetQuarter) {
                            Text("Q1 2026").tag("Q1 2026")
                            Text("Q2 2026").tag("Q2 2026")
                            Text("Q3 2026").tag("Q3 2026")
                            Text("Q4 2026").tag("Q4 2026")
                        }
                        .frame(width: 180)

                        Text("Lead Dev:")
                            .font(.caption.bold())
                        TextField("Name", text: $leadDeveloper)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    GridRow {
                        Text("Story Points:")
                            .font(.caption.bold())
                        Picker("", selection: $estimatedStoryPoints) {
                            Text("1").tag("1")
                            Text("2").tag("2")
                            Text("3").tag("3")
                            Text("5").tag("5")
                            Text("8").tag("8")
                            Text("13").tag("13")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)

                        Text("Team Alignment:")
                            .font(.caption.bold())
                        Picker("", selection: $teamAlignment) {
                            Text("Core Platform").tag("Core Platform")
                            Text("UI/UX Flow").tag("UI/UX Flow")
                            Text("Data Sync").tag("Data Sync")
                            Text("DevOps").tag("DevOps")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("Risk Level:")
                            .font(.caption.bold())
                        Picker("", selection: $riskLevel) {
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Text("Customer Impact:")
                            .font(.caption.bold())
                        Picker("", selection: $customerImpact) {
                            Text("Internal Tooling").tag("Internal Tooling")
                            Text("Enterprise Customers").tag("Enterprise Customers")
                            Text("All Public Users").tag("All Public Users")
                        }
                        .frame(width: 180)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertStories() {
        let template = """

        ### Proposed User Stories
        - [ ] **Story 1:** As a \(customerImpact) role, I want [action] so that [benefit].
        - [ ] **Story 2:** As a developer in \(teamAlignment), I want [technical action] so that [engineering benefit].

        **Feature Constraints:**
        * Story points budget: `\(estimatedStoryPoints)` SP
        * Risk Level: `\(riskLevel)`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertMilestones() {
        let template = """

        ### Major Milestones & Timelines (\(targetQuarter))
        | Milestone Description | Target Date | Team Responsible | Status |
        | :--- | :--- | :--- | :--- |
        | Core Architecture Complete | Mid-Quarter | \(teamAlignment) | Pending |
        | Public Beta Testing | End of Month 2 | \(teamAlignment) | Pending |
        | Production Release | End of Quarter | \(teamAlignment) | Pending |

        **Milestone Oversight:** Lead Dev: \(leadDeveloper)
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
