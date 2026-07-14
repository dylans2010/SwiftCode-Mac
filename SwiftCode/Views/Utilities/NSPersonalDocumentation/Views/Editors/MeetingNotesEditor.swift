import SwiftUI

public struct MeetingNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var meetingAttendees = ""
    @State private var meetingDate = Date()

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .meetingNotes,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertActionItems()
                } label: {
                    Label("Action Checklist", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    DatePicker("Meeting Date:", selection: $meetingDate, displayedComponents: .date)
                        .frame(width: 220)

                    Text("Attendees:")
                        .font(.caption.bold())
                    TextField("Alice, Bob, Charlie", text: $meetingAttendees)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                }
            },
            validationMessage: nil
        )
    }

    private func insertActionItems() {
        let template = """

        ### Meeting Action Items

        - [ ] **Task 1:** [Action item description] @[Assignee] (Due: [Date])
        - [ ] **Task 2:** [Action item description] @[Assignee] (Due: [Date])

        #### Next Discussion Agenda
        1. Review status of assigned action items above.
        2. Resolve outstanding structural issues.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
