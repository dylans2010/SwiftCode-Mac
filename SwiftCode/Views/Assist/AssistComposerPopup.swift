//
//  AssistComposerPopup.swift
//  SwiftCode
//
//  Interactive popup and selection chips for @ (MCP servers, project files)
//  and / (multi-select mandatory Agent Skills) in the Assist composer.
//

import SwiftUI
import AppKit

public enum ComposerTriggerMode: Equatable {
    case resource(query: String) // @
    case skill(query: String)    // /
}

public struct ComposerResourceItem: Identifiable, Hashable {
    public enum Kind {
        case mcp
        case file
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let fileURL: URL?
}

// MARK: - Chips Bar View

public struct AssistComposerChipsBar: View {
    @Binding public var selectedSkills: [SkillDescriptor]
    @Binding public var selectedMCPServers: [String]
    @Binding public var selectedFiles: [AgentFileContext]

    public var onRemoveSkill: (SkillDescriptor) -> Void
    public var onRemoveMCP: (String) -> Void
    public var onRemoveFile: (AgentFileContext) -> Void

    public init(
        selectedSkills: Binding<[SkillDescriptor]>,
        selectedMCPServers: Binding<[String]>,
        selectedFiles: Binding<[AgentFileContext]>,
        onRemoveSkill: @escaping (SkillDescriptor) -> Void,
        onRemoveMCP: @escaping (String) -> Void,
        onRemoveFile: @escaping (AgentFileContext) -> Void
    ) {
        self._selectedSkills = selectedSkills
        self._selectedMCPServers = selectedMCPServers
        self._selectedFiles = selectedFiles
        self.onRemoveSkill = onRemoveSkill
        self.onRemoveMCP = onRemoveMCP
        self.onRemoveFile = onRemoveFile
    }

    public var isEmpty: Bool {
        selectedSkills.isEmpty && selectedMCPServers.isEmpty && selectedFiles.isEmpty
    }

    public var body: some View {
        if !isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Mandatory Skills chips
                    ForEach(selectedSkills, id: \.id) { skill in
                        chipView(
                            title: skill.name,
                            icon: "wand.and.stars",
                            badge: "Mandatory Skill",
                            color: .orange
                        ) {
                            onRemoveSkill(skill)
                        }
                    }

                    // Mandatory MCP chips
                    ForEach(selectedMCPServers, id: \.self) { server in
                        chipView(
                            title: server,
                            icon: "network",
                            badge: "Mandatory MCP",
                            color: .purple
                        ) {
                            onRemoveMCP(server)
                        }
                    }

                    // Attached Files chips
                    ForEach(selectedFiles, id: \.id) { file in
                        chipView(
                            title: file.filename,
                            icon: "doc.text",
                            badge: "File Context",
                            color: .blue
                        ) {
                            onRemoveFile(file)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    private func chipView(
        title: String,
        icon: String,
        badge: String,
        color: Color,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(badge)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(color.opacity(0.12), in: Capsule())

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Popup Menu View

public struct AssistComposerPopupView: View {
    public let mode: ComposerTriggerMode
    public let onSelectSkill: (SkillDescriptor) -> Void
    public let onSelectMCP: (String) -> Void
    public let onSelectFile: (URL) -> Void
    public let onDismiss: () -> Void

    @ObservedObject private var skillIndex = SkillIndex.shared
    @State private var mcpServers: [MCPServer] = []
    @State private var projectFiles: [URL] = []
    @State private var selectedIndex: Int = 0

    public init(
        mode: ComposerTriggerMode,
        onSelectSkill: @escaping (SkillDescriptor) -> Void,
        onSelectMCP: @escaping (String) -> Void,
        onSelectFile: @escaping (URL) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSelectSkill = onSelectSkill
        self.onSelectMCP = onSelectMCP
        self.onSelectFile = onSelectFile
        self.onDismiss = onDismiss
    }

    private var skillItems: [SkillDescriptor] {
        guard case .skill(let query) = mode else { return [] }
        return skillIndex.search(query: query, limit: 12)
    }

    private var resourceItems: [ComposerResourceItem] {
        guard case .resource(let query) = mode else { return [] }
        let trimmed = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var list: [ComposerResourceItem] = []

        // 1. MCP servers
        for s in mcpServers {
            let serverName = s.displayName
            if trimmed.isEmpty || serverName.lowercased().contains(trimmed) {
                let sub = s.executablePath ?? (s.urlString.isEmpty ? "Configured" : s.urlString)
                list.append(ComposerResourceItem(
                    id: "mcp-\(s.id)",
                    kind: .mcp,
                    title: serverName,
                    subtitle: "MCP Server · \(sub)",
                    iconName: "network",
                    fileURL: nil
                ))
            }
        }

        // 2. Project files
        for url in projectFiles {
            let name = url.lastPathComponent
            if trimmed.isEmpty || name.lowercased().contains(trimmed) || url.path.lowercased().contains(trimmed) {
                list.append(ComposerResourceItem(
                    id: "file-\(url.path)",
                    kind: .file,
                    title: name,
                    subtitle: url.path,
                    iconName: "doc.text",
                    fileURL: url
                ))
            }
        }

        return Array(list.prefix(15))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: isSkillMode ? "wand.and.stars" : "at")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSkillMode ? .orange : .accentColor)

                    Text(isSkillMode ? "Agent Skills (Mandatory Execution)" : "Resources (@MCP or @File)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                Text("esc to close")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // List of filtered options
            ScrollView {
                VStack(spacing: 2) {
                    if isSkillMode {
                        if skillItems.isEmpty {
                            emptyRow(text: "No matching skills found")
                        } else {
                            ForEach(Array(skillItems.enumerated()), id: \.element.id) { idx, skill in
                                skillRow(skill: skill, isSelected: idx == selectedIndex)
                            }
                        }
                    } else {
                        if resourceItems.isEmpty {
                            emptyRow(text: "No matching MCP servers or files found")
                        } else {
                            ForEach(Array(resourceItems.enumerated()), id: \.element.id) { idx, item in
                                resourceRow(item: item, isSelected: idx == selectedIndex)
                            }
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .onAppear {
            loadResources()
        }
        .onExitCommand(perform: onDismiss)
    }

    private var isSkillMode: Bool {
        if case .skill = mode { return true }
        return false
    }

    private func emptyRow(text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 12)
            Spacer()
        }
    }

    private func skillRow(skill: SkillDescriptor, isSelected: Bool) -> some View {
        Button {
            onSelectSkill(skill)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: skill.sourceKind.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Text(skill.sourceKind.rawValue)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    Text(skill.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func resourceRow(item: ComposerResourceItem, isSelected: Bool) -> some View {
        Button {
            switch item.kind {
            case .mcp:
                onSelectMCP(item.title)
            case .file:
                if let url = item.fileURL {
                    onSelectFile(url)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(item.kind == .mcp ? .purple : .blue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(item.kind == .mcp ? "MCP" : "File")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(item.kind == .mcp ? .purple : .blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background((item.kind == .mcp ? Color.purple : Color.blue).opacity(0.12), in: Capsule())
                    }

                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func loadResources() {
        self.mcpServers = MCPServerManager.shared.servers

        // Discover project files if active project exists
        if let dir = ProjectSessionStore.shared.activeProject?.directoryURL {
            Task.detached(priority: .utility) {
                let fm = FileManager.default
                var found: [URL] = []
                if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if found.count >= 60 { break }
                        let ext = fileURL.pathExtension.lowercased()
                        if ["swift", "md", "json", "yml", "yaml", "toml", "txt", "sh", "py", "js", "ts", "html", "css"].contains(ext) {
                            found.append(fileURL)
                        }
                    }
                }
                await MainActor.run {
                    self.projectFiles = found
                }
            }
        }
    }
}
