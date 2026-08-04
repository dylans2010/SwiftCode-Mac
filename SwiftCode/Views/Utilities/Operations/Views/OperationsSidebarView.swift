import SwiftUI

struct OperationsSidebarView: View {
    @State private var coord = OperationsCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Operations")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("SwiftCode Management")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // List of Sidebar Items
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarSectionHeader(title: "Overview")
                    SidebarItemRow(panel: .dashboard)
                    SidebarItemRow(panel: .search)

                    SidebarSectionHeader(title: "Management")
                    SidebarItemRow(panel: .projectRegistry)
                    SidebarItemRow(panel: .archives)
                    SidebarItemRow(panel: .buildHistory)
                    SidebarItemRow(panel: .dependencies)

                    SidebarSectionHeader(title: "Diagnostics & Security")
                    SidebarItemRow(panel: .diagnostics)
                    SidebarItemRow(panel: .security)
                    SidebarItemRow(panel: .aiReports)
                    SidebarItemRow(panel: .health)

                    SidebarSectionHeader(title: "Logging & Health")
                    SidebarItemRow(panel: .logs)
                    SidebarItemRow(panel: .timeline)
                    SidebarItemRow(panel: .storage)
                    SidebarItemRow(panel: .queue)
                    SidebarItemRow(panel: .notifications)

                    SidebarSectionHeader(title: "Settings")
                    SidebarItemRow(panel: .preferences)
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }
        }
        .frame(minWidth: 220, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct SidebarItemRow: View {
    let panel: OperationsPanel
    @State private var coord = OperationsCoordinator.shared

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                coord.selectPanel(panel)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: panel.icon)
                    .font(.system(size: 14))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(coord.selectedPanel == panel ? .white : .blue)

                Text(panel.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(coord.selectedPanel == panel ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(coord.selectedPanel == panel ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
