import SwiftUI

public struct NSPersonalDocumentationView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var coordinator: PersonalDocumentationCoordinator? = nil
    @State private var initializationError: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let error = initializationError {
                ContentUnavailableView {
                    Label("Database Error", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                }
            } else if let coord = coordinator {
                @Bindable var coord = coord
                NavigationSplitView {
                    List(selection: $coord.selectedModuleKind) {
                        Section("Dashboard") {
                            NavigationLink(value: ModuleKind.dashboard) {
                                Label("Dashboard", systemImage: "square.grid.2x2.fill")
                            }
                        }

                        Section("Search") {
                            NavigationLink(value: ModuleKind.smartCollections) {
                                Label("Global Search", systemImage: "magnifyingglass")
                            }
                        }

                        Section("Freeform Documents") {
                            ForEach(ModuleKind.allCases.filter { $0.archetype == .freeform }) { kind in
                                NavigationLink(value: kind) {
                                    Label(kind.rawValue, systemImage: kind.icon)
                                        .foregroundStyle(kind.accentColor)
                                }
                            }
                        }

                        Section("Structured Records") {
                            ForEach(ModuleKind.allCases.filter { $0.archetype == .structured }) { kind in
                                NavigationLink(value: kind) {
                                    Label(kind.rawValue, systemImage: kind.icon)
                                        .foregroundStyle(kind.accentColor)
                                }
                            }
                        }

                        Section("Generated & Wiki") {
                            ForEach(ModuleKind.allCases.filter { $0.archetype == .generated && $0 != .dashboard }) { kind in
                                NavigationLink(value: kind) {
                                    Label(kind.rawValue, systemImage: kind.icon)
                                        .foregroundStyle(kind.accentColor)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 220, idealWidth: 240)
                    .navigationTitle("Documentation")
                } content: {
                    if let kind = coord.selectedModuleKind {
                        switch kind {
                        case .dashboard:
                            Text("Summary & Insights")
                                .font(.headline)
                                .padding()
                        case .projectWiki:
                            Text("Wiki Navigation")
                                .font(.headline)
                                .padding()
                        case .smartCollections:
                            Text("Search View")
                                .font(.headline)
                                .padding()
                        default:
                            RecordListView(coordinator: coord, kind: kind, selectedDocumentID: $coord.selectedDocumentID)
                                .frame(minWidth: 250, idealWidth: 280)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("No Module Selected", systemImage: "sidebar.left")
                        } description: {
                            Text("Select a module to view its documents.")
                        }
                    }
                } detail: {
                    if let kind = coord.selectedModuleKind {
                        switch kind {
                        case .dashboard:
                            DashboardView(coordinator: coord)
                        case .projectWiki:
                            WikiPageView(coordinator: coord)
                        case .smartCollections:
                            GlobalSearchView(coordinator: coord)
                        default:
                            RecordDetailView(coordinator: coord, documentID: coord.selectedDocumentID)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Select an Item", systemImage: "doc.text")
                        } description: {
                            Text("Choose a category and document to get started.")
                        }
                    }
                }
            } else {
                ProgressView("Attaching project session database...")
                    .padding()
            }
        }
        .onAppear {
            attachCoordinator()
        }
        .onChange(of: sessionStore.activeProject) { _, _ in
            attachCoordinator()
        }
    }

    private func attachCoordinator() {
        guard let project = sessionStore.activeProject else {
            self.coordinator = nil
            self.initializationError = "No active project session found."
            return
        }

        do {
            self.coordinator = try PersonalDocumentationCoordinator(projectID: project.id, projectURL: project.directoryURL)
            self.initializationError = nil
        } catch {
            self.coordinator = nil
            self.initializationError = "Failed to initialize SwiftData project store: \(error.localizedDescription)"
        }
    }
}
