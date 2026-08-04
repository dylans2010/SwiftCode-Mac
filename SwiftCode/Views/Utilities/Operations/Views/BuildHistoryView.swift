import SwiftUI

struct BuildHistoryView: View {
    @State private var bhm = BuildHistoryManager.shared
    @State private var filterQuery = ""
    @State private var selectedRecord: SCBuildRecord? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build History")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Logs, warnings, and performance reports of prior compiles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        bhm.clearHistory()
                        selectedRecord = nil
                    } label: {
                        Text("Clear History")
                    }
                    .buttonStyle(.bordered)
                    .disabled(bhm.buildRecords.isEmpty)
                }
                .padding(16)

                Divider()

                // Filter Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by project, SDK, configuration or status...", text: $filterQuery)
                        .textFieldStyle(.plain)
                    if !filterQuery.isEmpty {
                        Button {
                            filterQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                let filteredRecords = bhm.buildRecords.filter { record in
                    filterQuery.isEmpty ||
                    record.projectName.lowercased().contains(filterQuery.lowercased()) ||
                    record.sdk.lowercased().contains(filterQuery.lowercased()) ||
                    record.status.lowercased().contains(filterQuery.lowercased())
                }

                if filteredRecords.isEmpty {
                    ContentUnavailableView {
                        Label("No Build Records Found", systemImage: "clock")
                    } description: {
                        Text("Trigger a project build inside the editor toolbar to log active compile history.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredRecords, selection: $selectedRecord) { record in
                        HStack(spacing: 12) {
                            Image(systemName: record.status == "Succeeded" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(record.status == "Succeeded" ? .green : .red)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.projectName)
                                    .font(.headline)
                                Text("\(record.configuration) • \(record.sdk) • \(formatDate(record.date))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1fs", record.duration))
                                    .font(.system(size: 13, weight: .bold))
                                HStack(spacing: 6) {
                                    if record.errors > 0 {
                                        Label("\(record.errors)", systemImage: "xmark.octagon.fill")
                                            .foregroundStyle(.red)
                                    }
                                    if record.warnings > 0 {
                                        Label("\(record.warnings)", systemImage: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(record)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let selected = selectedRecord {
                Divider()
                BuildRecordDetailPanel(record: selected)
                    .frame(width: 320)
                    .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

struct BuildRecordDetailPanel: View {
    let record: SCBuildRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: record.status == "Succeeded" ? "checkmark.circle" : "xmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(record.status == "Succeeded" ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.projectName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Build Report")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    SCDetailRow(label: "Status", value: record.status)
                    SCDetailRow(label: "Duration", value: String(format: "%.2fs", record.duration))
                    SCDetailRow(label: "SDK", value: record.sdk)
                    SCDetailRow(label: "Destination", value: record.destination)
                    SCDetailRow(label: "Compiler", value: record.compiler)
                    SCDetailRow(label: "Errors Detected", value: "\(record.errors)")
                    SCDetailRow(label: "Warnings Flagged", value: "\(record.warnings)")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Build Commands Log")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text("swiftc -target \(record.sdk) -O -Xfrontend -warn-concurrency -sdk macosx \(record.projectName).swift")
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                    .frame(height: 120)
                }
            }
            .padding(16)
        }
    }
}
