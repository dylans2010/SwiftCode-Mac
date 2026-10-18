//
//  AssistComposerPopup.swift
//  SwiftCode
//
//  Interactive popup and selection chips for @ (Resources: Conversations, Code context,
//  Rules, Terminal, MCP, Files) and / (Meta Slash Commands, Skills) in the Assist composer.
//  Styled with transparency effects, ultra-thin materials, and low color saturation.
//

import SwiftUI
import AppKit

public enum ComposerTriggerMode: Equatable {
    case resource(query: String) // @
    case skill(query: String)    // /
    case metaCommand(query: String) // / with Meta Code
}

public struct ComposerResourceItem: Identifiable, Hashable {
    public enum Kind: String, Codable {
        case mcp
        case file
        case conversation
        case codeContext
        case rule
        case terminal
        case reverse
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let fileURL: URL?

    public var badgeText: String {
        switch kind {
        case .mcp: return "MCP"
        case .file: return "File"
        case .conversation: return "Conversation"
        case .codeContext: return "Code"
        case .rule: return "Rule"
        case .terminal: return "Terminal"
        case .reverse: return "Reverse"
        }
    }
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
                    // Skills chips
                    ForEach(selectedSkills, id: \.id) { skill in
                        chipView(
                            title: skill.name,
                            icon: "wand.and.stars",
                            badge: "Skill"
                        ) {
                            onRemoveSkill(skill)
                        }
                    }

                    // MCP / Resource chips
                    ForEach(selectedMCPServers, id: \.self) { server in
                        chipView(
                            title: server,
                            icon: server.hasPrefix("@") ? "at" : "network",
                            badge: server.hasPrefix("@") ? "Resource" : "MCP"
                        ) {
                            onRemoveMCP(server)
                        }
                    }

                    // Attached Files chips
                    ForEach(selectedFiles, id: \.id) { file in
                        chipView(
                            title: file.filename,
                            icon: "doc.text",
                            badge: "File"
                        ) {
                            onRemoveFile(file)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private func chipView(
        title: String,
        icon: String,
        badge: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(badge)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06), in: Capsule())

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.75)
        )
    }
}

// MARK: - Interactive Composer Popup View

public struct AssistComposerPopupView: View {
    public let mode: ComposerTriggerMode
    public var onSelectSkill: (SkillDescriptor) -> Void
    public var onSelectMCP: (String) -> Void
    public var onSelectFile: (URL) -> Void
    public var onSelectMetaCommand: ((MetaSlashCommand, String?) -> Void)?
    public var onRequestCommandArguments: ((MetaSlashCommand) -> Void)?
    public var onSelectReverse: (() -> Void)?
    public var onDismiss: () -> Void

    @State private var selectedIndex: Int = 0
    @State private var selectedCategory: String = "All"
    @State private var mcpServers: [MCPServer] = []
    @State private var projectFiles: [URL] = []
    @ObservedObject private var skillIndex = SkillIndex.shared
    @ObservedObject private var metaCommandManager = MetaSlashCommandManager.shared

    public init(
        mode: ComposerTriggerMode,
        onSelectSkill: @escaping (SkillDescriptor) -> Void,
        onSelectMCP: @escaping (String) -> Void,
        onSelectFile: @escaping (URL) -> Void,
        onSelectMetaCommand: ((MetaSlashCommand, String?) -> Void)? = nil,
        onRequestCommandArguments: ((MetaSlashCommand) -> Void)? = nil,
        onSelectReverse: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSelectSkill = onSelectSkill
        self.onSelectMCP = onSelectMCP
        self.onSelectFile = onSelectFile
        self.onSelectMetaCommand = onSelectMetaCommand
        self.onRequestCommandArguments = onRequestCommandArguments
        self.onSelectReverse = onSelectReverse
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

        // 1. Past Conversations (@conversations)
        let convos = AssistConversationHistory.shared.listConversations()
        for c in convos {
            if trimmed.isEmpty || c.title.lowercased().contains(trimmed) || "conversation".contains(trimmed) || "history".contains(trimmed) {
                list.append(ComposerResourceItem(
                    id: "convo-\(c.id)",
                    kind: .conversation,
                    title: c.title,
                    subtitle: "Conversation · \(c.messageCount) msgs · Context available",
                    iconName: "bubble.left.and.bubble.right",
                    fileURL: c.contextFileURL
                ))
            }
        }

        // 2. Code Context (@code)
        let codeMatches = ["code", "context", "active", "file", "selection"]
        if trimmed.isEmpty || codeMatches.contains(where: { $0.contains(trimmed) || trimmed.contains($0) }) {
            list.append(ComposerResourceItem(
                id: "code-active-file",
                kind: .codeContext,
                title: "Active Editor File Context",
                subtitle: "Full buffer of active editor tab and cursor selection",
                iconName: "chevron.left.forwardslash.chevron.right",
                fileURL: nil
            ))
            list.append(ComposerResourceItem(
                id: "code-symbols",
                kind: .codeContext,
                title: "Project Symbol Reference Graph",
                subtitle: "Top-level types, protocols, and extensions index",
                iconName: "square.3.layers.3d",
                fileURL: nil
            ))
        }

        // 3. Agent Task Rules (@rules)
        let standardRules = [
            ("Strict Concurrency Rule", "Enforce Swift 6 Sendable and actor isolation boundaries", "rules-concurrency"),
            ("Clean Architecture Rule", "Enforce clean separation of concerns and MVVM / services", "rules-arch"),
            ("Zero Breaking Changes", "Preserve existing APIs and backward compatibility", "rules-compat"),
            ("A11y & Dynamic Type First", "Ensure VoiceOver traits, dynamic type, and high contrast", "rules-a11y")
        ]
        for (ruleName, ruleDesc, ruleId) in standardRules {
            if trimmed.isEmpty || ruleName.lowercased().contains(trimmed) || "rule".contains(trimmed) {
                list.append(ComposerResourceItem(
                    id: ruleId,
                    kind: .rule,
                    title: ruleName,
                    subtitle: "Task Rule · \(ruleDesc)",
                    iconName: "shield.lefthalf.filled",
                    fileURL: nil
                ))
            }
        }

        // 4. Terminal Context (@terminal)
        if trimmed.isEmpty || "terminal".contains(trimmed) || "console".contains(trimmed) || "shell".contains(trimmed) {
            list.append(ComposerResourceItem(
                id: "term-recent-output",
                kind: .terminal,
                title: "Recent Terminal Buffer",
                subtitle: "Injects recent terminal command outputs and build diagnostics",
                iconName: "terminal",
                fileURL: nil
            ))
        }

        // 4b. Reverse command (@Reverse) — native static analysis.
        // Shown for an empty query or any query matching "reverse".
        if trimmed.isEmpty || "reverse".contains(trimmed) || trimmed.contains("reverse") {
            list.append(ComposerResourceItem(
                id: "reverse-command",
                kind: .reverse,
                title: "@Reverse",
                subtitle: "Static reverse engineering via the native Reverse subsystem (REA) — @Reverse <path> <what to investigate>",
                iconName: "magnifyingglass",
                fileURL: nil
            ))
        }

        // 5. MCP servers
        for s in mcpServers {
            let serverName = s.displayName
            if trimmed.isEmpty || serverName.lowercased().contains(trimmed) || "mcp".contains(trimmed) {
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

        // 6. Project files
        for url in projectFiles {
            let name = url.lastPathComponent
            if trimmed.isEmpty || name.lowercased().contains(trimmed) || url.path.lowercased().contains(trimmed) || "file".contains(trimmed) {
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

        return Array(list.prefix(18))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Basic, translucent header bar with minimal color
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 22, height: 22)

                        Image(systemName: isMetaCommandMode ? "bolt.badge.automatic.fill" : (isSkillMode ? "wand.and.stars" : "at"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.8))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isMetaCommandMode ? "Meta Slash Commands" : (isSkillMode ? "Agent Skills" : "Resources"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        if isMetaCommandMode {
                            Text("\(metaCommandItems.count) commands · Navigate with ↑↓ and Return ↵")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        } else if !isSkillMode {
                            Text("Conversations, files, rules, code context & terminal buffer")
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
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Category filter pills for Meta commands (subtle neutral design)
            if isMetaCommandMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(metaCommandCategories, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                                selectedIndex = 0
                            } label: {
                                Text(cat)
                                    .font(.system(size: 10, weight: selectedCategory == cat ? .semibold : .regular))
                                    .foregroundColor(selectedCategory == cat ? .primary : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(selectedCategory == cat ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedCategory == cat ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .background(.ultraThinMaterial.opacity(0.6))
            }

            Divider()
                .opacity(0.3)

            // Scrollable list of commands/skills/resources
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
                                emptyRow(text: "No matching resources, conversations, or files found")
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
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
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
            case .conversation:
                if let url = item.fileURL {
                    onSelectFile(url)
                } else {
                    onSelectMCP("@conversation: \(item.title)")
                }
            case .codeContext:
                onSelectMCP("@code: \(item.title)")
            case .rule:
                onSelectMCP("@rule: \(item.title)")
            case .terminal:
                onSelectMCP("@terminal: recent_buffer")
            case .reverse:
                onSelectReverse?()
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
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 26, height: 26)

                    Image(systemName: command.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(command.name)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)

                        Text(command.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))

                        Spacer()

                        Text(command.category)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.05), in: Capsule())

                        if command.requiresArguments {
                            HStack(spacing: 2) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 8))
                                Text("Options")
                                    .font(.system(size: 8.5, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }

                    Text(command.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if !command.syntax.isEmpty && command.syntax != command.name {
                        Text(command.syntax)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Image(systemName: command.requiresArguments ? "chevron.right" : "return")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary.opacity(0.4))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 0.5)
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
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Text(skill.sourceKind.rawValue)
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }

                    Text(skill.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
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
            case .conversation:
                if let url = item.fileURL {
                    onSelectFile(url)
                } else {
                    onSelectMCP("@conversation: \(item.title)")
                }
            case .codeContext:
                onSelectMCP("@code: \(item.title)")
            case .rule:
                onSelectMCP("@rule: \(item.title)")
            case .terminal:
                onSelectMCP("@terminal: recent_buffer")
            case .reverse:
                onSelectReverse?()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 11.5))
                    .foregroundColor(.primary.opacity(0.75))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(item.badgeText)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }

                    Text(item.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
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

public typealias AssistComposerPopup = AssistComposerPopupView
