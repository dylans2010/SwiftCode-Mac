import SwiftUI

struct SCTimelineView: View {
    @State private var tm = WorkspaceTimelineManager.shared
    @State private var selectedCategory: String = "All"
    @State private var searchQuery: String = ""
    @State private var showExportDialog: Bool = false
    @State private var exportedJSON: String = ""

    private let categories = [
        "All", "Build Completed", "Build Failed", "Archive Created",
        "Backup Created", "VM Started", "VM Stopped",
        "Project Opened", "Project Created", "Dependency Updated",
        "Diagnostics Completed"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Engineering Activity Timeline")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Chronological audit log tracking compilations, archives, hypervisors, and workspace events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    exportedJSON = tm.exportTimelineJSON()
                    showExportDialog = true
                } label: {
                    Label("Export Logs", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    tm.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            Divider()

            // Filter and Search Toolbar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search timeline events...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchQuery) { _, newValue in
                        tm.searchQuery = newValue
                    }

                Picker("Filter Category:", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .frame(width: 220)
                .onChange(of: selectedCategory) { _, newValue in
                    tm.filterCategory = newValue
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Events List
            if tm.filteredEvents.isEmpty {
                ContentUnavailableView {
                    Label("No Events Found", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Try adjusting your search query or selected category filter.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tm.filteredEvents) { item in
                            HStack(alignment: .top, spacing: 16) {
                                // Timeline indicator segment
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(colorForCategory(item.category))
                                        .frame(width: 10, height: 10)

                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                                .frame(width: 12)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.title)
                                            .font(.headline)
                                        Spacer()
                                        Text(formatDate(item.date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text(item.category.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(colorForCategory(item.category))
                                        .padding(.top, 2)
                                }
                                .padding(.bottom, 24)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .onAppear {
            tm.refresh()
        }
        .sheet(isPresented: $showExportDialog) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Timeline JSON")
                    .font(.headline)
                Text("Copied timeline state is formatted in standard JSON log metrics for export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: .constant(exportedJSON))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 300)
                    .border(Color.secondary.opacity(0.3))

                HStack {
                    Button("Copy to Clipboard") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(exportedJSON, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Close") {
                        showExportDialog = false
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(width: 500, height: 450)
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        let cat = category.lowercased()
        if cat.contains("completed") || cat.contains("success") { return .green }
        if cat.contains("failed") || cat.contains("error") { return .red }
        if cat.contains("archive") { return .blue }
        if cat.contains("backup") { return .purple }
        if cat.contains("vm") { return .cyan }
        if cat.contains("project") { return .orange }
        if cat.contains("dependency") { return .yellow }
        return .secondary
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .medium
        return fmt.string(from: date)
    }
}
