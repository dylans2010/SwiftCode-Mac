import SwiftUI

public struct MeetingNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var meetingAttendees = ""
    @State private var meetingDate = Date()
    @State private var meetingType = "Standup"
    @State private var facilitatorName = ""
    @State private var duration = "30m"
    @State private var nextFollowUpDate = Date()

    // Action Items Generator Model State
    @State private var actionDesc = ""
    @State private var actionAssignee = ""
    @State private var actionDueDate = Date()
    @State private var trackingActions: [ActionItem] = []

    struct ActionItem: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var assignee: String
        var dueDate: Date
    }

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
                HStack(spacing: 6) {
                    Button {
                        insertActionItems()
                    } label: {
                        Label("Action Checklist", systemImage: "checklist")
                    }
                    .help("Insert complete meeting minutes and action items checklist")

                    Button {
                        insertAgendaBlock()
                    } label: {
                        Label("Agenda Outline", systemImage: "list.bullet.clipboard")
                    }
                    .help("Insert meeting agenda outline boilerplate")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Type:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $meetingType) {
                                Text("Standup").tag("Standup")
                                Text("Sprint").tag("Sprint Planning")
                                Text("Retro").tag("Retro")
                                Text("Sync").tag("Architecture Sync")
                            }
                            .controlSize(.small)

                            Text("Duration:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $duration) {
                                Text("15m").tag("15m")
                                Text("30m").tag("30m")
                                Text("1h").tag("1h")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Attendees:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Alice, Bob", text: $meetingAttendees)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Facilitator:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Name", text: $facilitatorName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            DatePicker("Date:", selection: $meetingDate, displayedComponents: .date)
                                .font(.system(size: 10))
                                .controlSize(.small)
                                .gridCellColumns(2)

                            DatePicker("Follow-up:", selection: $nextFollowUpDate, displayedComponents: .date)
                                .font(.system(size: 10))
                                .controlSize(.small)
                                .gridCellColumns(2)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // INTERACTIVE ACTION ITEMS GENERATOR
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ACTION ITEM MANAGER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Action task description...", text: $actionDesc)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                            GridRow {
                                TextField("Assignee", text: $actionAssignee)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                DatePicker("Due", selection: $actionDueDate, displayedComponents: .date)
                                    .font(.system(size: 10))
                                    .controlSize(.small)
                            }
                        }

                        Button("Add Action Item") {
                            addAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Action items catalog list
                        if !trackingActions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(trackingActions) { item in
                                    HStack {
                                        Text(item.text)
                                            .font(.system(size: 9, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        if !item.assignee.isEmpty {
                                            Text("@\(item.assignee)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.accentColor)
                                        }
                                        Button {
                                            trackingActions.removeAll(where: { $0.id == item.id })
                                        } label: {
                                            Image(systemName: "xmark").font(.system(size: 7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func addAction() {
        let trimmed = actionDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = ActionItem(
            text: trimmed,
            assignee: actionAssignee.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: actionDueDate
        )
        trackingActions.append(item)
        actionDesc = ""
        actionAssignee = ""
    }

    private func insertActionItems() {
        var actionsMarkdown = ""
        if trackingActions.isEmpty {
            actionsMarkdown += "- [ ] **Task 1**: Outline technical specifications @[Assignee] (Due: [Date])\n- [ ] **Task 2**: Establish pipeline deployments @[Assignee] (Due: [Date])\n"
        } else {
            for item in trackingActions {
                let assigneeTag = item.assignee.isEmpty ? "" : " @\(item.assignee)"
                let dueTag = " (Due: \(item.dueDate.formatted(date: .abbreviated, time: .omitted)))"
                actionsMarkdown += "- [ ] **\(item.text)**\(assigneeTag)\(dueTag)\n"
            }
        }

        let template = """

        ### Meeting Protocol & Action Items

        **Meeting Type:** `\(meetingType)`
        **Facilitator:** `\(facilitatorName.isEmpty ? "Self" : facilitatorName)`
        **Duration:** `\(duration)`
        **Attendees:** \(meetingAttendees.isEmpty ? "N/A" : meetingAttendees)
        **Date:** \(meetingDate.formatted(date: .abbreviated, time: .omitted))
        **Follow-up Scheduled:** \(nextFollowUpDate.formatted(date: .abbreviated, time: .omitted))

        #### Action Items Checklist
        \(actionsMarkdown)

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

    private func insertAgendaBlock() {
        let agenda = """

        #### Proposed Meeting Agenda Outline
        - **00:00 - 00:05**: Roll Call & Quick Status Updates.
        - **00:05 - 00:20**: Technical Review of `\(meetingType)`.
        - **00:20 - 00:30**: Open Discussions & Action Assignments.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": agenda]
        )
    }
}
