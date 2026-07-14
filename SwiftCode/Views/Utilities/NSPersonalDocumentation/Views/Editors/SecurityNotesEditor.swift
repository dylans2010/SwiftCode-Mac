import SwiftUI

public struct SecurityNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var securitySeverity = "Critical"
    @State private var scope = "Internal"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .securityNotes,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 8) {
                    Button {
                        insertThreatModel()
                    } label: {
                        Label("Threat Model", systemImage: "shield.fill")
                    }
                    .buttonStyle(.bordered)
                }
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Picker("Severity:", selection: $securitySeverity) {
                        Text("Critical").tag("Critical")
                        Text("High").tag("High")
                        Text("Medium").tag("Medium")
                        Text("Low").tag("Low")
                    }
                    .frame(width: 150)

                    Picker("Scope:", selection: $scope) {
                        Text("Internal").tag("Internal")
                        Text("External").tag("External")
                    }
                    .frame(width: 150)
                }
            },
            validationMessage: nil
        )
    }

    private func insertThreatModel() {
        let template = """

        ### Threat Model & Mitigation Notes

        **Severity:** \(securitySeverity)
        **Review Scope:** \(scope)

        #### Potential Threat Vector
        - **Threat:** [Description of possible attack vector]
        - **Asset at Risk:** [Database, Authentication Token, etc.]

        #### Mitigation Strategy
        - **Action:** [Steps to mitigate risk, e.g. input validation, encryption at rest]
        - **Validator:** [Testing process to ensure verification]
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
