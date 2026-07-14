import SwiftUI

public struct ChangelogEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var releaseVersion = "1.0.0"
    @State private var releaseDate = ""
    @State private var releaseType = "Minor"
    @State private var deploymentEnv = "Production"
    @State private var authorsCount = 1
    @State private var ticketIdentifier = "SWIFT-101"

    // Visual SemVer Bumper Helper State
    @State private var previousVersion = "1.0.0"

    // Contributor Verification list
    @State private var isCiPassed = true
    @State private var isSecurityScanned = false
    @State private var isQaApproved = false

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        let parts = releaseVersion.split(separator: ".")
        if parts.isEmpty {
            return "Version must follow standard SemVer (e.g. 1.0.0)"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .changelogBuilder,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertChangelogSections()
                    } label: {
                        Label("Changelog Blocks", systemImage: "doc.text.below.ecg.fill")
                    }
                    .help("Insert standard Changelog block sections")

                    Button {
                        insertMigrationGuide()
                    } label: {
                        Label("Migration Block", systemImage: "arrow.right.circle.fill")
                    }
                    .help("Insert Migration upgrade instructions block")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    // Interactive SemVer Bumper
                    VStack(alignment: .leading, spacing: 6) {
                        Text("INTERACTIVE SEMVER VERSION BUMPER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Button("Major") { bumpVersion(major: true) }
                            Button("Minor") { bumpVersion(minor: true) }
                            Button("Patch") { bumpVersion(patch: true) }
                            Button("Revert") { releaseVersion = previousVersion }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider().padding(.vertical, 4)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Version:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("1.0.0", text: $releaseVersion)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Release Type:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $releaseType) {
                                Text("Major").tag("Major")
                                Text("Minor").tag("Minor")
                                Text("Patch").tag("Patch")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Release Date:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("YYYY-MM-DD", text: $releaseDate)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Environment:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $deploymentEnv) {
                                Text("Production").tag("Production")
                                Text("Staging").tag("Staging")
                                Text("Beta").tag("Beta")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Ticket ID:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. SWIFT-101", text: $ticketIdentifier)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Contributors:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Stepper("\(authorsCount)", value: $authorsCount, in: 1...50)
                                .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // Verification checklist
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRE-RELEASE CHECKS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("CI/CD Build Pipeline Passed", isOn: $isCiPassed)
                            Toggle("Static Security Analysis Completed", isOn: $isSecurityScanned)
                            Toggle("QA Integration Tests Approved", isOn: $isQaApproved)
                        }
                        .font(.system(size: 10))
                        .controlSize(.small)
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func bumpVersion(major: Bool = false, minor: Bool = false, patch: Bool = false) {
        previousVersion = releaseVersion
        let parts = releaseVersion.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return }

        var maj = parts[0]
        var min = parts[1]
        var pat = parts[2]

        if major {
            maj += 1; min = 0; pat = 0
        } else if minor {
            min += 1; pat = 0
        } else if patch {
            pat += 1
        }

        releaseVersion = "\(maj).\(min).\(pat)"
    }

    private func insertChangelogSections() {
        let actualDate = releaseDate.isEmpty ? Date().formatted(date: .numeric, time: .omitted) : releaseDate

        var verificationMarkdown = ""
        if isCiPassed { verificationMarkdown += "- [x] **CI/CD green status** validated.\n" }
        if isSecurityScanned { verificationMarkdown += "- [x] **Security scan** completed with zero high vulnerabilities.\n" }
        if isQaApproved { verificationMarkdown += "- [x] **QA acceptance testing** signed off.\n" }

        let template = """

        ## [\(releaseVersion)] - \(actualDate)

        **Release Type:** `\(releaseType)`
        **Target Environment:** `\(deploymentEnv)`
        **Linked Ticket:** `\(ticketIdentifier)`
        **Contributors:** \(authorsCount) developer(s)

        ### Added
        - New: [Description of major new features linked to \(ticketIdentifier)]
        - New: [Minor features]

        ### Changed
        - Update: [System adjustments or refactor details]

        ### Fixed
        - Bugfix: [Resolved issue description and impact]

        ### Verification Status
        \(verificationMarkdown)
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertMigrationGuide() {
        let migration = """

        ### Upgrading and Migration to `\(releaseVersion)`
        Follow these steps to migrate system resources securely:

        1. **Database Migration**: Ensure the target DB table schemas are upgraded to support v\(releaseVersion).
        2. **Environment Variables**: Verify that any new environment variables required by `\(ticketIdentifier)` are configured.
        3. **Fallback Revert**: If deployment issues occur in `\(deploymentEnv)`, trigger standard rollback commands immediately.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": migration]
        )
    }
}
