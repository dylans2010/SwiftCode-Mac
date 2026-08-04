import SwiftUI

struct SCTimelineView: View {
    @State private var tm = TimelineManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity Timeline")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Chronological audit log of compilations, archives, backups, and hypervisor sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    tm.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tm.activityItems) { item in
                        HStack(alignment: .top, spacing: 16) {
                            // Timeline bar segment
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
        .onAppear {
            tm.refresh()
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Build": return .green
        case "Archive": return .blue
        case "Backup": return .purple
        case "Diagnostics": return .orange
        case "Release": return .red
        default: return .secondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
