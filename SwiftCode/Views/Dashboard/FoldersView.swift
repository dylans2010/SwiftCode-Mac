import SwiftUI

struct FoldersView: View {
    let folder: ProjectFolder

    @Environment(ProjectSessionStore.self) private var sessionStore
    @EnvironmentObject private var folderManager: FolderManager

    private var projects: [Project] {
        folderManager.projects(in: folder, allProjects: sessionStore.projects)
    }

    var body: some View {
        AdaptiveDashboardPage {
            if projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Add projects to this folder from the Home page."))
                    .listRowBackground(Color.clear)
            } else {
                AdaptiveGrid(projects, id: \.id) { project in
                    HomeProjectCardView(project: project) {
                        Task { @MainActor in
                            try? await sessionStore.openProject(project)
                        }
                    } onDelete: {
                        try? sessionStore.deleteProject(project)
                    }
                }
            }
        }
        .navigationTitle(folder.folderName)
    }
}
