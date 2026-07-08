import SwiftUI

struct FoldersView: View {
    let folder: ProjectFolder

    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var folderManager: FolderManager

    private var projects: [Project] {
        folderManager.projects(in: folder, allProjects: projectManager.projects)
    }

    var body: some View {
        AdaptiveDashboardPage {
            if projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Add projects to this folder from the Home page."))
                    .listRowBackground(Color.clear)
            } else {
                AdaptiveGrid(projects, id: \.id) { project in
                    HomeProjectCardView(project: project) {
                        projectManager.openProject(project)
                    } onDelete: {
                        try? projectManager.deleteProject(project)
                    }
                }
            }
        }
        .navigationTitle(folder.folderName)
    }
}
