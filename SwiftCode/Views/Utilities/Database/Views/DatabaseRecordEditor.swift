import SwiftUI

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
            .background(Color(NSColor.controlBackgroundColor))

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
