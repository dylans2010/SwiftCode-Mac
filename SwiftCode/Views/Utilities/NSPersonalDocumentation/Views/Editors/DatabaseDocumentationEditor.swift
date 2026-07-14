import SwiftUI

public struct DatabaseDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var databaseEngine = "PostgreSQL"
    @State private var tableName = "users"
    @State private var schemaVersion = "v1.0"
    @State private var rowCountEstimate = "Medium (10k-1M)"
    @State private var partitioningStrategy = "None"
    @State private var backupFrequency = "Daily"

    // Column Designer Model State
    @State private var colName = ""
    @State private var colType = "UUID"
    @State private var colPrimaryKey = false
    @State private var colNullable = false
    @State private var colDescription = ""
    @State private var tableColumns: [TableColumnSpec] = []

    struct TableColumnSpec: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var type: String
        var isPrimaryKey: Bool
        var isNullable: Bool
        var description: String
    }

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if tableName.isEmpty {
            return "Table name cannot be empty"
        }
        // Ensure table name is snake_case
        let isSnakeCase = tableName.allSatisfy { $0.isLowercase || $0 == "_" || $0.isNumber }
        if !isSnakeCase {
            return "Table name should be snake_case (e.g. user_accounts)"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .databaseDocumentation,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertSchemaTable()
                    } label: {
                        Label("Table Schema", systemImage: "tablecells.fill")
                    }
                    .help("Insert schema definition markdown table")

                    Button {
                        insertSQLScript()
                    } label: {
                        Label("SQL Script", systemImage: "terminal")
                    }
                    .help("Generate and insert SQL DDL schema script")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Engine:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $databaseEngine) {
                                Text("PostgreSQL").tag("PostgreSQL")
                                Text("MySQL").tag("MySQL")
                                Text("SQLite").tag("SQLite")
                                Text("MongoDB").tag("MongoDB")
                            }
                            .controlSize(.small)

                            Text("Table Name:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. orders", text: $tableName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Version:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("v1.0", text: $schemaVersion)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Volume:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $rowCountEstimate) {
                                Text("Low").tag("Low (<10k)")
                                Text("Medium").tag("Medium (10k-1M)")
                                Text("High").tag("High (1M+)")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Partition:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $partitioningStrategy) {
                                Text("None").tag("None")
                                Text("Hash").tag("Hash")
                                Text("Range").tag("Range")
                            }
                            .controlSize(.small)

                            Text("Backup:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $backupFrequency) {
                                Text("Hourly").tag("Hourly")
                                Text("Daily").tag("Daily")
                                Text("Weekly").tag("Weekly")
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // COLUMN SCHEMATIC DESIGNER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCHEMA COLUMN DESIGNER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Col Name", text: $colName)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Picker("", selection: $colType) {
                                    Text("UUID").tag("UUID")
                                    Text("VARCHAR").tag("VARCHAR(255)")
                                    Text("INT").tag("INTEGER")
                                    Text("TIMESTAMP").tag("TIMESTAMP")
                                    Text("BOOLEAN").tag("BOOLEAN")
                                }
                                .controlSize(.small)
                            }

                            GridRow {
                                HStack(spacing: 8) {
                                    Toggle("PKey", isOn: $colPrimaryKey)
                                    Toggle("Null", isOn: $colNullable)
                                }
                                .font(.system(size: 10))
                                .controlSize(.small)

                                TextField("Description", text: $colDescription)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                        }

                        Button("Add Column Spec") {
                            addColumn()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Column visual chip status
                        if !tableColumns.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(tableColumns) { col in
                                    HStack {
                                        Text(col.name)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        Text(col.type)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                        if col.isPrimaryKey {
                                            Text("PK")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.orange)
                                        }
                                        Spacer()
                                        Button {
                                            tableColumns.removeAll(where: { $0.id == col.id })
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func addColumn() {
        let name = colName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let spec = TableColumnSpec(
            name: name,
            type: colType,
            isPrimaryKey: colPrimaryKey,
            isNullable: colNullable,
            description: colDescription.isEmpty ? "Value description" : colDescription
        )
        tableColumns.append(spec)
        colName = ""
        colDescription = ""
        colPrimaryKey = false
        colNullable = false
    }

    private func insertSchemaTable() {
        var columnsMarkdown = "| Column Name | Data Type | Constraints | Description |\n| :--- | :--- | :--- | :--- |\n"
        if tableColumns.isEmpty {
            columnsMarkdown += "| id | UUID | PRIMARY KEY | Unique identifier for the row |\n| created_at | TIMESTAMP | DEFAULT NOW() | Timestamp when record was created |\n"
        } else {
            for col in tableColumns {
                var constraints: [String] = []
                if col.isPrimaryKey { constraints.append("PRIMARY KEY") }
                if !col.isNullable { constraints.append("NOT NULL") }
                let constraintStr = constraints.isEmpty ? "NULL" : constraints.joined(separator: ", ")
                columnsMarkdown += "| \(col.name) | \(col.type) | \(constraintStr) | \(col.description) |\n"
            }
        }

        let template = """

        ### Table Schema: `\(tableName)` (\(databaseEngine))

        **Schema Version:** `\(schemaVersion)`
        **Estimated Data Volume:** `\(rowCountEstimate)`
        **Partitioning:** `\(partitioningStrategy)`
        **Backup Frequency:** `\(backupFrequency)`

        \(columnsMarkdown)

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

    private func insertSQLScript() {
        var createSQL = "CREATE TABLE \(tableName) (\n"
        if tableColumns.isEmpty {
            createSQL += "    id UUID PRIMARY KEY,\n    created_at TIMESTAMP DEFAULT NOW()\n"
        } else {
            var colSQLs: [String] = []
            for col in tableColumns {
                var colDef = "    \(col.name) \(col.type)"
                if col.isPrimaryKey { colDef += " PRIMARY KEY" }
                else if !col.isNullable { colDef += " NOT NULL" }
                colSQLs.append(colDef)
            }
            createSQL += colSQLs.joined(separator: ",\n") + "\n"
        }
        createSQL += ");"

        let sqlBlock = """

        #### SQL Schema Script (v\(schemaVersion))
        ```sql
        \(createSQL)
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": sqlBlock]
        )
    }
}
