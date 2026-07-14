import SwiftUI

struct DashboardView: View {
    let coordinator: PersonalDocumentationCoordinator
    @State private var snapshot: DashboardManager.DashboardSnapshot? = nil
    @State private var isLoading = false

    // Dashboard customization & Widget arrangement states
    @State private var activeWidgets: [String] = ["totalDocs", "tasks", "analyticsChart", "recentDocs", "recentWhiteboards", "recentSnippets", "aiAssistant"]
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with Customization Button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Documentation Ecosystem Dashboard")
                            .font(.title2.bold())
                        Text("Modular workspace combining planning boards, whiteboards, code snippet libraries, and AI context.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Label("Customize Dashboard", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                }

                if showSettings {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Toggle Visible Dashboard Widgets")
                            .font(.headline)
                        HStack(spacing: 12) {
                            widgetToggle(title: "Overview Cards", key: "totalDocs")
                            widgetToggle(title: "Task Progress", key: "tasks")
                            widgetToggle(title: "Analytics Chart", key: "analyticsChart")
                            widgetToggle(title: "Recent Documents", key: "recentDocs")
                            widgetToggle(title: "Whiteboard Sketch", key: "recentWhiteboards")
                            widgetToggle(title: "Code snippets", key: "recentSnippets")
                            widgetToggle(title: "AI Project Assistant", key: "aiAssistant")
                        }
                        .padding()
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                    .transition(.slide)
                }

                if isLoading {
                    ProgressView()
                        .padding()
                } else {
                    // Customizable Widget Layout Flow - Desktop Adaptive Grid
                    let columns = [GridItem(.adaptive(minimum: 280, maximum: 500), spacing: 20)]
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(activeWidgets, id: \.self) { widgetKey in
                            widgetView(for: widgetKey)
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            loadDashboard()
        }
    }

    @ViewBuilder
    private func widgetView(for key: String) -> some View {
        switch key {
        case "totalDocs":
            HStack(spacing: 16) {
                Image(systemName: "doc.text.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Documents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(snapshot?.totalDocuments ?? 0) Active Notes")
                        .font(.title2.bold())
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        case "tasks":
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks Progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(snapshot?.completedTasks ?? 0) / \(snapshot?.totalTasks ?? 0) Work Items")
                        .font(.title2.bold())
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        case "analyticsChart":
            VStack(alignment: .leading, spacing: 8) {
                Text("Documentation Weekly Pace")
                    .font(.headline)
                HStack(alignment: .bottom, spacing: 10) {
                    bar(day: "M", h: 30)
                    bar(day: "T", h: 50)
                    bar(day: "W", h: 80)
                    bar(day: "T", h: 40)
                    bar(day: "F", h: 90)
                }
                .frame(height: 100)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        case "recentDocs":
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Activity")
                    .font(.headline)

                if let docs = snapshot?.recentDocuments, !docs.isEmpty {
                    ForEach(docs) { doc in
                        HStack {
                            Image(systemName: doc.moduleKind.icon)
                                .foregroundStyle(doc.moduleKind.accentColor)
                            Text(doc.title)
                                .font(.body.bold())
                                .lineLimit(1)
                            Spacer()
                            Text("Updated \(doc.updatedAt, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No documents yet.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        case "recentWhiteboards":
            VStack(alignment: .leading, spacing: 12) {
                Text("Advanced Whiteboard Canvas")
                    .font(.headline)
                HStack {
                    Image(systemName: "pencil.and.outline")
                        .font(.largeTitle)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading) {
                        Text("Infinite Brainstorming Canvas")
                            .font(.caption.bold())
                        Text("Visual workflow schemas, UML diagrams, & mind maps.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    coordinator.navigate(to: .whiteboards)
                } label: {
                    Text("Open Canvas")
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        case "recentSnippets":
            VStack(alignment: .leading, spacing: 12) {
                Text("Code Snippet Workspace")
                    .font(.headline)
                HStack {
                    Image(systemName: "text.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Centralized Snippet Repository")
                            .font(.caption.bold())
                        Text("Search code snippets, detect languages, run AI explainers.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    coordinator.navigate(to: .snippets)
                } label: {
                    Text("Open Repository")
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        case "aiAssistant":
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Project Intelligence Assistant")
                    .font(.headline)
                Text("Direct link to codebase analysis, knowledge graphs, and memory Q&A.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    coordinator.navigate(to: .intelligence)
                } label: {
                    Text("Open AI Agent Panel")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

        default:
            EmptyView()
        }
    }

    private func widgetToggle(title: String, key: String) -> some View {
        Button {
            if activeWidgets.contains(key) {
                activeWidgets.removeAll { $0 == key }
            } else {
                activeWidgets.append(key)
            }
        } label: {
            HStack {
                Text(title)
                if activeWidgets.contains(key) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func bar(day: String, h: CGFloat) -> some View {
        VStack {
            Spacer()
            Rectangle()
                .fill(Color.blue)
                .frame(width: 16, height: h)
            Text(day)
                .font(.caption2)
        }
    }

    private func loadDashboard() {
        isLoading = true
        Task {
            snapshot = try? await coordinator.dashboard.getSnapshot()
            isLoading = false
        }
    }
}
