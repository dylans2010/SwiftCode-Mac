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
    case metaCommand(query: String) // / with Meta Code
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
    public var onSelectMetaCommand: ((MetaSlashCommand, String?) -> Void)? = nil
    public var onRequestCommandArguments: ((MetaSlashCommand) -> Void)? = nil
    public let onDismiss: () -> Void

    @ObservedObject private var skillIndex = SkillIndex.shared
    @ObservedObject private var metaCommandManager = MetaSlashCommandManager.shared
    @State private var mcpServers: [MCPServer] = []
    @State private var projectFiles: [URL] = []
    @State private var selectedIndex: Int = 0
    @State private var selectedCategory: String = "All"

    public init(
        mode: ComposerTriggerMode,
        onSelectSkill: @escaping (SkillDescriptor) -> Void,
        onSelectMCP: @escaping (String) -> Void,
        onSelectFile: @escaping (URL) -> Void,
        onSelectMetaCommand: ((MetaSlashCommand, String?) -> Void)? = nil,
        onRequestCommandArguments: ((MetaSlashCommand) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSelectSkill = onSelectSkill
        self.onSelectMCP = onSelectMCP
        self.onSelectFile = onSelectFile
        self.onSelectMetaCommand = onSelectMetaCommand
        self.onRequestCommandArguments = onRequestCommandArguments
        self.onDismiss = onDismiss
    }

    private var metaCommandCategories: [String] {
        var cats = ["All"]
        let allCategories = Set(metaCommandManager.commands.map { $0.category })
        cats.append(contentsOf: allCategories.sorted())
        return cats
    }

    private var metaCommandItems: [MetaSlashCommand] {
        guard case .metaCommand(let query) = mode else { return [] }
        let allFiltered = metaCommandManager.searchCommands(query: query)
        if selectedCategory == "All" {
            return allFiltered
        } else {
            return allFiltered.filter { $0.category.caseInsensitiveCompare(selectedCategory) == .orderedSame }
        }
    }

    private var skillItems: [SkillDescriptor] {
        guard case .skill(let query) = mode else { return [] }
        return skillIndex.search(query: query, limit: 16)
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
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: isMetaCommandMode ? [Color.orange.opacity(0.85), Color.pink.opacity(0.75)] : (isSkillMode ? [Color.orange.opacity(0.8), Color.yellow.opacity(0.7)] : [Color.blue.opacity(0.8), Color.purple.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 22, height: 22)

                        Image(systemName: isMetaCommandMode ? "bolt.badge.automatic.fill" : (isSkillMode ? "wand.and.stars" : "at"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isMetaCommandMode ? "Meta Slash Commands" : (isSkillMode ? "Agent Skills (Mandatory Execution)" : "Resources (@MCP or @File)"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)

                        if isMetaCommandMode {
                            Text("\(metaCommandItems.count) commands available · Navigate with ↑↓ and Return ↵")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("esc to dismiss")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))

            // Category filter pills for Meta commands
            if isMetaCommandMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(metaCommandCategories, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                                selectedIndex = 0
                            } label: {
                                Text(cat)
                                    .font(.system(size: 10, weight: selectedCategory == cat ? .bold : .medium))
                                    .foregroundColor(selectedCategory == cat ? .orange : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(selectedCategory == cat ? Color.orange.opacity(0.18) : Color.primary.opacity(0.04))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedCategory == cat ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            }

            Divider()
                .opacity(0.6)

            // Scrollable list of commands/skills/resources with explicit non-collapsing frame
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if isMetaCommandMode {
                            if metaCommandItems.isEmpty {
                                emptyRow(text: "No matching Meta commands found for '\(selectedCategory)'")
                            } else {
                                ForEach(Array(metaCommandItems.enumerated()), id: \.element.id) { idx, cmd in
                                    metaCommandRow(command: cmd, isSelected: idx == selectedIndex)
                                        .id(idx)
                                }
                            }
                        } else if isSkillMode {
                            if skillItems.isEmpty {
                                emptyRow(text: "No matching skills found")
                            } else {
                                ForEach(Array(skillItems.enumerated()), id: \.element.id) { idx, skill in
                                    skillRow(skill: skill, isSelected: idx == selectedIndex)
                                        .id(idx)
                                }
                            }
                        } else {
                            if resourceItems.isEmpty {
                                emptyRow(text: "No matching MCP servers or files found")
                            } else {
                                ForEach(Array(resourceItems.enumerated()), id: \.element.id) { idx, item in
                                    resourceRow(item: item, isSelected: idx == selectedIndex)
                                        .id(idx)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(height: 290)
                .onChange(of: selectedIndex) { _, newIdx in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 490)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.4), Color.primary.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
        .onAppear {
            loadResources()
        }
        .onExitCommand(perform: onDismiss)
        .background(
            VStack {
                Button("") {
                    selectPreviousItem()
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("") {
                    selectNextItem()
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button("") {
                    commitSelectedItem()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .opacity(0.001)
            .frame(width: 0, height: 0)
        )
    }

    private var currentItemsCount: Int {
        if isMetaCommandMode {
            return metaCommandItems.count
        } else if isSkillMode {
            return skillItems.count
        } else {
            return resourceItems.count
        }
    }

    private func selectPreviousItem() {
        let count = currentItemsCount
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    private func selectNextItem() {
        let count = currentItemsCount
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    private func commitSelectedItem() {
        if isMetaCommandMode {
            guard selectedIndex >= 0 && selectedIndex < metaCommandItems.count else { return }
            triggerMetaCommand(metaCommandItems[selectedIndex])
        } else if isSkillMode {
            guard selectedIndex >= 0 && selectedIndex < skillItems.count else { return }
            onSelectSkill(skillItems[selectedIndex])
        } else {
            guard selectedIndex >= 0 && selectedIndex < resourceItems.count else { return }
            let item = resourceItems[selectedIndex]
            switch item.kind {
            case .mcp:
                onSelectMCP(item.title)
            case .file:
                if let url = item.fileURL {
                    onSelectFile(url)
                }
            }
        }
    }

    private var isMetaCommandMode: Bool {
        if case .metaCommand = mode { return true }
        return false
    }

    private var isSkillMode: Bool {
        if case .skill = mode { return true }
        return false
    }

    private func metaCommandRow(command: MetaSlashCommand, isSelected: Bool) -> some View {
        Button {
            triggerMetaCommand(command)
        } label: {
            HStack(spacing: 10) {
                // SF Symbol icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(isSelected ? 0.35 : 0.18), Color.pink.opacity(isSelected ? 0.25 : 0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: command.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(command.name)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)

                        Text(command.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(command.category)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.07), in: Capsule())

                        if command.requiresArguments {
                            HStack(spacing: 2) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 8))
                                Text("Options")
                                    .font(.system(size: 8.5, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(command.description)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if !command.syntax.isEmpty && command.syntax != command.name {
                        Text(command.syntax)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }

                Image(systemName: command.requiresArguments ? "chevron.right" : "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .orange : .secondary.opacity(0.5))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected ?
                            LinearGradient(
                                colors: [Color.orange.opacity(0.18), Color.orange.opacity(0.06)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func triggerMetaCommand(_ command: MetaSlashCommand) {
        if command.requiresArguments {
            if let onRequestCommandArguments {
                onRequestCommandArguments(command)
            } else if let onSelectMetaCommand {
                onSelectMetaCommand(command, nil)
            }
        } else {
            onSelectMetaCommand?(command, nil)
        }
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
