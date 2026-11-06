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
            GroupBox {
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
            } label: {
                Label("Documents Overview", systemImage: "doc.text")
                    .foregroundStyle(.blue)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

        case "tasks":
            GroupBox {
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
            } label: {
                Label("Task Tracking", systemImage: "checklist")
                    .foregroundStyle(.green)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

        case "analyticsChart":
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 10) {
                        bar(day: "M", h: 30)
                        bar(day: "T", h: 50)
                        bar(day: "W", h: 80)
                        bar(day: "T", h: 40)
                        bar(day: "F", h: 90)
                    }
                    .frame(height: 100)
                }
            } label: {
                Label("Documentation Weekly Pace", systemImage: "chart.bar.fill")
                    .foregroundStyle(.orange)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

        case "recentDocs":
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if let docs = snapshot?.recentDocuments, !docs.isEmpty {
                        ForEach(docs) { doc in
                            HStack {
                                Image(systemName: doc.moduleKind.icon)
                                    .foregroundStyle(doc.moduleKind.accentColor)
                                Text(doc.title)
                                    .font(.body.bold())
                                    .lineLimit(1)
                                    .truncationMode(.tail)
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
            } label: {
                Label("Recent Activity", systemImage: "clock.fill")
                    .foregroundStyle(.purple)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

        case "recentWhiteboards":
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
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
            } label: {
                Label("Advanced Whiteboard", systemImage: "pencil.and.outline")
                    .foregroundStyle(.purple)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

        case "recentSnippets":
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
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
            } label: {
                Label("Code Snippets", systemImage: "text.badge.plus")
                    .foregroundStyle(.green)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

        case "aiAssistant":
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
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
            } label: {
                Label("AI Intelligence Assistant", systemImage: "sparkles")
                    .foregroundStyle(.indigo)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

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
