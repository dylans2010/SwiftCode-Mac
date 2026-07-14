import SwiftUI

public struct FeaturePlanningEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var targetQuarter = "Q3 2026"
    @State private var leadDeveloper = ""

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
                HStack(spacing: 20) {
                    Picker("Target Quarter:", selection: $targetQuarter) {
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
            },
            validationMessage: nil
        )
    }

    private func insertStories() {
        let template = """

        ### Proposed User Stories
        - [ ] **Story 1:** As a user, I want [action] so that [benefit].
        - [ ] **Story 2:** As a developer, I want [technical action] so that [engineering benefit].
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertMilestones() {
        let template = """

        ### Major Milestones & Timelines
        | Milestone Description | Target Date | Status |
        | :--- | :--- | :--- |
        | Core Architecture Complete | Mid-Quarter | Pending |
        | Public Beta Testing | End of Month 2 | Pending |
        | Production Release | End of Quarter | Pending |
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
