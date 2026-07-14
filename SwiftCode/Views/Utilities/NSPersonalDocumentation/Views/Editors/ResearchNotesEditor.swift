import SwiftUI

public struct ResearchNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var sourceURL = ""
    @State private var researcherName = ""

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .researchLibrary,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertReference()
                } label: {
                    Label("Add Reference", systemImage: "books.vertical.fill")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Text("Researcher:")
                        .font(.caption.bold())
                    TextField("Researcher Name", text: $researcherName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    Text("Source URL:")
                        .font(.caption.bold())
                    TextField("https://...", text: $sourceURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                }
            },
            validationMessage: nil
        )
    }

    private func insertReference() {
        let template = """

        ### Research Citation & Review

        * **Author/Source:** [Insert Author]
        * **Title:** [Insert Publication Title]
        * **Access URL:** [\(sourceURL)](\(sourceURL.isEmpty ? "https://example.com" : sourceURL))

        #### Research Abstract
        Detailed technical summary of findings and takeaways of this literature or API analysis.

        #### Core Key Discoveries
        - Discovery 1
        - Discovery 2
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
