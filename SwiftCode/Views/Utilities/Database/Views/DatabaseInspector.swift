import SwiftUI

struct DatabaseInspector: View {
    @Binding var selectedTable: DatabaseTable?
    @Binding var selectedColumn: DatabaseColumn?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let table = selectedTable {
                    Text("Table Inspector")
                        .font(.headline)

                    GroupBox("Metadata") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name: \(table.name)")
                                .font(.subheadline.bold())
                            if let comment = table.comment {
                                Text("Comment: \(comment)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("Records: \(table.recordCount)")
                                .font(.caption)
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let col = selectedColumn {
                        Text("Column Details")
                            .font(.subheadline.bold())
                            .padding(.top, 8)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Name: \(col.name)")
                                Text("Type: \(col.type)")
                                Toggle("Primary Key", isOn: .constant(col.isPrimaryKey)).disabled(true)
                                Toggle("Nullable", isOn: .constant(col.isNullable)).disabled(true)
                                Toggle("Unique", isOn: .constant(col.isUnique)).disabled(true)
                                if let def = col.defaultValue {
                                    Text("Default: \(def)")
                                }
                            }
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("Select a Column inside Schema Designer or Spreadsheet rows to inspect advanced details.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                } else {
                    ContentUnavailableView {
                        Label("No Selection", systemImage: "info.circle")
                    } description: {
                        Text("Select a Table or Column to view and modify details.")
                    }
                }
            }
            .padding()
        }
    }
}
