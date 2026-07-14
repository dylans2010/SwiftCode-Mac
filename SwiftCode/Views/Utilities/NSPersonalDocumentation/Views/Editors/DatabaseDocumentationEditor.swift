import SwiftUI

public struct DatabaseDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var databaseEngine = "PostgreSQL"
    @State private var tableName = "users"
    @State private var schemaVersion = "v1.0"
    @State private var rowCountEstimate = "Medium (10k-1M)"
    @State private var partitioningStrategy = "None"
    @State private var backupFrequency = "Daily"

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
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Engine:")
                            .font(.caption.bold())
                        Picker("", selection: $databaseEngine) {
                            Text("PostgreSQL").tag("PostgreSQL")
                            Text("MySQL").tag("MySQL")
                            Text("SQLite").tag("SQLite")
                            Text("MongoDB").tag("MongoDB")
                        }
                        .frame(width: 180)

                        Text("Table Name:")
                            .font(.caption.bold())
                        TextField("users, orders, etc.", text: $tableName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    GridRow {
                        Text("Schema Version:")
                            .font(.caption.bold())
                        TextField("e.g. v1.0", text: $schemaVersion)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Text("Volume Estimate:")
                            .font(.caption.bold())
                        Picker("", selection: $rowCountEstimate) {
                            Text("Low (<10k)").tag("Low (<10k)")
                            Text("Medium (10k-1M)").tag("Medium (10k-1M)")
                            Text("High (1M+)").tag("High (1M+)")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("Partition Strategy:")
                            .font(.caption.bold())
                        Picker("", selection: $partitioningStrategy) {
                            Text("None").tag("None")
                            Text("Hash").tag("Hash")
                            Text("Range").tag("Range")
                            Text("List").tag("List")
                        }
                        .frame(width: 180)

                        Text("Backup Freq:")
                            .font(.caption.bold())
                        Picker("", selection: $backupFrequency) {
                            Text("Hourly").tag("Hourly")
                            Text("Daily").tag("Daily")
                            Text("Weekly").tag("Weekly")
                        }
                        .frame(width: 180)
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func insertSchemaTable() {
        let template = """

        ### Table Schema: `\(tableName)` (\(databaseEngine))

        **Schema Version:** `\(schemaVersion)`
        **Estimated Data Volume:** `\(rowCountEstimate)`
        **Partitioning:** `\(partitioningStrategy)`
        **Backup Frequency:** `\(backupFrequency)`

        | Column Name | Data Type | Constraints | Description |
        | :--- | :--- | :--- | :--- |
        | id | UUID | PRIMARY KEY | Unique identifier for the row |
        | created_at | TIMESTAMP | DEFAULT NOW() | Timestamp when record was created |
        | updated_at | TIMESTAMP | NULLABLE | Timestamp of last record update |

        #### Indexes
        - `idx_\(tableName)_id` on (`id`)

        #### Partition Details
        - Partitioning Scheme: `\(partitioningStrategy)`

        #### Disaster Recovery
        - Backup Interval: `\(backupFrequency)`
        - Storage Target: Encrypted S3 Bucket object lock
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
