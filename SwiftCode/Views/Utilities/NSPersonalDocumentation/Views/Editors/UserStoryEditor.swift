import SwiftUI

public struct UserStoryEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var acceptanceCriteriaCount = 3
    @State private var priority = "High"
    @State private var personaTarget = "Standard User"
    @State private var storyPoints = "3"
    @State private var epic = "Authentication"
    @State private var statusState = "Backlog"

    // Gherkin Scenario Builder States
    @State private var gherkinScenarioName = "Success Flow"
    @State private var gherkinGiven = "a registered user is on the dashboard"
    @State private var gherkinWhen = "they tap Create New Entry"
    @State private var gherkinThen = "they are presented with a type-selection popover"

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
                HStack(spacing: 6) {
                    Button {
                        insertGherkin()
                    } label: {
                        Label("Gherkin Scenario", systemImage: "doc.text.image")
                    }
                    .help("Insert acceptance criteria and Gherkin Scenario template block")

                    Button {
                        insertDoD()
                    } label: {
                        Label("DoD Checklist", systemImage: "checkmark.seal.fill")
                    }
                    .help("Insert standard Definition of Done checklist block")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Priority:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $priority) {
                                Text("High").tag("High")
                                Text("Med").tag("Medium")
                                Text("Low").tag("Low")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Points:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $storyPoints) {
                                Text("1").tag("1")
                                Text("3").tag("3")
                                Text("5").tag("5")
                                Text("8").tag("8")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Persona:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $personaTarget) {
                                Text("User").tag("Standard User")
                                Text("Admin").tag("Administrator")
                                Text("Client").tag("Developer API Client")
                            }
                            .controlSize(.small)

                            Text("Criteria:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Stepper("\(acceptanceCriteriaCount)", value: $acceptanceCriteriaCount, in: 1...10)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Epic Link:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Epic Name", text: $epic)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Status:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $statusState) {
                                Text("Backlog").tag("Backlog")
                                Text("Dev").tag("In Dev")
                                Text("Done").tag("Done")
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // GHERKIN SCENARIO BUILDER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("INTERACTIVE GHERKIN SCENARIO BUILDER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Scenario name...", text: $gherkinScenarioName)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                            GridRow {
                                Text("Given")
                                    .font(.system(size: 8, weight: .bold))
                                TextField("Context...", text: $gherkinGiven)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("When")
                                    .font(.system(size: 8, weight: .bold))
                                TextField("Action...", text: $gherkinWhen)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("Then")
                                    .font(.system(size: 8, weight: .bold))
                                TextField("Outcome...", text: $gherkinThen)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                        }

                        Button("Insert Scenario Block") {
                            insertScenarioBlock()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertScenarioBlock() {
        let block = """

        #### Gherkin Scenario: \(gherkinScenarioName)
        ```gherkin
        Scenario: \(gherkinScenarioName)
          Given \(gherkinGiven)
          When \(gherkinWhen)
          Then \(gherkinThen)
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": block]
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
        Scenario: \(gherkinScenarioName)
          Given \(gherkinGiven)
          When \(gherkinWhen)
          Then \(gherkinThen)
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertDoD() {
        let dod = """

        #### Definition of Done (DoD) Checklist
        - [ ] All Acceptance Criteria (\(acceptanceCriteriaCount) ACs) are verified and passing.
        - [ ] Unit test coverage conforms to target requirements.
        - [ ] Peer design and code review completed successfully.
        - [ ] Compliance security checks completed.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": dod]
        )
    }
}
