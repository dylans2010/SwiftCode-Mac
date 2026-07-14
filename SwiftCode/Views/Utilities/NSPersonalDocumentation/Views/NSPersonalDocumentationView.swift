// ====================================================================
// NS PERSONAL DOCUMENTATION - MAIN ENTRY POINT
// ====================================================================
// This view acts as the MAIN container view of the personal documentation feature,
// coordinating and accessing all sub-views/modules (Dashboard, Wiki,
// Knowledge Graph, Timeline, Whiteboards, Snippets, Snapshots, etc.) and
// is integrated to be accessible from WorkspaceView.
// ====================================================================

import SwiftUI

public struct NSPersonalDocumentationView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var coordinator: PersonalDocumentationCoordinator? = nil
    @State private var initializationError: String? = nil
    @State private var showingCommandPalette = false

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

                        Section("Search & Command") {
                            NavigationLink(value: ModuleKind.smartCollections) {
                                Label("Global Search", systemImage: "magnifyingglass")
                            }

                            Button {
                                showingCommandPalette = true
                            } label: {
                                Label("Quick Open Palette", systemImage: "terminal")
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }

                        Section("Ecosystem & Productivity Tools") {
                            NavigationLink(value: ModuleKind.knowledgeGraph) {
                                Label("Knowledge Graph", systemImage: ModuleKind.knowledgeGraph.icon)
                                    .foregroundStyle(ModuleKind.knowledgeGraph.accentColor)
                            }
                            NavigationLink(value: ModuleKind.timeline) {
                                Label("Project Timeline", systemImage: ModuleKind.timeline.icon)
                                    .foregroundStyle(ModuleKind.timeline.accentColor)
                            }
                            NavigationLink(value: ModuleKind.analytics) {
                                Label("Project Analytics", systemImage: ModuleKind.analytics.icon)
                                    .foregroundStyle(ModuleKind.analytics.accentColor)
                            }
                            NavigationLink(value: ModuleKind.intelligence) {
                                Label("Project Intelligence", systemImage: ModuleKind.intelligence.icon)
                                    .foregroundStyle(ModuleKind.intelligence.accentColor)
                            }
                            NavigationLink(value: ModuleKind.whiteboards) {
                                Label("Advanced Whiteboards", systemImage: ModuleKind.whiteboards.icon)
                                    .foregroundStyle(ModuleKind.whiteboards.accentColor)
                            }
                            NavigationLink(value: ModuleKind.snippets) {
                                Label("Snippet Workspace", systemImage: ModuleKind.snippets.icon)
                                    .foregroundStyle(ModuleKind.snippets.accentColor)
                            }
                            NavigationLink(value: ModuleKind.snapshots) {
                                Label("Project Snapshots", systemImage: ModuleKind.snapshots.icon)
                                    .foregroundStyle(ModuleKind.snapshots.accentColor)
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
                            ForEach(ModuleKind.allCases.filter {
                                $0.archetype == .generated &&
                                $0 != .dashboard &&
                                $0 != .knowledgeGraph &&
                                $0 != .timeline &&
                                $0 != .analytics &&
                                $0 != .intelligence &&
                                $0 != .whiteboards &&
                                $0 != .snippets &&
                                $0 != .snapshots
                            }) { kind in
                                NavigationLink(value: kind) {
                                    Label(kind.rawValue, systemImage: kind.icon)
                                        .foregroundStyle(kind.accentColor)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 230, idealWidth: 250)
                    .navigationTitle("Personal Documentation")
                } content: {
                    if let kind = coord.selectedModuleKind {
                        switch kind {
                        case .dashboard, .projectWiki, .smartCollections, .knowledgeGraph, .timeline, .analytics, .intelligence, .whiteboards, .snippets, .snapshots:
                            Text(kind.rawValue)
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
                        case .knowledgeGraph:
                            KnowledgeGraphView(coordinator: coord)
                        case .timeline:
                            ProjectTimelineView(coordinator: coord)
                        case .analytics:
                            AnalyticsView(coordinator: coord)
                        case .intelligence:
                            IntelligenceView(coordinator: coord)
                        case .whiteboards:
                            WhiteboardsListView(coordinator: coord)
                        case .snippets:
                            SnippetWorkspaceView(coordinator: coord)
                        case .snapshots:
                            SnapshotsView(coordinator: coord)
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
                .sheet(isPresented: $showingCommandPalette) {
                    PersonalDocCommandPalette(coordinator: coord) {
                        showingCommandPalette = false
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
