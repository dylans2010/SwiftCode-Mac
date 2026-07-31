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
            }
            .padding()
            .background(Color.secondary.opacity(0.08))

            Form {
                ForEach(table.columns) { col in
                    HStack {
                        Text(col.name)
                            .frame(width: 120, alignment: .leading)
                        TextField("Value", text: Binding(
                            get: { rowData[col.name] ?? "" },
                            set: { rowData[col.name] = $0 }
                        ))
                        .disabled(col.isPrimaryKey && col.isAutoIncrement)
                    }
                }
            }
            .formStyle(.grouped)

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
    }
}
