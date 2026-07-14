import SwiftUI

public struct UserStoryEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var acceptanceCriteriaCount = 3
    @State private var priority = "High"
    @State private var personaTarget = "Standard User"
    @State private var storyPoints = "3"
    @State private var epic = "Authentication"
    @State private var statusState = "Backlog"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .userStory,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertGherkin()
                } label: {
                    Label("Gherkin Scenario", systemImage: "doc.text.image")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Story Priority:")
                            .font(.caption.bold())
                        Picker("", selection: $priority) {
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Text("Story Points:")
                            .font(.caption.bold())
                        Picker("", selection: $storyPoints) {
                            Text("1").tag("1")
                            Text("2").tag("2")
                            Text("3").tag("3")
                            Text("5").tag("5")
                            Text("8").tag("8")
                            Text("13").tag("13")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    GridRow {
                        Text("Persona Target:")
                            .font(.caption.bold())
                        Picker("", selection: $personaTarget) {
                            Text("Standard User").tag("Standard User")
                            Text("Administrator").tag("Administrator")
                            Text("Developer API Client").tag("Developer API Client")
                        }
                        .frame(width: 180)

                        Text("Criteria Count:")
                            .font(.caption.bold())
                        Stepper("\(acceptanceCriteriaCount)", value: $acceptanceCriteriaCount, in: 1...10)
                    }

                    GridRow {
                        Text("Epic Link:")
                            .font(.caption.bold())
                        TextField("e.g. Authentication", text: $epic)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Text("Status State:")
                            .font(.caption.bold())
                        Picker("", selection: $statusState) {
                            Text("Backlog").tag("Backlog")
                            Text("In Dev").tag("In Dev")
                            Text("In Review").tag("In Review")
                            Text("Done").tag("Done")
                        }
                        .frame(width: 150)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertGherkin() {
        var criteria = ""
        for i in 1...acceptanceCriteriaCount {
            criteria += "- [ ] **AC \(i):** Given [Context], When [Action], Then [Expected Outcome].\n"
        }
        let template = """

        ### User Story Specifications

        **Priority:** `\(priority)`
        **Story Points:** `\(storyPoints)` SP
        **Epic:** `\(epic)`
        **Status:** `\(statusState)`
        **Persona:** `\(personaTarget)`

        **As a** \(personaTarget),
        **I want** [some behavior/feature],
        **So that** [the business benefit/value is realized].

        #### Acceptance Criteria (\(acceptanceCriteriaCount) Items)
        \(criteria)

        #### Gherkin Scenario Definition
        ```gherkin
        Scenario: Success Flow for \(personaTarget)
          Given a registered \(personaTarget) is on the dashboard
          When they tap "Create New Entry"
          Then they are presented with a type-selection popover
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
