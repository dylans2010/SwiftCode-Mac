import SwiftUI

struct DatabaseInspectorView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var folderManager: FolderManager
    @State private var selectedTable = "Projects"
    let tables = ["Projects", "Folders", "Settings"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Table", selection: $selectedTable) {
                ForEach(tables, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                headerRow
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                switch selectedTable {
                case "Projects":
                    ForEach(projectManager.projects) { project in
                        HStack {
                            Text(project.id.uuidString.prefix(8)).font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(project.name).font(.subheadline)
                            Spacer()
                            Text(project.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                case "Folders":
                    ForEach(folderManager.folders) { folder in
                        HStack {
                            Text(folder.folderId.uuidString.prefix(8)).font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(folder.folderName).font(.subheadline)
                            Spacer()
                            Text("\(folder.projectIdentifiers.count) items").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                default:
                    Text("System Settings Table (Internal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Database Inspector")
    }

    private var headerRow: some View {
        HStack {
            Text("UUID")
            Spacer()
            Text("Name/Key")
            Spacer()
            Text("Metadata")
        }
    }
}
