import SwiftUI

public struct DatabaseDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var databaseEngine = "PostgreSQL"
    @State private var tableName = "users"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if tableName.isEmpty {
            return "Table name cannot be empty"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .databaseDocumentation,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 8) {
                    Button {
                        insertSchemaTable()
                    } label: {
                        Label("DB Template", systemImage: "tablecells.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Insert standard database schema definition table")
                }
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Picker("Engine:", selection: $databaseEngine) {
                        Text("PostgreSQL").tag("PostgreSQL")
                        Text("MySQL").tag("MySQL")
                        Text("SQLite").tag("SQLite")
                        Text("MongoDB").tag("MongoDB")
                    }
                    .frame(width: 200)

                    Text("Table Name:")
                        .font(.caption.bold())
                    TextField("users, orders, etc.", text: $tableName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            },
            validationMessage: validationMessage
        )
    }

    private func insertSchemaTable() {
        let template = """

        ### Table Schema: `\(tableName)` (\(databaseEngine))

        | Column Name | Data Type | Constraints | Description |
        | :--- | :--- | :--- | :--- |
        | id | UUID | PRIMARY KEY | Unique identifier for the row |
        | created_at | TIMESTAMP | DEFAULT NOW() | Timestamp when record was created |
        | updated_at | TIMESTAMP | NULLABLE | Timestamp of last record update |

        #### Indexes
        - `idx_\(tableName)_id` on (`id`)

        #### Foreign Key Relations
        - None
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
