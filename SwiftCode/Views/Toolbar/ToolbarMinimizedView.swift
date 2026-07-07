import SwiftUI


struct ToolbarMinimizedView: View {
    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExpanded, arrowEdge: .top) {
            ToolbarExpandedPanelView(isPresented: $isExpanded)
                .preferredColorScheme(.dark)
        }
        .help("Expand Toolbar")
    }
}

// MARK: - Expanded Panel

struct ToolbarExpandedPanelView: View {
    @Binding var isPresented: Bool
    @StateObject private var toolbarManager = ToolbarManager.shared

    private var groupedTools: [String: [ToolbarTool]] {
        Dictionary(grouping: toolbarManager.tools, by: { $0.category })
    }

    private var categories: [String] {
        groupedTools.keys.sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(categories, id: \.self) { category in
                        categorySection(category, tools: groupedTools[category] ?? [])
                        Divider().opacity(0.15)
                    }
                }
            }
            .navigationTitle("All Tools")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 450)
    }

    private func categorySection(_ title: String, tools: [ToolbarTool]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(tools) { tool in
                    toolButton(tool)
                }
            }
            .padding(12)
        }
    }

    private func toolButton(_ tool: ToolbarTool) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .toolbarToolActivated,
                object: nil,
                userInfo: ["toolID": tool.id]
            )
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                Text(tool.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
