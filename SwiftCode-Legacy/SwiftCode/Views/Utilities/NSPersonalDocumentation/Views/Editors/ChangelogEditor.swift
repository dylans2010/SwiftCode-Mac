import SwiftUI

public struct ChangelogEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var releaseVersion = "1.0.0"
    @State private var releaseDate = ""
    @State private var releaseType = "Minor"
    @State private var deploymentEnv = "Production"
    @State private var authorsCount = 1
    @State private var ticketIdentifier = "SWIFT-101"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .changelogBuilder,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertChangelogSections()
                } label: {
                    Label("Changelog Blocks", systemImage: "doc.text.below.ecg.fill")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Version:")
                            .font(.caption.bold())
                        TextField("1.0.0", text: $releaseVersion)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        Text("Release Type:")
                            .font(.caption.bold())
                        Picker("", selection: $releaseType) {
                            Text("Major").tag("Major")
                            Text("Minor").tag("Minor")
                            Text("Patch").tag("Patch")
                            Text("Hotfix").tag("Hotfix")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    GridRow {
                        Text("Release Date:")
                            .font(.caption.bold())
                        TextField("YYYY-MM-DD", text: $releaseDate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        Text("Environment:")
                            .font(.caption.bold())
                        Picker("", selection: $deploymentEnv) {
                            Text("Production").tag("Production")
                            Text("Staging").tag("Staging")
                            Text("Beta").tag("Beta")
                        }
                        .frame(width: 150)
                    }

                    GridRow {
                        Text("Ticket ID:")
                            .font(.caption.bold())
                        TextField("e.g. JIRA-101", text: $ticketIdentifier)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        Text("Contributors:")
                            .font(.caption.bold())
                        Stepper("\(authorsCount)", value: $authorsCount, in: 1...50)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertChangelogSections() {
        let template = """

        ## [\(releaseVersion)] - \(releaseDate.isEmpty ? Date().formatted(date: .numeric, time: .omitted) : releaseDate)

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

        ### Security
        - Audited: Security hardening completed for release type `\(releaseType)`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
