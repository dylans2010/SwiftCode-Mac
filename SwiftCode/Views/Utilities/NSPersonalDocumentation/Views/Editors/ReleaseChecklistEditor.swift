import SwiftUI

public struct ReleaseChecklistEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var targetEnvironment = "Production"
    @State private var releaseManager = ""

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .releaseChecklist,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertChecklist()
                } label: {
                    Label("Deployment Checklist", systemImage: "shippingbox.fill")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Picker("Environment:", selection: $targetEnvironment) {
                        Text("Staging").tag("Staging")
                        Text("Production").tag("Production")
                    }
                    .frame(width: 180)

                    Text("Release Lead:")
                        .font(.caption.bold())
                    TextField("Name", text: $releaseManager)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            },
            validationMessage: nil
        )
    }

    private func insertChecklist() {
        let template = """

        ### Release Deployment Checklist (Target: \(targetEnvironment))

        **Release Lead:** \(releaseManager)

        #### Pre-flight Checks
        - [ ] Verify that CI/CD builds successfully and all target unit tests pass.
        - [ ] Run security code analysis scanning on release branches.

        #### Deployment Steps
        1. [ ] Back up target database structures (SQL Dump).
        2. [ ] Deploy application binaries to clusters/staging.
        3. [ ] Run active smoke validation tests.

        #### Verification & Sign-off
        - [ ] Run active end-to-end regression workflows.
        - [ ] Set tags on origin git branch.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
