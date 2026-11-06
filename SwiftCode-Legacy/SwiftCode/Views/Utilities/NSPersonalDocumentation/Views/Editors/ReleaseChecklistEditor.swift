import SwiftUI

public struct ReleaseChecklistEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var targetEnvironment = "Production"
    @State private var releaseManager = ""
    @State private var buildVersion = "v1.0.0"
    @State private var deploymentType = "Canary"
    @State private var verificationMethod = "Automated E2E"
    @State private var rollbackStrategy = "Automatic Rollback"

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
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Environment:")
                            .font(.caption.bold())
                        Picker("", selection: $targetEnvironment) {
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

                    GridRow {
                        Text("Build Version:")
                            .font(.caption.bold())
                        TextField("e.g. v1.0.0", text: $buildVersion)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Text("Deployment Type:")
                            .font(.caption.bold())
                        Picker("", selection: $deploymentType) {
                            Text("Rolling Update").tag("Rolling Update")
                            Text("Blue-Green").tag("Blue-Green")
                            Text("Canary").tag("Canary")
                            Text("Recreate").tag("Recreate")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("Verification:")
                            .font(.caption.bold())
                        Picker("", selection: $verificationMethod) {
                            Text("Automated E2E").tag("Automated E2E")
                            Text("Manual Acceptance").tag("Manual Acceptance")
                            Text("Smoke Tests Only").tag("Smoke Tests Only")
                        }
                        .frame(width: 180)

                        Text("Rollback Plan:")
                            .font(.caption.bold())
                        Picker("", selection: $rollbackStrategy) {
                            Text("Automatic Rollback").tag("Automatic Rollback")
                            Text("Manual Revert").tag("Manual Revert")
                            Text("Fail Forward").tag("Fail Forward")
                        }
                        .frame(width: 180)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertChecklist() {
        let template = """

        ### Release Deployment Checklist (Target: \(targetEnvironment))

        **Release Lead:** \(releaseManager)
        **Build Version:** `\(buildVersion)`
        **Deployment Type:** `\(deploymentType)`
        **Verification Method:** `\(verificationMethod)`
        **Rollback Strategy:** `\(rollbackStrategy)`

        #### Pre-flight Checks
        - [ ] Verify that CI/CD builds successfully and all target unit tests pass.
        - [ ] Run security code analysis scanning on release branches.

        #### Deployment Steps (\(deploymentType))
        1. [ ] Back up target database structures (SQL Dump).
        2. [ ] Deploy application binaries `\(buildVersion)` to clusters.
        3. [ ] Run active smoke validation tests using `\(verificationMethod)`.

        #### Verification & Sign-off
        - [ ] Run active end-to-end regression workflows.
        - [ ] Set tags on origin git branch.

        #### Emergency Mitigation
        - Rollback Strategy: `\(rollbackStrategy)`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
