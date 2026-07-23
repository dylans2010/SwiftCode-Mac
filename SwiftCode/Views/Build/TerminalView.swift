import SwiftUI
import Combine
import os
import Foundation

// MARK: - Logger setup
private let logger = Logger(subsystem: "com.swiftcode.app", category: "TerminalView")

// MARK: - Themes

public enum TerminalTheme: String, CaseIterable, Identifiable, Codable {
    case midnight = "Midnight Blue"
    case monokai = "Monokai Classic"
    case matrix = "Matrix Green"
    case chalkboard = "Chalkboard Gray"
    case solarized = "Solarized Dark"

    public var id: String { rawValue }

    public var backgroundColor: Color {
        switch self {
        case .midnight: return Color(red: 0.06, green: 0.07, blue: 0.10)
        case .monokai: return Color(red: 0.11, green: 0.11, blue: 0.11)
        case .matrix: return .black
        case .chalkboard: return Color(red: 0.18, green: 0.20, blue: 0.22)
        case .solarized: return Color(red: 0.03, green: 0.15, blue: 0.21)
        }
    }

    public var textColor: Color {
        switch self {
        case .matrix: return .green
        default: return Color(red: 0.85, green: 0.85, blue: 0.85)
        }
    }

    public var headerColor: Color {
        switch self {
        case .midnight: return Color(red: 0.10, green: 0.10, blue: 0.14)
        case .monokai: return Color(red: 0.16, green: 0.16, blue: 0.16)
        case .matrix: return Color(red: 0.08, green: 0.08, blue: 0.08)
        case .chalkboard: return Color(red: 0.24, green: 0.26, blue: 0.28)
        case .solarized: return Color(red: 0.04, green: 0.19, blue: 0.26)
        }
    }
}

// MARK: - Models

public enum SplitDirection: Codable {
    case horizontal
    case vertical
}

public struct EnvVar: Identifiable, Codable {
    public var id = UUID()
    public var key: String
    public var value: String
    public var isSecret: Bool
}

public struct CommandLibraryItem: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var command: String
    public var category: String
    public var notes: String
}

public struct TerminalProfile: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var icon: String
    public var executable: String
    public var startupCommand: String
    public var environmentVariables: [String: String]
    public var workingDirectory: String
}

public struct SSHHost: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var address: String
    public var port: Int
    public var username: String
    public var authMethod: String // "password" or "publicKey"
    public var keyPath: String
    public var group: String
    public var tags: String
    public var isFavorite: Bool
}

// MARK: - Split Layout Configuration
public indirect enum LayoutNode: Codable {
    case single(UUID) // Session ID
    case horizontal([LayoutNode])
    case vertical([LayoutNode])

    public var allSessionIDs: [UUID] {
        switch self {
        case .single(let id):
            return [id]
        case .horizontal(let children), .vertical(let children):
            return children.flatMap { $0.allSessionIDs }
        }
    }
}

public struct TerminalTab: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var layout: LayoutNode
    public var isPinned: Bool = false
    public var colorHex: String? = nil
}

// MARK: - Terminal Session

@Observable
@MainActor
public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public var name: String
    public var profile: TerminalProfile?
    public var sshHost: SSHHost?
    public var currentDirectory: String = "/"
    public var outputLines: [TerminalLine] = []
    public var isRunning: Bool = false
    public var startTime = Date()
    public var executionDuration: TimeInterval = 0
    public var lastExitStatus: Int32? = nil
    public var activeCommand: String? = nil

    private var activeProcess: Process?
    private let outputPipe = Pipe()

    public struct TerminalLine: Identifiable {
        public let id = UUID()
        public var text: String
        public var type: LineType
        public var isFolded: Bool = false
        public enum LineType { case command, output, error, info }
    }

    public init(name: String, profile: TerminalProfile? = nil, sshHost: SSHHost? = nil) {
        self.name = name
        self.profile = profile
        self.sshHost = sshHost
        self.outputLines.append(TerminalLine(text: "Session \(name) initialized.", type: .info))
    }

    public func runCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        outputLines.append(TerminalLine(text: trimmed, type: .command))
        activeCommand = trimmed
        isRunning = true

        let runProcess = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        runProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        runProcess.arguments = ["-c", trimmed]

        let pathExists = FileManager.default.fileExists(atPath: currentDirectory)
        runProcess.currentDirectoryURL = URL(fileURLWithPath: pathExists ? currentDirectory : "/")
        runProcess.standardOutput = pipe
        runProcess.standardError = errorPipe

        let outHandle = pipe.fileHandleForReading
        let errHandle = errorPipe.fileHandleForReading

        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.addOutput(output, type: .output)
                }
            }
        }

        errHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.addOutput(output, type: .error)
                }
            }
        }

        runProcess.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.isRunning = false
                self?.lastExitStatus = proc.terminationStatus
                self?.activeCommand = nil
                self?.activeProcess = nil
                self?.addOutput("[Process exited with status \(proc.terminationStatus)]", type: .info)
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
            }
        }

        self.activeProcess = runProcess

        do {
            try runProcess.run()
        } catch {
            addOutput("Failed to run command: \(error.localizedDescription)", type: .error)
            isRunning = false
            self.activeProcess = nil
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
        }
    }

    public func terminate() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
        }
        activeProcess = nil
        isRunning = false
    }

    private func addOutput(_ text: String, type: TerminalLine.LineType) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            outputLines.append(TerminalLine(text: line, type: type))
        }
    }
}

// MARK: - Terminal Manager (Central State)

@Observable
@MainActor
public final class TerminalManager: @unchecked Sendable {
    public static let shared = TerminalManager()

    // Workspace & Sessions
    public var tabs: [TerminalTab] = []
    public var activeTabID: UUID?
    public var sessions: [UUID: TerminalSession] = [:]
    public var activeSessionID: UUID?

    // Custom UI settings
    public var theme: TerminalTheme = .midnight
    public var searchQuery = ""

    // Saved Models
    public var savedHosts: [SSHHost] = []
    public var savedProfiles: [TerminalProfile] = []
    public var commandHistory: [String] = []
    public var commandLibrary: [CommandLibraryItem] = []
    public var environments: [EnvVar] = []

    private init() {
        loadDefaults()
        createNewTab()
    }

    public func createNewTab(withProfile profile: TerminalProfile? = nil) {
        let session = TerminalSession(name: profile?.name ?? "Local Shell", profile: profile)
        sessions[session.id] = session
        let newTab = TerminalTab(name: profile?.name ?? "Local Tab", layout: .single(session.id))
        tabs.append(newTab)
        activeTabID = newTab.id
        activeSessionID = session.id
    }

    public func closeSession(_ id: UUID) {
        sessions[id]?.terminate()
        sessions.removeValue(forKey: id)

        guard let activeTabID = activeTabID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        func cleanNode(_ node: LayoutNode) -> LayoutNode? {
            switch node {
            case .single(let sId):
                return sId == id ? nil : node
            case .horizontal(let children):
                let cleaned = children.compactMap { cleanNode($0) }
                if cleaned.isEmpty { return nil }
                if cleaned.count == 1 { return cleaned.first }
                return .horizontal(cleaned)
            case .vertical(let children):
                let cleaned = children.compactMap { cleanNode($0) }
                if cleaned.isEmpty { return nil }
                if cleaned.count == 1 { return cleaned.first }
                return .vertical(cleaned)
            }
        }

        if let updated = cleanNode(tabs[tabIndex].layout) {
            tabs[tabIndex].layout = updated
            activeSessionID = updated.allSessionIDs.first
        } else {
            tabs.remove(at: tabIndex)
            if tabs.isEmpty {
                createNewTab()
            } else {
                self.activeTabID = tabs.first?.id
                self.activeSessionID = tabs.first?.layout.allSessionIDs.first
            }
        }
    }

    public func connectToHost(_ host: SSHHost) {
        let session = TerminalSession(name: "SSH: \(host.name)", sshHost: host)
        sessions[session.id] = session
        let newTab = TerminalTab(name: host.name, layout: .single(session.id))
        tabs.append(newTab)
        activeTabID = newTab.id
        activeSessionID = session.id

        session.runCommand("ssh -p \(host.port) \(host.username)@\(host.address)")
    }

    private func loadDefaults() {
        savedProfiles = [
            TerminalProfile(name: "zsh", icon: "terminal", executable: "/bin/zsh", startupCommand: "", environmentVariables: [:], workingDirectory: "/"),
            TerminalProfile(name: "bash", icon: "terminal.fill", executable: "/bin/bash", startupCommand: "", environmentVariables: [:], workingDirectory: "/"),
            TerminalProfile(name: "fish", icon: "circle.grid.3x3.fill", executable: "/usr/local/bin/fish", startupCommand: "", environmentVariables: [:], workingDirectory: "/")
        ]

        savedHosts = [
            SSHHost(name: "Vercel Production Server", address: "13.234.45.109", port: 22, username: "admin", authMethod: "publicKey", keyPath: "~/.ssh/id_rsa", group: "Production", tags: "vercel,web", isFavorite: true),
            SSHHost(name: "Staging DB Node", address: "54.120.9.88", port: 5432, username: "postgres", authMethod: "password", keyPath: "", group: "Staging", tags: "db,postgresql", isFavorite: false)
        ]

        commandHistory = [
            "swift build",
            "git status",
            "npm run dev",
            "docker-compose up -d"
        ]

        commandLibrary = [
            CommandLibraryItem(name: "Count Lines of Code", command: "find . -name '*.swift' | xargs wc -l", category: "Git/Utilities", notes: "Recursively find swift files and count total lines of code."),
            CommandLibraryItem(name: "Prune Git Branches", command: "git branch -vv | grep ': gone]' | grep -v '*' | awk '{print $1}' | xargs -r git branch -D", category: "Git/Utilities", notes: "Quickly delete local branches that were already merged on remote.")
        ]

        environments = [
            EnvVar(key: "DEBUG_LEVEL", value: "verbose", isSecret: false),
            EnvVar(key: "PORT", value: "8080", isSecret: false)
        ]
    }
}

// MARK: - Redesigned Primary TerminalView

@MainActor
public struct TerminalView: View {
    @State private var manager = TerminalManager.shared
    @State private var isShowingManagementSuite = false
    @State private var selectedManagementTab = "Settings"

    public var body: some View {
        VStack(spacing: 0) {
            // Tab list toolbar
            tabHeaderView

            // Central Terminal Output & Input Panel
            if let activeTab = manager.tabs.first(where: { $0.id == manager.activeTabID }),
               let sId = activeTab.layout.allSessionIDs.first,
               let session = manager.sessions[sId] {
                InteractiveTerminalSessionView(session: session, manager: manager)
            } else {
                ContentUnavailableView("No active tabs", systemImage: "terminal")
            }
        }
        .background(manager.theme.backgroundColor)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Secondary Managers Launcher Button
                Button {
                    isShowingManagementSuite = true
                } label: {
                    Label("Advanced Options", systemImage: "slider.horizontal.3")
                }
                .help("Launch advanced Terminal settings, SSH node lists, Environment configuration, and snippets")

                Picker("", selection: Bindable(manager).theme) {
                    ForEach(TerminalTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .frame(width: 130)
            }
        }
        .sheet(isPresented: $isShowingManagementSuite) {
            terminalManagementSuiteSheet
        }
    }

    private var tabHeaderView: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(manager.tabs) { tab in
                        HStack(spacing: 6) {
                            Text(tab.name)
                            Button {
                                manager.closeSession(tab.layout.allSessionIDs.first ?? UUID())
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(manager.activeTabID == tab.id ? manager.theme.backgroundColor : manager.theme.headerColor)
                        .cornerRadius(6)
                        .onTapGesture {
                            manager.activeTabID = tab.id
                            manager.activeSessionID = tab.layout.allSessionIDs.first
                        }
                    }
                }
            }

            Button {
                manager.createNewTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(manager.theme.headerColor)
    }

    // MARK: - Advanced Management Suite Sheet

    private var terminalManagementSuiteSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terminal Advanced Management Suite")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isShowingManagementSuite = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            HSplitView {
                // Navigation list for categories
                List {
                    Section("Core Settings") {
                        NavigationLink(state: "Settings", label: "Terminal Settings", icon: "gearshape")
                        NavigationLink(state: "Appearance", label: "Appearance Theme", icon: "paintpalette")
                        NavigationLink(state: "Profiles", label: "Profiles", icon: "person.crop.square")
                    }

                    Section("Connections & Envs") {
                        NavigationLink(state: "SSH", label: "SSH Connections", icon: "network")
                        NavigationLink(state: "Environments", label: "Environment Variables", icon: "slider.horizontal.3")
                        NavigationLink(state: "Processes", label: "Process Manager", icon: "cpu")
                    }

                    Section("History & Snippets") {
                        NavigationLink(state: "History", label: "History Log", icon: "clock.arrow.circlepath")
                        NavigationLink(state: "Snippets", label: "Snippets & Bookmarks", icon: "square.grid.2x2")
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)

                // Detailed subview panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedManagementTab {
                        case "Settings":
                            settingsManagementPanel
                        case "Appearance":
                            appearanceManagementPanel
                        case "Profiles":
                            profilesManagementPanel
                        case "SSH":
                            sshManagementPanel
                        case "Environments":
                            environmentsManagementPanel
                        case "Processes":
                            processManagementPanel
                        case "History":
                            historyManagementPanel
                        case "Snippets":
                            snippetsManagementPanel
                        default:
                            ContentUnavailableView("Category not loaded", systemImage: "terminal")
                        }
                    }
                    .padding(20)
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 800, height: 500)
    }

    private func NavigationLink(state: String, label: String, icon: String) -> some View {
        Button {
            selectedManagementTab = state
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .foregroundStyle(selectedManagementTab == state ? Color.accentColor : Color.primary)
    }

    // MARK: - Advanced Subpanels

    private var settingsManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Terminal Settings")
                .font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Scrollback Buffer limit (1000 lines)", isOn: .constant(true))
                    Toggle("Always launch new sessions in project path", isOn: .constant(true))
                    Toggle("Enable standard error high-contrast highlighting", isOn: .constant(true))
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private var appearanceManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance Theme")
                .font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Theme Style", selection: Bindable(manager).theme) {
                        ForEach(TerminalTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private var profilesManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shell Profiles")
                .font(.title2.bold())

            ForEach(manager.savedProfiles) { profile in
                GroupBox {
                    HStack {
                        Image(systemName: profile.icon)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading) {
                            Text(profile.name).bold()
                            Text(profile.executable).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Select") {
                            manager.createNewTab(withProfile: profile)
                            isShowingManagementSuite = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }

    private var sshManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SSH Connections")
                .font(.title2.bold())

            ForEach(manager.savedHosts) { host in
                GroupBox {
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(host.name).bold()
                            Text("\(host.username)@\(host.address):\(host.port)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") {
                            manager.connectToHost(host)
                            isShowingManagementSuite = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }

    private var environmentsManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Environment Variables")
                .font(.title2.bold())

            ForEach(manager.environments) { env in
                GroupBox {
                    HStack {
                        Text(env.key).bold()
                        Spacer()
                        Text(env.value).foregroundStyle(.secondary)
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }

    private var processManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Process Tree Manager")
                .font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SwiftCode Background Task Nodes")
                        .font(.headline)
                    Text("PID: \(ProcessInfo.processInfo.processIdentifier) | Parent PID: 1 | State: Running")
                        .font(.caption.monospaced())
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private var historyManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Command History Log")
                .font(.title2.bold())

            ForEach(manager.commandHistory, id: \.self) { cmd in
                GroupBox {
                    HStack {
                        Text(cmd).font(.system(.caption, design: .monospaced))
                        Spacer()
                        Button("Run") {
                            if let sId = manager.activeSessionID, let session = manager.sessions[sId] {
                                session.runCommand(cmd)
                            }
                            isShowingManagementSuite = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }

    private var snippetsManagementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Snippets & Bookmarks")
                .font(.title2.bold())

            ForEach(manager.commandLibrary) { item in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name).bold()
                        Text(item.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.cyan)
                            .padding(4)
                            .background(Color.black.opacity(0.12))
                            .cornerRadius(4)
                        Text(item.notes).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }
}

// MARK: - Interactive Session Terminal View

@MainActor
struct InteractiveTerminalSessionView: View {
    @Bindable var session: TerminalSession
    let manager: TerminalManager

    @State private var commandInput = ""
    @State private var isShowingFindBar = false
    @Environment(WorkspaceViewModel.self) private var workspaceVM: WorkspaceViewModel?

    var body: some View {
        VStack(spacing: 0) {
            if isShowingFindBar {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find in output...", text: Bindable(manager).searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                    Spacer()
                    Button("Close") {
                        isShowingFindBar = false
                        manager.searchQuery = ""
                    }
                }
                .padding(6)
                .background(manager.theme.headerColor)
            }

            // Command Area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.outputLines) { line in
                            if matchesFilter(line.text) {
                                HStack(alignment: .top) {
                                    if line.type == .command {
                                        Text("❯")
                                            .foregroundStyle(.cyan)
                                    }
                                    RenderTextLine(text: line.text, workspaceVM: workspaceVM)
                                }
                                .padding(.horizontal)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: session.outputLines.count) {
                    proxy.scrollTo("bottom")
                }
            }
            .background(manager.theme.backgroundColor)

            Divider()

            // Active Path Info bar
            HStack {
                Text("Directory: \(session.currentDirectory)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if session.isRunning {
                    Label("zsh (running)", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(manager.theme.headerColor.opacity(0.5))

            Divider()

            // Input command box
            HStack {
                Text("❯")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)
                TextField("Execute command...", text: $commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        session.runCommand(commandInput)
                        if !manager.commandHistory.contains(commandInput) {
                            manager.commandHistory.append(commandInput)
                        }
                        commandInput = ""
                    }
                Spacer()

                Button {
                    isShowingFindBar.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)

                if session.isRunning {
                    Button {
                        session.terminate()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(manager.theme.headerColor)
        }
        .onTapGesture {
            manager.activeSessionID = session.id
        }
    }

    private func matchesFilter(_ text: String) -> Bool {
        if manager.searchQuery.isEmpty { return true }
        return text.localizedCaseInsensitiveContains(manager.searchQuery)
    }
}

// MARK: - Rich Text Renderer for Terminal Line

@MainActor
struct RenderTextLine: View {
    let text: String
    let workspaceVM: WorkspaceViewModel?

    var body: some View {
        if let fileMatch = parseFilePath(text) {
            Button {
                let fileURL = URL(fileURLWithPath: fileMatch.path)
                Task {
                    await workspaceVM?.editor.openFile(url: fileURL)
                }
            } label: {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .underline()
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.link)
        } else {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    struct FileMatch {
        let path: String
        let line: Int?
    }

    private func parseFilePath(_ text: String) -> FileMatch? {
        let pattern = "(/[a-zA-Z0-9_\\-\\./]+\\.swift):(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        if let first = results.first {
            let pathRange = first.range(at: 1)
            let lineRange = first.range(at: 2)
            let path = nsString.substring(with: pathRange)
            let line = Int(nsString.substring(with: lineRange))
            return FileMatch(path: path, line: line)
        }
        return nil
    }
}
