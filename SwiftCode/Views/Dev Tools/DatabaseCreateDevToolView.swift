import SwiftUI
import os.log

struct TableColumnItem: Identifiable {
    let id = UUID()
    var name: String
    var type: String
    var isPrimaryKey: Bool
}

@Observable
@MainActor
final class DatabaseCreateViewModel {
    var tableName: String = "users"
    var columns: [TableColumnItem] = [
        TableColumnItem(name: "id", type: "INTEGER", isPrimaryKey: true),
        TableColumnItem(name: "username", type: "TEXT", isPrimaryKey: false),
        TableColumnItem(name: "created_at", type: "DATETIME", isPrimaryKey: false)
    ]

    var generatedSQL: String {
        var sql = "CREATE TABLE \(tableName) (\n"
        let cols = columns.map { col in
            var line = "    \(col.name) \(col.type)"
            if col.isPrimaryKey {
                line += " PRIMARY KEY AUTOINCREMENT"
            }
            return line
        }
        sql += cols.joined(separator: ",\n")
        sql += "\n);"
        return sql
    }

    func addColumn() {
        columns.append(TableColumnItem(name: "new_column", type: "TEXT", isPrimaryKey: false))
    }
}

struct DatabaseCreateDevToolView: View {
    @State private var viewModel = DatabaseCreateViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Visually build SQL relational database tables and export standard CREATE TABLE scripts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Table Name")
                        .font(.headline)
                    TextField("users", text: $viewModel.tableName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                HStack {
                    Text("Columns")
                        .font(.headline)
                    Spacer()
                    Button("Add Column") {
                        viewModel.addColumn()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(spacing: 10) {
                    ForEach(0..<viewModel.columns.count, id: \.self) { index in
                        HStack(spacing: 12) {
                            TextField("Column Name", text: Binding(
                                get: { viewModel.columns[index].name },
                                set: { viewModel.columns[index].name = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Picker("", selection: Binding(
                                get: { viewModel.columns[index].type },
                                set: { viewModel.columns[index].type = $0 }
                            )) {
                                Text("INTEGER").tag("INTEGER")
                                Text("TEXT").tag("TEXT")
                                Text("DATETIME").tag("DATETIME")
                                Text("REAL").tag("REAL")
                            }
                            .frame(width: 120)

                            Toggle("PK", isOn: Binding(
                                get: { viewModel.columns[index].isPrimaryKey },
                                set: { viewModel.columns[index].isPrimaryKey = $0 }
                            ))
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Generated SQL CREATE TABLE")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(viewModel.generatedSQL, forType: .string)
                        }) {
                            Label("Copy SQL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }

                    TextEditor(text: .constant(viewModel.generatedSQL))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)
                        .border(Color.secondary.opacity(0.15))
                }
            }
            .padding()
        }
        .navigationTitle("Database Schema Builder")
    }
}
