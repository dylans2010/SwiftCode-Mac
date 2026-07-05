import SwiftUI

struct FoldersView: View {
    let folder: ProjectFolder

    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var folderManager: FolderManager

    private var projects: [Project] {
        folderManager.projects(in: folder, allProjects: projectManager.projects)
    }

    var body: some View {
        List {
            if projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Add projects to this folder from the Home page."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(projects) { project in
                    Button {
                        projectManager.openProject(project)
                    } label: {
                        HStack {
                            Image(systemName: "swift")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(project.name)
                                Text("\(project.fileCount) Files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
        }
        .navigationTitle(folder.folderName)
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()
                Color(hex: folder.colorHex)
                    .opacity(0.12)
                    .ignoresSafeArea()

                // Subtle gradient overlay
                LinearGradient(
                    colors: [
                        Color(hex: folder.colorHex).opacity(0.1),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}
