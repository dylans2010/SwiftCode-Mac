import SwiftUI
import SwiftCodeCloud

/// Edits one row's values; the caller persists them.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabaseRecordEditor.swift`.
///
/// The only change over Legacy is the removal of the `liquidGlass`
/// header (SwiftCodeUI has no such modifier); the header is a plain
/// row on a subtle background. The form itself is unchanged: one
/// field per column, auto-increment primary keys disabled, and
/// `onSave` hands the edited `[String: String]` back to the caller
/// — `DatabaseRecordViewer` runs the real `UPDATE` for it. The
/// editor itself executes nothing.
@MainActor
struct DatabaseRecordEditor: View {
    @Environment(\.dismiss) private var dismiss
    let table: DatabaseTable
    @State var rowData: [String: String]
    var onSave: ([String: String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Row Records")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Form {
                ForEach(table.columns) { col in
                    LabeledContent(col.name) {
                        TextField("", text: Binding(
                            get: { rowData[col.name] ?? "" },
                            set: { rowData[col.name] = $0 }
                        ))
                        .disabled(col.isPrimaryKey && col.isAutoIncrement)
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding()
            .formStyle(.automatic)

            Divider()

            HStack {
                Spacer()
                Button("Save Record") {
                    onSave(rowData)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400)
    }
}
