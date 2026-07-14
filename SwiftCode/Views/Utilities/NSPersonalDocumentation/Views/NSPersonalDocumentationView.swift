// ====================================================================
// NS PERSONAL DOCUMENTATION - MAIN ENTRY POINT (REFACTORED WORKSPACE)
// ====================================================================
// This view acts as the MAIN container view of the personal documentation feature,
// coordinating and accessing all sub-views/modules (Dashboard, Wiki,
// Knowledge Graph, Timeline, Whiteboards, Snippets, Snapshots, etc.) and
// is integrated to be accessible from WorkspaceView.
//
// Refactored to utilize a native macOS-like HSplitView for fluid multi-column resizing,
// a clean, modern collapsible sidebar, and full available workspace width.
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
                HSplitView {
                    // Column 1: Native Sidebar
                    sidebarView(coord: coord)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                        .background(Color(NSColor.windowBackgroundColor))

                    // Column 2: Optional Middle List Browser
                    if let kind = coord.selectedModuleKind, hasMiddleList(kind) {
                        middleListView(for: kind, coord: coord)
                            .frame(minWidth: 240, idealWidth: 280, maxWidth: 400)
                            .background(Color(NSColor.windowBackgroundColor))
                    }

                    // Column 3: Main Workspace Panel
                    mainWorkspaceView(for: coord.selectedModuleKind, coord: coord)
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
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

    private func hasMiddleList(_ kind: ModuleKind) -> Bool {
        switch kind {
        case .dashboard, .smartCollections, .knowledgeGraph, .timeline, .analytics, .intelligence:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func sidebarView(coord: PersonalDocumentationCoordinator) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Search / Action Row
            HStack {
                Text("Documentation")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingCommandPalette = true
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Command Palette (Quick Open)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List {
                Section(header: Text("OVERVIEW").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    sidebarRow(title: "Dashboard", icon: "square.grid.2x2.fill", color: .blue, tag: .dashboard, coord: coord)
                    sidebarRow(title: "Global Search", icon: "magnifyingglass", color: .teal, tag: .smartCollections, coord: coord)
                }

                Section(header: Text("PRODUCTIVITY ECOSYSTEM").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    sidebarRow(title: "Knowledge Graph", icon: ModuleKind.knowledgeGraph.icon, color: ModuleKind.knowledgeGraph.accentColor, tag: .knowledgeGraph, coord: coord)
                    sidebarRow(title: "Project Timeline", icon: ModuleKind.timeline.icon, color: ModuleKind.timeline.accentColor, tag: .timeline, coord: coord)
                    sidebarRow(title: "Project Analytics", icon: ModuleKind.analytics.icon, color: ModuleKind.analytics.accentColor, tag: .analytics, coord: coord)
                    sidebarRow(title: "Project Intelligence", icon: ModuleKind.intelligence.icon, color: ModuleKind.intelligence.accentColor, tag: .intelligence, coord: coord)
                    sidebarRow(title: "Advanced Whiteboards", icon: ModuleKind.whiteboards.icon, color: ModuleKind.whiteboards.accentColor, tag: .whiteboards, coord: coord)
                    sidebarRow(title: "Snippet Workspace", icon: ModuleKind.snippets.icon, color: ModuleKind.snippets.accentColor, tag: .snippets, coord: coord)
                    sidebarRow(title: "Project Snapshots", icon: ModuleKind.snapshots.icon, color: ModuleKind.snapshots.accentColor, tag: .snapshots, coord: coord)
                }

                Section(header: Text("LIBRARIES").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    DisclosureGroup("Freeform Documents") {
                        ForEach(ModuleKind.allCases.filter { $0.archetype == .freeform }) { kind in
                            sidebarRow(title: kind.rawValue, icon: kind.icon, color: kind.accentColor, tag: kind, coord: coord)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))

                    DisclosureGroup("Structured Records") {
                        ForEach(ModuleKind.allCases.filter { $0.archetype == .structured }) { kind in
                            sidebarRow(title: kind.rawValue, icon: kind.icon, color: kind.accentColor, tag: kind, coord: coord)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))

                    DisclosureGroup("Generated & Wiki") {
                        sidebarRow(title: "Project Wiki", icon: "globe.americas.fill", color: .purple, tag: .projectWiki, coord: coord)
                        ForEach(ModuleKind.allCases.filter {
                            $0.archetype == .generated &&
                            $0 != .dashboard &&
                            $0 != .knowledgeGraph &&
                            $0 != .timeline &&
                            $0 != .analytics &&
                            $0 != .intelligence &&
                            $0 != .whiteboards &&
                            $0 != .snippets &&
                            $0 != .snapshots &&
                            $0 != .projectWiki
                        }) { kind in
                            sidebarRow(title: kind.rawValue, icon: kind.icon, color: kind.accentColor, tag: kind, coord: coord)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func sidebarRow(title: String, icon: String, color: Color, tag: ModuleKind, coord: PersonalDocumentationCoordinator) -> some View {
        Button {
            coord.selectedModuleKind = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(coord.selectedModuleKind == tag ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(coord.selectedModuleKind == tag ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }

    @ViewBuilder
    private func middleListView(for kind: ModuleKind, coord: PersonalDocumentationCoordinator) -> some View {
        switch kind {
        case .projectWiki:
            WikiPageListView(coordinator: coord)
        case .whiteboards:
            WhiteboardListView(coordinator: coord)
        case .snippets:
            SnippetListView(coordinator: coord)
        case .snapshots:
            SnapshotListView(coordinator: coord)
        default:
            RecordListView(coordinator: coord, kind: kind, selectedDocumentID: $coord.selectedDocumentID)
        }
    }

    @ViewBuilder
    private func mainWorkspaceView(for kind: ModuleKind?, coord: PersonalDocumentationCoordinator) -> some View {
        if let kind = kind {
            switch kind {
            case .dashboard:
                DashboardView(coordinator: coord)
            case .projectWiki:
                WikiPageDetailView(coordinator: coord)
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
                WhiteboardCanvasDetailView(coordinator: coord)
            case .snippets:
                SnippetDetailView(coordinator: coord)
            case .snapshots:
                SnapshotDetailView(coordinator: coord)
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
}
