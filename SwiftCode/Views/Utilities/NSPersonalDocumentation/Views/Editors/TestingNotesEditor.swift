import SwiftUI

public struct TestingNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var coverageTarget = "85%"
    @State private var testEnvironment = "Simulator"

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
                HStack(spacing: 20) {
                    Picker("Test Env:", selection: $testEnvironment) {
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
            },
            validationMessage: nil
        )
    }

    private func insertTestGrid() {
        let template = """

        ### QA & Testing Notes Specifications

        **Target Coverage:** \(coverageTarget)
        **Testing Environment:** \(testEnvironment)

        #### Test Case Matrix
        | ID | Test Scenario | Inputs / Steps | Expected Result | Status |
        | :--- | :--- | :--- | :--- | :--- |
        | TC01 | Create API Doc | Click create API Doc, insert path | Document created and launches APIDocumentationEditor | Passed |
        | TC02 | Sidebar Category Switch | Select Database Doc | active editor replaced entirely | Passed |

        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
