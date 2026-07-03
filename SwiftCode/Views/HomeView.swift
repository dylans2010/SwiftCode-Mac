import SwiftUI

struct HomeView: View {
    @State var viewModel = HomeViewModel()
    @State private var showingImport = false
    @State private var showingNewProject = false
    @State private var selectedProject: ProjectRegistryEntry?

    var body: some View {
        NavigationStack {
            VStack {
                Text("SwiftCode")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 40)

                HomeProjectGridView(projects: viewModel.recentProjects) { project in
                    selectedProject = project
                }
                .padding()

                HStack(spacing: 20) {
                    Button("New Project...") { showingNewProject = true }
                    Button("Open Folder...") { showingImport = true }
                }
                .padding(.bottom, 40)
            }
            .frame(minWidth: 800, minHeight: 600)
            .sheet(isPresented: $showingImport) {
                ImportProjectSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheetView(viewModel: viewModel)
            }
            .navigationDestination(item: $selectedProject) { project in
                WorkspaceView(viewModel: WorkspaceViewModel(projectURL: project.rootURL))
            }
        }
        .onAppear {
            Task { await viewModel.loadProjects() }
        }
    }
}
