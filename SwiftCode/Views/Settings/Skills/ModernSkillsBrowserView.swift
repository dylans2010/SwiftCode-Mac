//
//  ModernSkillsBrowserView.swift
//  SwiftCode
//
//  Modern, native macOS Agent Skills browser with fast indexed search,
//  source metadata inspection, category filtering, and SKILL.md preview.
//

import SwiftUI
import AppKit

public struct ModernSkillsBrowserView: View {
    @ObservedObject private var skillIndex = SkillIndex.shared
    @ObservedObject private var discoveryService = SkillDiscoveryService.shared

    @State private var searchText: String = ""
    @State private var selectedSourceFilter: SkillSourceKind? = nil
    @State private var selectedSkillId: String? = nil
    @State private var isShowingDetail: Bool = true

    public init() {}

    private var filteredSkills: [SkillDescriptor] {
        var base: [SkillDescriptor]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = skillIndex.skills
        } else {
            base = skillIndex.search(query: searchText, limit: 100)
        }

        if let filter = selectedSourceFilter {
            base = base.filter { $0.sourceKind == filter }
        }

        return base
    }

    private var selectedSkill: SkillDescriptor? {
        guard let id = selectedSkillId else {
            return filteredSkills.first
        }
        return skillIndex.skills.first(where: { $0.id == id }) ?? filteredSkills.first
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            if let skill = selectedSkill {
                skillDetailView(skill: skill)
            } else {
                emptyStateDetailView
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task {
                        await discoveryService.discoverAndImportAll()
                    }
                } label: {
                    if discoveryService.isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Rescan & Import", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(discoveryService.isDiscovering)
                .help("Scan local development environments and import discovered skills")

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: skillIndex.authoritativeSkillsDirectory.path)
                } label: {
                    Label("Open Skills Folder", systemImage: "folder")
                }
                .help("Reveal authoritative SwiftCode Skills directory in Finder")
            }
        }
    }

    // MARK: - Sidebar List & Search Surface

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Main Search Surface
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))

                TextField("Search agent skills...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Source Filter Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    sourceChip(title: "All (\(skillIndex.skills.count))", isSelected: selectedSourceFilter == nil) {
                        selectedSourceFilter = nil
                    }

                    ForEach(SkillSourceKind.allCases, id: \.self) { kind in
                        let count = skillIndex.skills.filter { $0.sourceKind == kind }.count
                        if count > 0 {
                            sourceChip(
                                title: "\(kind.rawValue) (\(count))",
                                icon: kind.iconName,
                                isSelected: selectedSourceFilter == kind
                            ) {
                                selectedSourceFilter = (selectedSourceFilter == kind) ? nil : kind
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.top, 4)

            // Dynamic Skill Rows
            if filteredSkills.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "No skills available" : "No matching skills")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "Click 'Rescan & Import' to discover installed tools." : "Try a different search term.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredSkills, id: \.id, selection: $selectedSkillId) { skill in
                    SkillRowView(skill: skill, isSelected: selectedSkill?.id == skill.id)
                        .tag(skill.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }

            // Footer status bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(discoveryService.isDiscovering ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text(discoveryService.isDiscovering ? "Scanning machine..." : "\(skillIndex.skills.count) skills active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let date = skillIndex.lastIndexedDate {
                    Text("Indexed \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .border(width: 1, edges: [.top], color: Color.primary.opacity(0.06))
        }
    }

    private func sourceChip(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Inspector View

    private func skillDetailView(skill: SkillDescriptor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: skill.sourceKind.iconName)
                            .font(.system(size: 22))
                            .foregroundColor(.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(skill.name)
                                .font(.system(size: 18, weight: .semibold))

                            Text(skill.sourceKind.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())

                            Spacer()

                            Toggle("Enabled", isOn: Binding(
                                get: { skill.isEnabled },
                                set: { val in
                                    skillIndex.toggleSkillEnabled(id: skill.id, enabled: val)
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        Text(skill.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )

                // Metadata Details
                VStack(alignment: .leading, spacing: 10) {
                    Text("METADATA & PROVENANCE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        detailRow(title: "Source Ecosystem", value: skill.sourceDescription, icon: "building.2")
                        detailRow(title: "Authoritative Location", value: skill.path, icon: "folder", isPath: true)
                        if let orig = skill.originalPath {
                            detailRow(title: "Original Imported From", value: orig, icon: "arrow.down.right.and.arrow.up.left", isPath: true)
                        }
                        detailRow(title: "Last Modified", value: skill.lastModified.formatted(date: .abbreviated, time: .shortened), icon: "clock")

                        if !skill.tags.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Label("Tags", systemImage: "tag")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                FlowTagLayout(spacing: 6) {
                                    ForEach(skill.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.06), in: Capsule())
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }

                // SKILL.md Markdown Content Viewer
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("INSTRUCTION SPECIFICATION (SKILL.MD)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            let skillUrl = URL(fileURLWithPath: skill.path).appendingPathComponent("SKILL.md")
                            NSWorkspace.shared.selectFile(skillUrl.path, inFileViewerRootedAtPath: skill.path)
                        } label: {
                            Label("Reveal File", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    if let content = skill.skillMarkdownContent, !content.isEmpty {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .frame(minHeight: 200, maxHeight: 400)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    } else {
                        Text("No SKILL.md instruction specification found in directory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(20)
        }
    }

    private func detailRow(title: String, value: String, icon: String, isPath: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)

            if isPath {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)

                Spacer()

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: value)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyStateDetailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Select an Agent Skill")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Select a skill from the sidebar to inspect its instructions, provenance, and configuration.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Skill Row View

private struct SkillRowView: View {
    let skill: SkillDescriptor
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: skill.sourceKind.iconName)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(skill.sourceKind.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                Text(skill.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Tag Flow Layout Helper

private struct FlowTagLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat
        if let w = proposal.width, w.isFinite, w > 0 {
            maxWidth = w
        } else {
            maxWidth = 360
        }
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var maxXUsed: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowMaxHeight + spacing
                rowMaxHeight = 0
            }
            rowMaxHeight = max(rowMaxHeight, size.height)
            currentX += size.width + spacing
            maxXUsed = max(maxXUsed, currentX)
        }
        let totalHeight = currentY + rowMaxHeight
        return CGSize(width: min(maxWidth, max(maxXUsed, 40)), height: max(totalHeight, 20))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = (bounds.width.isFinite && bounds.width > 0) ? bounds.width : 360
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowMaxHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.minX + maxWidth && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowMaxHeight + spacing
                rowMaxHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            rowMaxHeight = max(rowMaxHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

// MARK: - View Border Helper Extension

private extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(
            EdgeBorder(width: width, edges: edges)
                .foregroundColor(color)
        )
    }
}

private struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addPath(Path(CGRect(x: x, y: y, width: w, height: h)))
        }
        return path
    }
}
