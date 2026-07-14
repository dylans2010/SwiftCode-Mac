import SwiftUI

public struct MeetingNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var meetingAttendees = ""
    @State private var meetingDate = Date()
    @State private var meetingType = "Standup"
    @State private var facilitatorName = ""
    @State private var duration = "30m"
    @State private var nextFollowUpDate = Date()

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
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        DatePicker("Meeting Date:", selection: $meetingDate, displayedComponents: .date)
                            .frame(width: 220)

                        Text("Attendees:")
                            .font(.caption.bold())
                        TextField("Alice, Bob, Charlie", text: $meetingAttendees)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }

                    GridRow {
                        Text("Meeting Type:")
                            .font(.caption.bold())
                        Picker("", selection: $meetingType) {
                            Text("Standup").tag("Standup")
                            Text("Sprint Planning").tag("Sprint Planning")
                            Text("Retro").tag("Retro")
                            Text("Architecture Sync").tag("Architecture Sync")
                            Text("1-on-1").tag("1-on-1")
                        }
                        .frame(width: 180)

                        Text("Facilitator:")
                            .font(.caption.bold())
                        TextField("Facilitator Name", text: $facilitatorName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    GridRow {
                        Text("Duration:")
                            .font(.caption.bold())
                        Picker("", selection: $duration) {
                            Text("15m").tag("15m")
                            Text("30m").tag("30m")
                            Text("45m").tag("45m")
                            Text("1h").tag("1h")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)

                        DatePicker("Follow-up Date:", selection: $nextFollowUpDate, displayedComponents: .date)
                            .frame(width: 220)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertActionItems() {
        let template = """

        ### Meeting Protocol & Notes

        **Meeting Type:** `\(meetingType)`
        **Facilitator:** `\(facilitatorName.isEmpty ? "Self" : facilitatorName)`
        **Duration:** `\(duration)`
        **Attendees:** \(meetingAttendees.isEmpty ? "N/A" : meetingAttendees)
        **Date:** \(meetingDate.formatted(date: .abbreviated, time: .omitted))
        **Follow-up Scheduled:** \(nextFollowUpDate.formatted(date: .abbreviated, time: .omitted))

        #### Action Items Checklist
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
