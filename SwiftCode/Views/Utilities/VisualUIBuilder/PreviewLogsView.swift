import SwiftUI
import AppKit

public struct PreviewLogsView: View {
    @State private var diagnostics = PreviewDiagnostics.shared
    @State private var searchQuery = ""
    @State private var selectedCategoryFilter: LogCategoryFilter = .all
    @State private var selectedLogIDs = Set<UUID>()

    public init() {}

    private enum LogCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case engine = "Engine"
        case compiler = "Compiler"
        case swiftpm = "SwiftPM"
        case renderer = "Renderer"
        case diagnostics = "Diagnostics"

        var id: String { rawValue }
    }

    private var filteredLogs: [PreviewDiagnosticsRecord] {
        var result = diagnostics.logs

        // Category Filter
        switch selectedCategoryFilter {
        case .all:
            break
        case .engine:
            result = result.filter { ["state", "engine", "discovery"].contains($0.category.lowercased()) }
        case .compiler:
            result = result.filter { ["compile", "compiler"].contains($0.category.lowercased()) }
        case .swiftpm:
            result = result.filter { $0.category.lowercased() == "swiftpm" }
        case .renderer:
            result = result.filter { ["render", "renderer"].contains($0.category.lowercased()) }
        case .diagnostics:
            result = result.filter { ["diagnostics", "error", "cache", "llm"].contains($0.category.lowercased()) }
        }

        // Search Filter
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { $0.message.lowercased().contains(q) || $0.category.lowercased().contains(q) }
        }

        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header/Controls
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search logs...", text: $searchQuery)
                            .textFieldStyle(.plain)
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    Button(action: copyAll) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: copySelected) {
                        Label("Copy Selected", systemImage: "doc.on.clipboards")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedLogIDs.isEmpty)

                    Button(action: {
                        diagnostics.clearLogs()
                        selectedLogIDs.removeAll()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear Logs")
                }

                // Log category tabs
                Picker("Filter", selection: $selectedCategoryFilter) {
                    ForEach(LogCategoryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No Logs Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredLogs) { log in
                                let isSelected = selectedLogIDs.contains(log.id)
                                HStack(alignment: .top, spacing: 8) {
                                    // Timestamp
                                    Text(formattedTime(log.timestamp))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    // Category Tag
                                    Text("[\(log.category.uppercased())]")
                                        .font(.system(.caption, design: .monospaced))
                                        .bold()
                                        .foregroundColor(categoryColor(log.category))
                                        .frame(width: 80, alignment: .leading)

                                    // Message
                                    Text(log.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedLogIDs.contains(log.id) {
                                        selectedLogIDs.remove(log.id)
                                    } else {
                                        selectedLogIDs.insert(log.id)
                                    }
                                }
                                .id(log.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .onChange(of: filteredLogs.count) { _, _ in
                        if let lastLog = filteredLogs.last {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280, minHeight: 400)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "error":
            return .red
        case "compile", "compiler":
            return .orange
        case "render", "renderer":
            return .blue
        case "cache":
            return .green
        case "state", "engine":
            return .purple
        case "llm":
            return .indigo
        default:
            return .secondary
        }
    }

    private func copyAll() {
        let text = filteredLogs.map { "[\(formattedTime($0.timestamp))] [\($0.category.uppercased())] \($0.message)" }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copySelected() {
        let text = filteredLogs.filter { selectedLogIDs.contains($0.id) }
            .map { "[\(formattedTime($0.timestamp))] [\($0.category.uppercased())] \($0.message)" }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
