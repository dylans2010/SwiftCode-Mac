import SwiftUI

struct HomeView: View {
    @State var viewModel = HomeViewModel()
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var selectedProject: ProjectRegistryEntry?

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .padding()
                }

                Text("SwiftCode")
                    .font(.system(size: 48, weight: .bold))
                    .padding(.top, 20)

                Text("The Next Generation IDE for Swift")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 40)

                if viewModel.recentProjects.isEmpty {
                    ContentUnavailableView("No Recent Projects", systemImage: "folder", description: Text("Create a new project or import an existing one to get started."))
                        .frame(maxHeight: 300)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                            ForEach(viewModel.recentProjects) { project in
                                ProjectCardView(project: project) {
                                    selectedProject = project
                                } onDelete: {
                                    deleteProject(project)
                                }
                            }
                        }
                        .padding()
                    }
                }

                Spacer()

                HStack(spacing: 20) {
                    Button(action: { showingNewProject = true }) {
                        VStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.largeTitle)
                            Text("New Project")
                        }
                        .frame(width: 150, height: 100)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Button(action: { showingNewProject = true }) { // Now handles both in the same sheet
                        VStack {
                            Image(systemName: "folder.fill")
                                .font(.largeTitle)
                            Text("Open Existing")
                        }
                        .frame(width: 150, height: 100)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 60)
            }
            .frame(minWidth: 800, minHeight: 600)
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .frame(width: 600, height: 500)
            }
            .navigationDestination(item: $selectedProject) { project in
                WorkspaceView(viewModel: WorkspaceViewModel(projectURL: project.rootURL))
            }
        }
        .onAppear {
            Task { await viewModel.loadProjects() }
        }
    }

    private func deleteProject(_ project: ProjectRegistryEntry) {
        Task {
            await viewModel.removeProject(project)
        }
    }
}

struct ProjectCardView: View {
    let project: ProjectRegistryEntry
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            Text(project.name)
                .font(.headline)
                .lineLimit(1)

            Text(project.rootURL.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
