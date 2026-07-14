import SwiftUI

public struct TestingNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var coverageTarget = "85%"
    @State private var testEnvironment = "Simulator"
    @State private var testFramework = "XCTest"
    @State private var testCategory = "Unit Test"
    @State private var linkedBugID = ""
    @State private var executionStatus = "Passed"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .testingNotes,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertTestGrid()
                } label: {
                    Label("Test Matrix", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Test Env:")
                            .font(.caption.bold())
                        Picker("", selection: $testEnvironment) {
                            Text("Simulator").tag("Simulator")
                            Text("Device").tag("Device")
                            Text("CI Server").tag("CI Server")
                        }
                        .frame(width: 150)

                        Text("Coverage Target:")
                            .font(.caption.bold())
                        TextField("80%", text: $coverageTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }

                    GridRow {
                        Text("Framework:")
                            .font(.caption.bold())
                        Picker("", selection: $testFramework) {
                            Text("XCTest").tag("XCTest")
                            Text("Playwright").tag("Playwright")
                            Text("Selenium").tag("Selenium")
                            Text("Quick/Nimble").tag("Quick/Nimble")
                        }
                        .frame(width: 150)

                        Text("Test Category:")
                            .font(.caption.bold())
                        Picker("", selection: $testCategory) {
                            Text("Unit Test").tag("Unit Test")
                            Text("Integration").tag("Integration")
                            Text("UI/E2E").tag("UI/E2E")
                            Text("Performance").tag("Performance/Load")
                        }
                        .frame(width: 150)
                    }

                    GridRow {
                        Text("Bug/Ticket ID:")
                            .font(.caption.bold())
                        TextField("e.g. BUG-304", text: $linkedBugID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        Text("Execution Status:")
                            .font(.caption.bold())
                        Picker("", selection: $executionStatus) {
                            Text("Passed").tag("Passed")
                            Text("Failed").tag("Failed")
                            Text("Blocked").tag("Blocked")
                            Text("Not Run").tag("Not Run")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertTestGrid() {
        let template = """

        ### QA & Testing Notes Specifications

        **Target Coverage:** \(coverageTarget)
        **Testing Environment:** \(testEnvironment)
        **Automation Framework:** `\(testFramework)`
        **Test Category:** `\(testCategory)`
        **Linked Ticket:** `\(linkedBugID.isEmpty ? "None" : linkedBugID)`
        **Current Execution Status:** `\(executionStatus)`

        #### Test Case Matrix
        | ID | Test Scenario | Inputs / Steps | Expected Result | Status |
        | :--- | :--- | :--- | :--- | :--- |
        | TC01 | Create API Doc | Click create API Doc, insert path | Document created and launches APIDocumentationEditor | \(executionStatus) |
        | TC02 | Sidebar Category Switch | Select Database Doc | active editor replaced entirely | \(executionStatus) |

        #### Diagnostics & Artifacts
        - Execution Log: Verified under `\(testEnvironment)` on `\(Date().formatted(date: .numeric, time: .shortened))`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
