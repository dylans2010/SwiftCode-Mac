import SwiftUI

public struct UserStoryEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var acceptanceCriteriaCount = 3
    @State private var priority = "High"

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
                HStack(spacing: 20) {
                    Picker("Story Priority:", selection: $priority) {
                        Text("High").tag("High")
                        Text("Medium").tag("Medium")
                        Text("Low").tag("Low")
                    }
                    .frame(width: 180)

                    Stepper("Acceptance Criteria: \(acceptanceCriteriaCount)", value: $acceptanceCriteriaCount, in: 1...10)
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

        **As a** [user/system role],
        **I want** [some behavior/feature],
        **So that** [the business benefit/value is realized].

        #### Acceptance Criteria
        \(criteria)

        #### Gherkin Scenario Definition
        ```gherkin
        Scenario: Success Flow
          Given a registered user is on the dashboard
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
