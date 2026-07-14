import SwiftUI

public struct ReleaseChecklistEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var targetEnvironment = "Production"
    @State private var releaseManager = ""
    @State private var buildVersion = "v1.0.0"
    @State private var deploymentType = "Canary"
    @State private var verificationMethod = "Automated E2E"
    @State private var rollbackStrategy = "Automatic Rollback"

    // Interactive Checklist Steps
    @State private var step1Completed = false
    @State private var step2Completed = false
    @State private var step3Completed = false
    @State private var step4Completed = false

    private var deploymentProgress: Double {
        var completed = 0.0
        if step1Completed { completed += 1 }
        if step2Completed { completed += 1 }
        if step3Completed { completed += 1 }
        if step4Completed { completed += 1 }
        return completed / 4.0
    }

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if buildVersion.isEmpty {
            return "Build version is required"
        }
        if !buildVersion.hasPrefix("v") {
            return "Build version must start with 'v' (e.g. v1.2.3)"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .releaseChecklist,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertChecklist()
                    } label: {
                        Label("Release Checklist", systemImage: "shippingbox.fill")
                    }
                    .help("Insert step-by-step Release Checklist protocol template")

                    Button {
                        insertRollbackPlaybook()
                    } label: {
                        Label("Rollback Playbook", systemImage: "arrow.counterclockwise.shield.fill")
                    }
                    .help("Insert Emergency Rollback Playbook blueprint")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    // Deployment progress bar visual
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("DEPLOYMENT STEP PROGRESS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(deploymentProgress * 100))%")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.accentColor)
                        }

                        ProgressView(value: deploymentProgress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Environment:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $targetEnvironment) {
                                Text("Staging").tag("Staging")
                                Text("Production").tag("Production")
                            }
                            .controlSize(.small)

                            Text("Release Lead:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Name", text: $releaseManager)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Build:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. v1.0.0", text: $buildVersion)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Type:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $deploymentType) {
                                Text("Rolling").tag("Rolling Update")
                                Text("Blue-Green").tag("Blue-Green")
                                Text("Canary").tag("Canary")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Verification:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $verificationMethod) {
                                Text("E2E").tag("Automated E2E")
                                Text("Manual").tag("Manual Acceptance")
                                Text("Smoke").tag("Smoke Tests Only")
                            }
                            .controlSize(.small)

                            Text("Rollback:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $rollbackStrategy) {
                                Text("Auto").tag("Automatic Rollback")
                                Text("Manual").tag("Manual Revert")
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // STEPPER CHECKLIST
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STEP-BY-STEP DEPLOYMENT GATEWAY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("1. Database Backup Completed", isOn: $step1Completed)
                            Toggle("2. Binary Clusters Complied & Tagged", isOn: $step2Completed)
                            Toggle("3. Active Traffic Routing Verified", isOn: $step3Completed)
                            Toggle("4. Smoke Regression Validated", isOn: $step4Completed)
                        }
                        .font(.system(size: 10))
                        .controlSize(.small)
                    }
                }
            },
            validationMessage: validationMessage
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
        - [\(step1Completed ? "x" : " ")] Verify that CI/CD builds successfully and all target unit tests pass.
        - [\(step1Completed ? "x" : " ")] Run security code analysis scanning on release branches.

        #### Deployment Steps (\(deploymentType))
        1. [\(step2Completed ? "x" : " ")] Back up target database structures (SQL Dump).
        2. [\(step3Completed ? "x" : " ")] Deploy application binaries `\(buildVersion)` to clusters.
        3. [\(step4Completed ? "x" : " ")] Run active smoke validation tests using `\(verificationMethod)`.

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

    private func insertRollbackPlaybook() {
        let playbook = """

        ### Emergency Rollback Playbook (Build: `\(buildVersion)`)
        If deployment checks fail, follow these step-by-step mitigation routines immediately:

        1. **Traffic Re-routing**: Shift traffic immediately back to prior production binaries.
        2. **Database Revert**: Roll back database schema to prior snapshots.
        3. **SLA Diagnostics**: Execute post-incident analysis on rollback actions.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": playbook]
        )
    }
}
