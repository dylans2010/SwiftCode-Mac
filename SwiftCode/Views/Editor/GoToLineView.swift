import SwiftUI

struct GoToLineView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var lineNumber = ""
    let onGoToLine: (Int) -> Void

    var totalLines: Int {
        projectManager.activeFileContent.components(separatedBy: "\n").count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    Text("Go To Line")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    if let node = projectManager.activeFileNode {
                        Text(node.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Total Lines: \(totalLines)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                TextField("Line Number", text: $lineNumber)
                    .keyboardType(.numberPad)
                    .font(.title2.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 40)

                Button {
                    if let line = Int(lineNumber), line > 0 {
                        onGoToLine(min(line, totalLines))
                        dismiss()
                    }
                } label: {
                    Text("Go")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 40)
                .disabled(Int(lineNumber) == nil || Int(lineNumber)! < 1)

                Spacer()
            }
            .padding(.top, 30)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
