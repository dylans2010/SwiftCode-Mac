import SwiftUI

public struct StructuredRecordEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var recordSchemaType = "Generic Record"
    @State private var author = ""
    @State private var serializationFormat = "JSON"
    @State private var validationStatus = "Valid"
    @State private var dataSensitivity = "Internal-Only"

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
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
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

                    GridRow {
                        Text("Format:")
                            .font(.caption.bold())
                        Picker("", selection: $serializationFormat) {
                            Text("JSON").tag("JSON")
                            Text("YAML").tag("YAML")
                            Text("XML").tag("XML")
                            Text("Protobuf").tag("Protobuf")
                        }
                        .frame(width: 150)

                        Text("Data Sensitivity:")
                            .font(.caption.bold())
                        Picker("", selection: $dataSensitivity) {
                            Text("Public").tag("Public")
                            Text("Internal").tag("Internal-Only")
                            Text("Confidential").tag("Confidential/PII")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    GridRow {
                        Text("Validation:")
                            .font(.caption.bold())
                        Picker("", selection: $validationStatus) {
                            Text("Valid").tag("Valid")
                            Text("Invalid").tag("Invalid")
                            Text("Warning").tag("Warning")
                            Text("Pending").tag("Pending Audit")
                        }
                        .pickerStyle(.segmented)
                        .gridCellColumns(3)
                        .frame(width: 320)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertKeyValueTable() {
        let template = """

        ### Structured Key-Value Record: \(recordSchemaType)

        **Author:** `\(author.isEmpty ? "Unknown" : author)`
        **Serialization Format:** `\(serializationFormat)`
        **Data Sensitivity:** `\(dataSensitivity)`
        **Validation Status:** `\(validationStatus)`

        | Parameter / Key | Value | Datatype / Validation |
        | :--- | :--- | :--- |
        | Record ID | `REC_93041` | UUID |
        | Last Evaluated | `\(Date().formatted(date: .numeric, time: .shortened))` | DateTime |
        | Status | `\(validationStatus.uppercased())` | String / Enum |
        | Format Type | `\(serializationFormat)` | String / Format |

        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
