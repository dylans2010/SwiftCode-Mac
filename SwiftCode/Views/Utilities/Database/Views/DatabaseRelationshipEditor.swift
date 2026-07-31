import SwiftUI

struct DatabaseRelationshipEditor: View {
    @Environment(\.dismiss) private var dismiss
    let tables: [DatabaseTable]
    var onSave: (DatabaseRelationship) -> Void

    @State private var type: RelationshipType = .oneToMany
    @State private var sourceTable = ""
    @State private var sourceColumn = ""
    @State private var targetTable = ""
    @State private var targetColumn = ""
    @State private var onDelete: ReferentialAction = .cascade
    @State private var onUpdate: ReferentialAction = .cascade

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Design Relationship")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            .background(Color.secondary.opacity(0.08))

            Form {
                Section("Properties") {
                    Picker("Relationship Type", selection: $type) {
                        ForEach(RelationshipType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                }

                Section("Source (Foreign Key Table)") {
                    Picker("Source Table", selection: $sourceTable) {
                        ForEach(tables) { t in
                            Text(t.name).tag(t.name)
                        }
                    }

                    if let tableObj = tables.first(where: { $0.name == sourceTable }) {
                        Picker("Source Column", selection: $sourceColumn) {
                            ForEach(tableObj.columns) { c in
                                Text(c.name).tag(c.name)
                            }
                        }
                    }
                }

                Section("Target (Referenced Table)") {
                    Picker("Target Table", selection: $targetTable) {
                        ForEach(tables) { t in
                            Text(t.name).tag(t.name)
                        }
                    }

                    if let tableObj = tables.first(where: { $0.name == targetTable }) {
                        Picker("Target Column", selection: $targetColumn) {
                            ForEach(tableObj.columns) { c in
                                Text(c.name).tag(c.name)
                            }
                        }
                    }
                }

                Section("Referential Cascading Rules") {
                    Picker("On Delete", selection: $onDelete) {
                        ForEach(ReferentialAction.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    Picker("On Update", selection: $onUpdate) {
                        ForEach(ReferentialAction.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Save Relationship") {
                    let rel = DatabaseRelationship(
                        type: type,
                        sourceTable: sourceTable,
                        sourceColumn: sourceColumn,
                        targetTable: targetTable,
                        targetColumn: targetColumn,
                        onDelete: onDelete,
                        onUpdate: onUpdate
                    )
                    onSave(rel)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onAppear {
            if let first = tables.first {
                sourceTable = first.name
                targetTable = first.name
                if let col = first.columns.first {
                    sourceColumn = col.name
                    targetColumn = col.name
                }
            }
        }
    }
}
