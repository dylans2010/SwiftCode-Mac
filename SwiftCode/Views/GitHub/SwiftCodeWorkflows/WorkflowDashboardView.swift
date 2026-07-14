import SwiftUI
import AppKit

@MainActor
public struct WorkflowDashboardView: View {
    let project: Project
    let gitViewModel: GitViewModel

    @State private var manager = WorkflowManager.shared
    @State private var selectedWorkflow: DeveloperWorkflow?
    @State private var showingCreateSheet = false
    @State private var showingExecutionSheet = false

    // Creation Form State
    @State private var newFlowName = ""
    @State private var newFlowDesc = ""
    @State private var newFlowCategory = "General"
    @State private var newFlowIcon = "hammer.fill"

    // Search & Filter State
    @State private var searchText = ""
    @State private var selectedCategoryFilter = "All"

    public init(project: Project, gitViewModel: GitViewModel) {
        self.project = project
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        HSplitView {
            // Left Panel: Workflows Library
            VStack(spacing: 0) {
                libraryHeader
                Divider()
                libraryList
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            .background(Color(NSColor.windowBackgroundColor))

            // Right Panel: Details and Analytics Workspace or active Editor
            VStack(spacing: 0) {
                if let selected = selectedWorkflow {
                    WorkflowBuilderView(
                        workflow: Binding(
                            get: { selected },
                            set: { newValue in
                                selectedWorkflow = newValue
                                if let idx = manager.workflows.firstIndex(where: { $0.id == newValue.id }) {
                                    manager.workflows[idx] = newValue
                                }
                                manager.saveWorkflows()
                            }
                        ),
                        project: project,
                        gitViewModel: gitViewModel,
                        onRunTriggered: { flow in
                            selectedWorkflow = flow
                            showingExecutionSheet = true
                        }
                    )
                } else {
                    noSelectionPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingCreateSheet) {
            creationSheetView
        }
        .sheet(isPresented: $showingExecutionSheet) {
            if let flow = selectedWorkflow {
                WorkflowExecutionView(
                    workflow: flow,
                    project: project,
                    gitViewModel: gitViewModel,
                    onDismiss: {
                        showingExecutionSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    private var libraryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Workflow Library")
                    .font(.headline)
                Spacer()
                Button {
                    newFlowName = ""
                    newFlowDesc = ""
                    newFlowCategory = "General"
                    newFlowIcon = "hammer.fill"
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .help("Create a new workflow")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search workflows...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    private var libraryList: some View {
        List {
            // Favorites Section
            let favs = manager.workflows.filter {
                $0.isFavorite &&
                (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
            }
            if !favs.isEmpty {
                Section(header: Text("FAVORITES").font(.caption).bold().foregroundStyle(.secondary)) {
                    ForEach(favs) { flow in
                        libraryRow(for: flow)
                    }
                }
            }

            // Categories list
            let categories = Array(Set(manager.workflows.map { $0.category })).sorted()
            ForEach(categories, id: \.self) { category in
                let categoryFlows = manager.workflows.filter {
                    $0.category == category &&
                    (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
                }
                if !categoryFlows.isEmpty {
                    Section(header: Text(category.uppercased()).font(.caption).bold().foregroundStyle(.secondary)) {
                        ForEach(categoryFlows) { flow in
                            libraryRow(for: flow)
                        }
                    }
                }
            }

            // Built-in Templates section
            Section(header: Text("BUILT-IN TEMPLATES").font(.caption).bold().foregroundStyle(.secondary)) {
                ForEach(WorkflowTemplates.templates) { template in
                    HStack {
                        Image(systemName: template.icon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .bold()
                            Text("Click + to instantiate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            var flow = template
                            flow.id = UUID()
                            manager.workflows.append(flow)
                            manager.saveWorkflows()
                        } label: {
                            Image(systemName: "plus.square.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func libraryRow(for flow: DeveloperWorkflow) -> some View {
        HStack {
            Image(systemName: flow.icon)
                .font(.body)
                .foregroundStyle(selectedWorkflow?.id == flow.id ? Color.accentColor : .primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(flow.name)
                    .font(.body)
                    .lineLimit(1)
                Text(flow.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                manager.toggleFavorite(flow)
            } label: {
                Image(systemName: flow.isFavorite ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(flow.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedWorkflow = flow
        }
        .contextMenu {
            Button("Run Pipeline Now") {
                selectedWorkflow = flow
                showingExecutionSheet = true
            }
            Button("Duplicate Workflow") {
                manager.duplicateWorkflow(flow)
            }
            Divider()
            Button("Delete Workflow", role: .destructive) {
                if selectedWorkflow?.id == flow.id {
                    selectedWorkflow = nil
                }
                manager.deleteWorkflow(flow)
            }
        }
    }

    private var noSelectionPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ContentUnavailableView(
                    "No Pipeline Selected",
                    systemImage: "checklist",
                    description: Text("Select an automation pipeline from your library, or instantiate a template to get started.")
                )
                .frame(height: 250)

                Divider()

                // Analytics View Section
                Text("Automation History & Analytics")
                    .font(.title2).bold()
                    .padding(.horizontal)

                HStack(spacing: 20) {
                    MetricCard(title: "Total Executions", value: "\(manager.history.count)", subtitle: "All-time local runs", color: .blue)
                    let successCount = manager.history.filter { $0.success }.count
                    let rate = manager.history.isEmpty ? 0 : Int(Double(successCount) / Double(manager.history.count) * 100)
                    MetricCard(title: "Success Rate", value: "\(rate)%", subtitle: "Build validation passes", color: .green)
                    let totalTime = manager.history.reduce(0.0) { $0 + $1.duration }
                    MetricCard(title: "Total Run Time", value: String(format: "%.1f min", totalTime / 60), subtitle: "Automated test time saved", color: .purple)
                }
                .padding(.horizontal)

                // Recent history list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Execution Timeline")
                        .font(.headline)

                    if manager.history.isEmpty {
                        Text("No pipeline runs logged yet.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(manager.history.prefix(5)) { entry in
                            HStack {
                                Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(entry.success ? .green : .red)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.workflowName)
                                        .bold()
                                    Text("Duration: \(String(format: "%.1f", entry.duration))s • \(entry.timestamp.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Divider()
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: - Sheets

    private var creationSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Developer Workflow")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showingCreateSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            Form {
                TextField("Name", text: $newFlowName)
                    .textFieldStyle(.roundedBorder)

                TextField("Description", text: $newFlowDesc)
                    .textFieldStyle(.roundedBorder)

                Picker("Category", selection: $newFlowCategory) {
                    Text("Startup").tag("Startup")
                    Text("Quality").tag("Quality")
                    Text("Release").tag("Release")
                    Text("Maintenance").tag("Maintenance")
                    Text("General").tag("General")
                }

                Picker("Icon Symbol", selection: $newFlowIcon) {
                    Label("Hammer", systemImage: "hammer.fill").tag("hammer.fill")
                    Label("Sun", systemImage: "sun.max.fill").tag("sun.max.fill")
                    Label("Checkmark Shield", systemImage: "checkmark.shield.fill").tag("checkmark.shield.fill")
                    Label("Shipping Box", systemImage: "shippingbox.fill").tag("shippingbox.fill")
                    Label("Arrow Cycle", systemImage: "arrow.triangle.2.circlepath.circle.fill").tag("arrow.triangle.2.circlepath.circle.fill")
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Create") {
                    manager.createWorkflow(
                        name: newFlowName,
                        description: newFlowDesc,
                        icon: newFlowIcon,
                        category: newFlowCategory
                    )
                    showingCreateSheet = false
                }
                .disabled(newFlowName.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 320)
    }
}
