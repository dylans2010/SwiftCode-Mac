import SwiftUI

public struct StructuredRecordEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var recordSchemaType = "Generic Record"
    @State private var author = ""

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .structuredRecord,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertKeyValueTable()
                } label: {
                    Label("KV Table", systemImage: "tablecells.fill")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Text("Schema Type:")
                        .font(.caption.bold())
                    TextField("Schema, JSON, XML", text: $recordSchemaType)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    Text("Author:")
                        .font(.caption.bold())
                    TextField("Name", text: $author)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            },
            validationMessage: nil
        )
    }

    private func insertKeyValueTable() {
        let template = """

        ### Structured Key-Value Record: \(recordSchemaType)

        | Parameter / Key | Value | Datatype / Validation |
        | :--- | :--- | :--- |
        | Record ID | `REC_93041` | UUID |
        | Last Evaluated | `\(Date().formatted(date: .numeric, time: .shortened))` | DateTime |
        | Status | `PASS` | String / Enum |

        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
