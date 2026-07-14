import SwiftUI

public struct FreeformDocumentEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var tags = "Documentation"
    @State private var isSticky = false

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .freeformDocument,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertTOC()
                } label: {
                    Label("Table of Contents", systemImage: "list.bullet.indent")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Text("Tags:")
                        .font(.caption.bold())
                    TextField("comma separated tags", text: $tags)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Toggle("Sticky Note", isOn: $isSticky)
                        .help("Keep this note at the top of lists")
                }
            },
            validationMessage: nil
        )
    }

    private func insertTOC() {
        let template = """

        ### Table of Contents
        1. [Overview](#overview)
        2. [Background & Objectives](#background)
        3. [Core Logic Implementation](#implementation)
        4. [Results & Analysis](#analysis)

        ---
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
