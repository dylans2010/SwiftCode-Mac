import SwiftUI

// MARK: - Code Stats Extension View
struct CodeStatsExtensionView: View {
    var body: some View {
        Form {
            Section("Current File") {
                statRow("Lines of Code", value: "—", icon: "number")
                statRow("Characters", value: "—", icon: "textformat.size")
                statRow("Functions", value: "—", icon: "function")
                statRow("Complexity", value: "—", icon: "chart.bar")
            }
            Section("Project") {
                statRow("Total Files", value: "—", icon: "doc.on.doc")
                statRow("Total Lines", value: "—", icon: "list.number")
                statRow("Languages", value: "Swift", icon: "chevron.left.forwardslash.chevron.right")
            }
            Section {
                Text("Displays line counts, cyclomatic complexity metrics, and language breakdown for your project. Stats update automatically when you open or edit files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Code Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
