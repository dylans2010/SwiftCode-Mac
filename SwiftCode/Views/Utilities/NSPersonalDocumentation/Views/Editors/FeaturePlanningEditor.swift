import SwiftUI

public struct FeaturePlanningEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var targetQuarter = "Q3 2026"
    @State private var leadDeveloper = ""
    @State private var estimatedStoryPoints = "5"
    @State private var teamAlignment = "Core Platform"
    @State private var riskLevel = "Medium"
    @State private var customerImpact = "All Public Users"

    // Interactive Scope Guard Checklist
    @State private var inScopeItem = ""
    @State private var outOfScopeItem = ""
    @State private var inScopeList: [String] = []
    @State private var outOfScopeList: [String] = []

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
                HStack(spacing: 6) {
                    Button {
                        insertStories()
                    } label: {
                        Label("Stories List", systemImage: "person.2.fill")
                    }
                    .help("Insert standard User Stories specification")

                    Button {
                        insertMilestones()
                    } label: {
                        Label("Milestones", systemImage: "flag.fill")
                    }
                    .help("Insert key product milestones timeline")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Quarter:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $targetQuarter) {
                                Text("Q1 2026").tag("Q1 2026")
                                Text("Q2 2026").tag("Q2 2026")
                                Text("Q3 2026").tag("Q3 2026")
                                Text("Q4 2026").tag("Q4 2026")
                            }
                            .controlSize(.small)

                            Text("Lead Dev:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Developer", text: $leadDeveloper)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Points:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $estimatedStoryPoints) {
                                Text("1").tag("1")
                                Text("3").tag("3")
                                Text("5").tag("5")
                                Text("8").tag("8")
                                Text("13").tag("13")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Team:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $teamAlignment) {
                                Text("Platform").tag("Core Platform")
                                Text("UI Flow").tag("UI/UX Flow")
                                Text("Data Sync").tag("Data Sync")
                            }
                            .controlSize(.small)

                            Text("Risk:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $riskLevel) {
                                Text("High").tag("High")
                                Text("Med").tag("Medium")
                                Text("Low").tag("Low")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Impact:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $customerImpact) {
                                Text("Internal").tag("Internal Tooling")
                                Text("Enterprise").tag("Enterprise Customers")
                                Text("Public").tag("All Public Users")
                            }
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // SCOPE GUARD BUILDER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCOPE GUARD CONTROLS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        // In scope
                        HStack {
                            TextField("Add In-Scope...", text: $inScopeItem, onCommit: addInScope)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            Button { addInScope() } label: { Image(systemName: "plus") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }

                        // Out of scope
                        HStack {
                            TextField("Add Out-of-Scope...", text: $outOfScopeItem, onCommit: addOutOfScope)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            Button { addOutOfScope() } label: { Image(systemName: "plus") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }

                        // Added visual items count indicator
                        if !inScopeList.isEmpty || !outOfScopeList.isEmpty {
                            HStack {
                                Text("In-Scope: \(inScopeList.count)")
                                    .foregroundStyle(.green)
                                Text("•")
                                Text("Out-of-Scope: \(outOfScopeList.count)")
                                    .foregroundStyle(.red)
                            }
                            .font(.system(size: 10, weight: .bold))
                        }
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func addInScope() {
        let trimmed = inScopeItem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            inScopeList.append(trimmed)
            inScopeItem = ""
        }
    }

    private func addOutOfScope() {
        let trimmed = outOfScopeItem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            outOfScopeList.append(trimmed)
            outOfScopeItem = ""
        }
    }

    private func insertStories() {
        var scopeMarkdown = ""
        if !inScopeList.isEmpty {
            scopeMarkdown += "\n#### In-Scope Items:\n"
            for item in inScopeList { scopeMarkdown += "- [x] \(item)\n" }
        }
        if !outOfScopeList.isEmpty {
            scopeMarkdown += "\n#### Out-of-Scope Boundaries:\n"
            for item in outOfScopeList { scopeMarkdown += "- [ ] *Excluding*: \(item)\n" }
        }

        let template = """

        ### Feature Requirements & User Stories

        **Target Timeline:** `\(targetQuarter)`
        **Story Points Budget:** `\(estimatedStoryPoints)` SP
        **Team Alignment:** `\(teamAlignment)`
        **Oversight Lead:** \(leadDeveloper.isEmpty ? "N/A" : leadDeveloper)

        #### Proposed User Stories
        - [ ] **Story 1:** As a \(customerImpact) role, I want [action] so that [benefit].
        - [ ] **Story 2:** As a developer in \(teamAlignment), I want [technical action] so that [engineering benefit].

        \(scopeMarkdown)

        **Risk Mitigation Plan:**
        - Risk Level: `\(riskLevel)`
        - Mitigation: Regular testing sync and agile scope adjustments.
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
