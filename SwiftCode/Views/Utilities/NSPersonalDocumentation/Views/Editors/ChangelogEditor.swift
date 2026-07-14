import SwiftUI

public struct ChangelogEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var releaseVersion = "1.0.0"
    @State private var releaseDate = ""

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
                HStack(spacing: 20) {
                    Text("Version:")
                        .font(.caption.bold())
                    TextField("1.0.0", text: $releaseVersion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Text("Release Date:")
                        .font(.caption.bold())
                    TextField("YYYY-MM-DD", text: $releaseDate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            },
            validationMessage: nil
        )
    }

    private func insertChangelogSections() {
        let template = """

        ## [\(releaseVersion)] - \(releaseDate.isEmpty ? Date().formatted(date: .numeric, time: .omitted) : releaseDate)

        ### Added
        - New: [Description of major new features]
        - New: [Minor features]

        ### Changed
        - Update: [System adjustments or refactor details]

        ### Fixed
        - Bugfix: [Resolved issue description and impact]
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
