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

public struct SSHTunnel: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var type: String // "local", "remote", "dynamic"
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
}

public struct TerminalTask: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var command: String
    public var schedule: String // e.g. "manual", "interval"
    public var intervalSeconds: Int
}

public struct TerminalRecording: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var date: Date
    public var durationSeconds: Int
    public var lines: [String]
}

public struct ProcessItem: Identifiable {
    public var id = UUID()
    public var pid: Int32
    public var ppid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var state: String
}

public struct RemoteFSNode: Identifiable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var permissions: String
    public var size: Int64
    public var modDate: String
}

public struct RemoteTransfer: Identifiable {
    public var id = UUID()
    public var name: String
    public var size: Int64
    public var percentComplete: Double
    public var direction: String // "upload" or "download"
    public var speed: String
    public var status: String // "Queued", "In Progress", "Completed", "Error"
}

public enum ActivePanel: String, CaseIterable, Identifiable {
    case ssh = "SSH Connections"
    case profiles = "Profiles"
    case history = "History"
    case commandLibrary = "Snippets"
    case environment = "Env Manager"
    case remoteFS = "Remote SFTP"
    case tasks = "Tasks/Macros"
    case recordings = "Recordings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .ssh: return "network"
        case .profiles: return "person.crop.square"
        case .history: return "clock.arrow.circlepath"
        case .commandLibrary: return "square.grid.2x2"
        case .environment: return "slider.horizontal.3"
        case .remoteFS: return "folder.badge.gearshape"
        case .tasks: return "play.square.stack"
        case .recordings: return "record.circle"
        }
    }
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

public struct SavedLayout: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var tabs: [TerminalTab]
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
    private var isRecording: Bool = false
    private var recordingLines: [String] = []

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

    public func startRecording() {
        isRecording = true
        recordingLines = []
        outputLines.append(TerminalLine(text: "[Recording Started]", type: .info))
    }

    public func stopRecording() -> TerminalRecording {
        isRecording = false
        outputLines.append(TerminalLine(text: "[Recording Stopped]", type: .info))
        return TerminalRecording(
            name: "Session Record \(Date().formatted())",
            date: Date(),
            durationSeconds: Int(Date().timeIntervalSince(startTime)),
            lines: recordingLines
        )
    }

    public func runCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        outputLines.append(TerminalLine(text: trimmed, type: .command))
        if isRecording {
            recordingLines.append("❯ \(trimmed)")
        }
        activeCommand = trimmed
        isRunning = true

        let runProcess = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        runProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        runProcess.arguments = ["-c", trimmed]
        runProcess.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
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
            if isRecording {
                recordingLines.append(line)
            }
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
    public var activePanel: ActivePanel = .ssh
    public var showSidebar = true
    public var showInspector = false

    // Saved Models (Persistent simulation/real storage)
    public var savedHosts: [SSHHost] = []
    public var savedProfiles: [TerminalProfile] = []
    public var commandHistory: [String] = []
    public var commandLibrary: [CommandLibraryItem] = []
    public var environments: [EnvVar] = []
    public var savedTasks: [TerminalTask] = []
    public var recordings: [TerminalRecording] = []
    public var transfers: [RemoteTransfer] = []
    public var remoteFSNodes: [RemoteFSNode] = []
    public var currentRemotePath: String = "/home/developer"

    // Multi-Window handling
    public var savedLayouts: [SavedLayout] = []

    // Quick configurations
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

    public func splitActiveSession(direction: SplitDirection) {
        guard let activeTabID = activeTabID,
              let activeSessionID = activeSessionID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        let newSession = TerminalSession(name: "Split Shell")
        sessions[newSession.id] = newSession

        func updateLayout(_ node: LayoutNode) -> LayoutNode {
            switch node {
            case .single(let id):
                if id == activeSessionID {
                    switch direction {
                    case .horizontal:
                        return .horizontal([.single(id), .single(newSession.id)])
                    case .vertical:
                        return .vertical([.single(id), .single(newSession.id)])
                    }
                }
                return node
            case .horizontal(let children):
                return .horizontal(children.map { updateLayout($0) })
            case .vertical(let children):
                return .vertical(children.map { updateLayout($0) })
            }
        }

        tabs[tabIndex].layout = updateLayout(tabs[tabIndex].layout)
        self.activeSessionID = newSession.id
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

    public func duplicateSession(_ id: UUID) {
        guard let session = sessions[id] else { return }
        let copy = TerminalSession(name: "\(session.name) Copy", profile: session.profile, sshHost: session.sshHost)
        sessions[copy.id] = copy

        guard let activeTabID = activeTabID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        func insertDuplicate(_ node: LayoutNode) -> LayoutNode {
            switch node {
            case .single(let sId):
                if sId == id {
                    return .horizontal([.single(sId), .single(copy.id)])
                }
                return node
            case .horizontal(let children):
                return .horizontal(children.map { insertDuplicate($0) })
            case .vertical(let children):
                return .vertical(children.map { insertDuplicate($0) })
            }
        }

        tabs[tabIndex].layout = insertDuplicate(tabs[tabIndex].layout)
        activeSessionID = copy.id
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

    // Layout Persistence
    public func saveLayout(named: String) {
        let layout = SavedLayout(name: named, tabs: tabs)
        savedLayouts.append(layout)
        saveLayoutsToDisk()
    }

    public func restoreLayout(_ layout: SavedLayout) {
        self.tabs = layout.tabs
        for tab in tabs {
            for id in tab.layout.allSessionIDs {
                let session = TerminalSession(name: "Restored Session")
                sessions[id] = session
            }
        }
        self.activeTabID = tabs.first?.id
        self.activeSessionID = tabs.first?.layout.allSessionIDs.first
    }

    // SSH Config parser
    public func parseSSHConfig() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configURL = homeDir.appendingPathComponent(".ssh/config")
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        do {
            let content = try String(contentsOf: configURL, encoding: .utf8)
            var currentHost: SSHHost?
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                let parts = trimmed.components(separatedBy: .whitespaces)
                guard parts.count >= 2 else { continue }
                let keyword = parts[0].lowercased()
                let value = parts[1...].joined(separator: " ")

                if keyword == "host" {
                    if let previous = currentHost {
                        savedHosts.append(previous)
                    }
                    currentHost = SSHHost(name: value, address: "", port: 22, username: "", authMethod: "password", keyPath: "", group: "SSH Config", tags: "imported", isFavorite: false)
                } else if var host = currentHost {
                    if keyword == "hostname" {
                        host.address = value
                    } else if keyword == "user" {
                        host.username = value
                    } else if keyword == "port", let portVal = Int(value) {
                        host.port = portVal
                    } else if keyword == "identityfile" {
                        host.keyPath = value
                        host.authMethod = "publicKey"
                    }
                    currentHost = host
                }
            }

            if let last = currentHost {
                savedHosts.append(last)
            }
            logger.info("Successfully parsed SSH Config.")
        } catch {
            logger.error("Failed to read ~/.ssh/config: \(error.localizedDescription)")
        }
    }

    // Default simulation lists
    private func loadDefaults() {
        savedProfiles = [
            TerminalProfile(name: "zsh", icon: "terminal", executable: "/bin/zsh", startupCommand: "", environmentVariables: [:], workingDirectory: "/"),
            TerminalProfile(name: "bash", icon: "terminal.fill", executable: "/bin/bash", startupCommand: "", environmentVariables: [:], workingDirectory: "/"),
            TerminalProfile(name: "fish", icon: "circle.grid.3x3.fill", executable: "/usr/local/bin/fish", startupCommand: "", environmentVariables: [:], workingDirectory: "/"),
            TerminalProfile(name: "PowerShell", icon: "chevron.right.square.fill", executable: "/usr/local/bin/pwsh", startupCommand: "", environmentVariables: [:], workingDirectory: "/"),
            TerminalProfile(name: "Nushell", icon: "cpu.fill", executable: "/usr/local/bin/nu", startupCommand: "", environmentVariables: [:], workingDirectory: "/")
        ]

        savedHosts = [
            SSHHost(name: "Vercel Production Server", address: "13.234.45.109", port: 22, username: "admin", authMethod: "publicKey", keyPath: "~/.ssh/id_rsa", group: "Production", tags: "vercel,web", isFavorite: true),
            SSHHost(name: "Staging DB Node", address: "54.120.9.88", port: 5432, username: "postgres", authMethod: "password", keyPath: "", group: "Staging", tags: "db,postgresql", isFavorite: false)
        ]

        commandHistory = [
            "swift build",
            "git status",
            "docker-compose up -d",
            "npm run dev",
            "scp -r ./dist user@13.234.45.109:/var/www"
        ]

        commandLibrary = [
            CommandLibraryItem(name: "Count Lines of Code", command: "find . -name '*.swift' | xargs wc -l", category: "Git/Utilities", notes: "Recursively find swift files and count total lines of code."),
            CommandLibraryItem(name: "Prune Git Branches", command: "git branch -vv | grep ': gone]' | grep -v '*' | awk '{print $1}' | xargs -r git branch -D", category: "Git/Utilities", notes: "Quickly delete local branches that were already merged on remote."),
            CommandLibraryItem(name: "Prune Docker Images", command: "docker image prune -f && docker system prune -f", category: "DevOps", notes: "Clean unused Docker storage layers to free up disk space.")
        ]

        environments = [
            EnvVar(key: "API_SECRET_KEY", value: "api_secret_key_placeholder", isSecret: true),
            EnvVar(key: "DEBUG_LEVEL", value: "verbose", isSecret: false),
            EnvVar(key: "PORT", value: "8080", isSecret: false)
        ]

        savedTasks = [
            TerminalTask(name: "Live Lint Analyzer", command: "swiftlint lint", schedule: "manual", intervalSeconds: 0),
            TerminalTask(name: "Automated Backup Pipeline", command: "tar -czf backup.tar.gz ./Sources", schedule: "interval", intervalSeconds: 300)
        ]

        remoteFSNodes = [
            RemoteFSNode(name: "www", path: "/home/developer/www", isDirectory: true, permissions: "drwxr-xr-x", size: 4096, modDate: "Today, 14:32"),
            RemoteFSNode(name: "index.html", path: "/home/developer/index.html", isDirectory: false, permissions: "-rw-r--r--", size: 10423, modDate: "Yesterday, 18:20"),
            RemoteFSNode(name: "api.py", path: "/home/developer/api.py", isDirectory: false, permissions: "-rwxr-xr-x", size: 4560, modDate: "Jul 21, 12:00")
        ]

        parseSSHConfig()
    }

    private func saveLayoutsToDisk() {
        if let data = try? JSONEncoder().encode(savedLayouts) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.terminal.layouts")
        }
    }
}

// MARK: - Views

@MainActor
public struct TerminalView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var manager = TerminalManager.shared

    @State private var isShowingSaveLayoutAlert = false
    @State private var newLayoutName = ""

    public var body: some View {
        HSplitView {
            if manager.showSidebar {
                TerminalSidebar(manager: manager)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)
            }

            VSplitView {
                TerminalWorkspaceArea(manager: manager)
                    .frame(minHeight: 200, maxHeight: .infinity)

                if !manager.transfers.isEmpty {
                    TransferQueuePanel(manager: manager)
                        .frame(height: 150)
                }
            }

            if manager.showInspector {
                TerminalInspectorPanel(manager: manager)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
            }
        }
        .background(manager.theme.backgroundColor)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation {
                        manager.showSidebar.toggle()
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }

                Button {
                    withAnimation {
                        manager.showInspector.toggle()
                    }
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Layout preset picker
                Button {
                    isShowingSaveLayoutAlert = true
                } label: {
                    Label("Save Workspace", systemImage: "square.and.arrow.down")
                }
                .help("Save current split layout configuration")

                Picker("", selection: Bindable(manager).theme) {
                    ForEach(TerminalTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .frame(width: 140)
            }
        }
        .alert("Save Layout", isPresented: $isShowingSaveLayoutAlert) {
            TextField("Layout Name", text: $newLayoutName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if !newLayoutName.isEmpty {
                    manager.saveLayout(named: newLayoutName)
                    newLayoutName = ""
                }
            }
        }
    }
}

// MARK: - Sidebar view

@MainActor
struct TerminalSidebar: View {
    @Bindable var manager: TerminalManager

    var body: some View {
        VStack(spacing: 0) {
            // Panel list switcher
            List(ActivePanel.allCases, selection: $manager.activePanel) { panel in
                Label(panel.rawValue, systemImage: panel.icon)
                    .tag(panel)
            }
            .listStyle(.sidebar)
            .frame(height: 180)

            Divider()

            ScrollView {
                switch manager.activePanel {
                case .ssh:
                    SSHConnectionsSidebar(manager: manager)
                case .profiles:
                    ProfilesSidebar(manager: manager)
                case .history:
                    HistorySidebar(manager: manager)
                case .commandLibrary:
                    CommandLibrarySidebar(manager: manager)
                case .environment:
                    EnvironmentSidebar(manager: manager)
                case .remoteFS:
                    RemoteFSSidebar(manager: manager)
                case .tasks:
                    TasksSidebar(manager: manager)
                case .recordings:
                    RecordingsSidebar(manager: manager)
                }
            }
        }
        .background(manager.theme.headerColor.opacity(0.8))
    }
}

// MARK: - SSH Sidebar

@MainActor
struct SSHConnectionsSidebar: View {
    var manager: TerminalManager
    @State private var isAddingHost = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Connections")
                    .font(.headline)
                Spacer()
                Button {
                    isAddingHost = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)

            ForEach(manager.savedHosts) { host in
                Button {
                    manager.connectToHost(host)
                } label: {
                    HStack {
                        Image(systemName: host.isFavorite ? "star.fill" : "network")
                            .foregroundStyle(host.isFavorite ? .yellow : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                                .fontWeight(.medium)
                            Text("\(host.username)@\(host.address):\(host.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Profiles Sidebar

@MainActor
struct ProfilesSidebar: View {
    var manager: TerminalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shell Profiles")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ForEach(manager.savedProfiles) { profile in
                Button {
                    manager.createNewTab(withProfile: profile)
                } label: {
                    HStack {
                        Image(systemName: profile.icon)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .fontWeight(.medium)
                            Text(profile.executable)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - History Sidebar

@MainActor
struct HistorySidebar: View {
    var manager: TerminalManager
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Command History")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            TextField("Search history...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            let filteredHistory = manager.commandHistory.filter {
                searchQuery.isEmpty || $0.localizedCaseInsensitiveContains(searchQuery)
            }

            ForEach(filteredHistory, id: \.self) { cmd in
                HStack {
                    Text(cmd)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        if let currentSessionID = manager.activeSessionID,
                           let session = manager.sessions[currentSessionID] {
                            session.runCommand(cmd)
                        }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Command Library Sidebar

@MainActor
struct CommandLibrarySidebar: View {
    var manager: TerminalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snippet Library")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ForEach(manager.commandLibrary) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            if let sId = manager.activeSessionID,
                               let session = manager.sessions[sId] {
                                session.runCommand(item.command)
                            }
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    Text(item.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .padding(4)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(4)

                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Environment Sidebar

@MainActor
struct EnvironmentSidebar: View {
    var manager: TerminalManager
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Environment Variables")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            VStack(spacing: 8) {
                TextField("Key", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Value", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                Button("Add Environment Variable") {
                    if !newKey.isEmpty {
                        manager.environments.append(EnvVar(key: newKey, value: newValue, isSecret: false))
                        newKey = ""
                        newValue = ""
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Divider().padding(.vertical)

            ForEach(manager.environments) { env in
                HStack {
                    Text(env.key)
                        .fontWeight(.medium)
                    Spacer()
                    Text(env.isSecret ? "••••••••" : env.value)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Remote FS Sidebar

@MainActor
struct RemoteFSSidebar: View {
    @Bindable var manager: TerminalManager
    @State private var currentPath = "/home/developer"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remote SFTP Explorer")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            HStack {
                TextField("Remote Path", text: $currentPath)
                    .textFieldStyle(.roundedBorder)
                Button("Go") {
                    manager.currentRemotePath = currentPath
                }
            }
            .padding(.horizontal)

            ForEach(manager.remoteFSNodes) { node in
                HStack {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(node.isDirectory ? .yellow : .secondary)
                    VStack(alignment: .leading) {
                        Text(node.name)
                        Text(node.permissions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !node.isDirectory {
                        Button {
                            // Queue a download simulation
                            manager.transfers.append(RemoteTransfer(name: node.name, size: node.size, percentComplete: 0.0, direction: "download", speed: "1.2 MB/s", status: "In Progress"))
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Tasks Sidebar

@MainActor
struct TasksSidebar: View {
    var manager: TerminalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automation Tasks")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ForEach(manager.savedTasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.name)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            if let sId = manager.activeSessionID,
                               let session = manager.sessions[sId] {
                                session.runCommand(task.command)
                            }
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(task.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text("Schedule: \(task.schedule)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Recordings Sidebar

@MainActor
struct RecordingsSidebar: View {
    @Bindable var manager: TerminalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Recordings")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            if let activeSessionID = manager.activeSessionID,
               let session = manager.sessions[activeSessionID] {
                Button("Record Active Session") {
                    session.startRecording()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }

            ForEach(manager.recordings) { recording in
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.name)
                        .fontWeight(.medium)
                    Text("Duration: \(recording.durationSeconds)s | lines: \(recording.lines.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Terminal Workspace Area (Center Tabs & Splits)

@MainActor
struct TerminalWorkspaceArea: View {
    @Bindable var manager: TerminalManager

    var body: some View {
        VStack(spacing: 0) {
            // Tab list toolbar
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(manager.tabs) { tab in
                            HStack {
                                Text(tab.name)
                                Button {
                                    manager.closeSession(tab.layout.allSessionIDs.first ?? UUID())
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
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

                // Split Buttons
                Button {
                    manager.splitActiveSession(direction: .horizontal)
                } label: {
                    Image(systemName: "square.split.2x1")
                }
                .buttonStyle(.plain)

                Button {
                    manager.splitActiveSession(direction: .vertical)
                } label: {
                    Image(systemName: "square.split.1x2")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(manager.theme.headerColor)

            // Split View Workspace rendering
            if let activeTab = manager.tabs.first(where: { $0.id == manager.activeTabID }) {
                LayoutRendererView(node: activeTab.layout, manager: manager)
            } else {
                ContentUnavailableView("No active tabs", systemImage: "terminal")
            }
        }
    }
}

// MARK: - Layout Node Renderer

@MainActor
struct LayoutRendererView: View {
    let node: LayoutNode
    let manager: TerminalManager

    var body: some View {
        switch node {
        case .single(let sessionID):
            if let session = manager.sessions[sessionID] {
                InteractiveTerminalSessionView(session: session, manager: manager)
            } else {
                Color.clear
            }
        case .horizontal(let children):
            HSplitView {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    LayoutRendererView(node: child, manager: manager)
                }
            }
        case .vertical(let children):
            VSplitView {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    LayoutRendererView(node: child, manager: manager)
                }
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
    @State private var findQuery = ""
    @State private var isShowingFindBar = false
    @Environment(WorkspaceViewModel.self) private var workspaceVM: WorkspaceViewModel?

    var body: some View {
        VStack(spacing: 0) {
            if isShowingFindBar {
                HStack {
                    TextField("Find in output...", text: $findQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                    Spacer()
                    Button("Close") {
                        isShowingFindBar = false
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
                        manager.commandHistory.append(commandInput)
                        commandInput = ""
                    }
                Spacer()
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
        if findQuery.isEmpty { return true }
        return text.localizedCaseInsensitiveContains(findQuery)
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
        // Matches typical compiler error styles: /path/to/file.swift:45:12 or similar
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

// MARK: - Transfer Queue Panel

@MainActor
struct TransferQueuePanel: View {
    @Bindable var manager: TerminalManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfer Queue")
                    .font(.headline)
                Spacer()
                Button("Clear Completed") {
                    manager.transfers.removeAll(where: { $0.status == "Completed" })
                }
            }
            .padding()
            .background(manager.theme.headerColor)

            List(manager.transfers) { transfer in
                HStack {
                    Image(systemName: transfer.direction == "download" ? "arrow.down.circle" : "arrow.up.circle")
                    Text(transfer.name)
                    Spacer()
                    ProgressView(value: transfer.percentComplete, total: 100.0)
                        .frame(width: 150)
                    Text(transfer.speed)
                    Text(transfer.status)
                }
            }
        }
    }
}

// MARK: - Terminal Inspector Panel (Right Sidebar)

@MainActor
struct TerminalInspectorPanel: View {
    @Bindable var manager: TerminalManager
    @State private var activeTab = "Stats"

    var body: some View {
        VStack {
            Picker("", selection: $activeTab) {
                Text("Metadata").tag("Stats")
                Text("Process Explorer").tag("Processes")
                Text("Git Status").tag("Git")
                Text("AI Support").tag("AI")
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                switch activeTab {
                case "Stats":
                    SessionInspectorTab(manager: manager)
                case "Processes":
                    ProcessExplorerTab()
                case "Git":
                    GitStatusTab()
                case "AI":
                    AITerminalAssistantTab(manager: manager)
                default:
                    Color.clear
                }
            }
        }
        .background(manager.theme.headerColor.opacity(0.8))
    }
}

// MARK: - Session Inspector Tab

@MainActor
struct SessionInspectorTab: View {
    let manager: TerminalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sId = manager.activeSessionID,
               let session = manager.sessions[sId] {
                Text("Active Terminal Details")
                    .font(.headline)

                Group {
                    LabeledContent("Session Name", value: session.name)
                    LabeledContent("Active Folder", value: session.currentDirectory)
                    LabeledContent("PID", value: "\(ProcessInfo.processInfo.processIdentifier)")
                    LabeledContent("Exit Code", value: session.lastExitStatus.map { String($0) } ?? "N/A")
                }
                .font(.subheadline)

                Divider()

                Text("Remote Server Diagnostics")
                    .font(.headline)

                VStack(spacing: 12) {
                    ProgressGauge(title: "CPU Load", percentage: 42, color: .green)
                    ProgressGauge(title: "Memory Commit", percentage: 68, color: .blue)
                    ProgressGauge(title: "Storage Pool Size", percentage: 89, color: .orange)
                }
            } else {
                ContentUnavailableView("No Active Session", systemImage: "terminal")
            }
        }
        .padding()
    }
}

// MARK: - Progress Gauge

@MainActor
struct ProgressGauge: View {
    let title: String
    let percentage: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(percentage))%")
            }
            .font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(percentage / 100.0))
                }
            }
            .frame(height: 6)
            .cornerRadius(3)
        }
    }
}

// MARK: - Process Explorer Tab

@MainActor
struct ProcessExplorerTab: View {
    @State private var processes: [ProcessItem] = [
        ProcessItem(pid: 2981, ppid: 1, name: "zsh", cpuPercent: 0.1, memoryPercent: 1.2, state: "Running"),
        ProcessItem(pid: 2994, ppid: 2981, name: "swift build", cpuPercent: 12.4, memoryPercent: 4.5, state: "Running"),
        ProcessItem(pid: 3001, ppid: 2981, name: "node", cpuPercent: 1.1, memoryPercent: 3.8, state: "Suspended")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Process Tree Manager")
                .font(.headline)
                .padding(.horizontal)

            ForEach(processes) { proc in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(proc.name)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("PID: \(proc.pid)")
                            .font(.caption)
                    }
                    HStack {
                        Text("CPU: \(proc.cpuPercent, specifier: "%.1f")%")
                        Text("MEM: \(proc.memoryPercent, specifier: "%.1f")%")
                        Spacer()
                        Button("Kill") {
                            // Run kill shell commands to kill real pid
                            let killProcess = Process()
                            killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
                            killProcess.arguments = ["-9", "\(proc.pid)"]
                            try? killProcess.run()
                            processes.removeAll(where: { $0.pid == proc.pid })
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Git Status Tab

@MainActor
struct GitStatusTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Git Control Hub")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Active Branch", value: "main")
                LabeledContent("Staged Files", value: "3 files")
                LabeledContent("Modified Files", value: "5 files")
                LabeledContent("Ahead / Behind", value: "↑ 2 | ↓ 0")
            }

            Divider()

            HStack {
                Button("Commit") {
                    // Quick git action execution
                }
                Button("Pull") {
                    // Git pull
                }
                Button("Push") {
                    // Git push
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - AI Terminal Assistant Tab

@MainActor
struct AITerminalAssistantTab: View {
    let manager: TerminalManager
    @State private var query = ""
    @State private var response = ""
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Terminal Genius")
                .font(.headline)

            Text("Troubleshoot compilation errors, generate complex pipeline scripts, or ask command explanations.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Ask the terminal assistant...", text: $query)
                .textFieldStyle(.roundedBorder)

            Button("Send Context to AI") {
                generateAIHelp()
            }
            .buttonStyle(.borderedProminent)
            .disabled(query.isEmpty || isGenerating)

            if isGenerating {
                ProgressView()
            }

            if !response.isEmpty {
                ScrollView {
                    Text(response)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 250)
            }
        }
        .padding()
    }

    private func generateAIHelp() {
        guard !query.isEmpty else { return }
        isGenerating = true
        response = ""

        // Extract context lines from the current active terminal
        var contextLines = ""
        if let sId = manager.activeSessionID,
           let session = manager.sessions[sId] {
            let lastLines = session.outputLines.suffix(20).map { $0.text }
            contextLines = lastLines.joined(separator: "\n")
        }

        let sysPrompt = "You are a senior macOS developer. Answer the question using the following terminal context if helpful. Provide exact commands and explanations."
        let promptContent = "User Query: \(query)\n\nTerminal Context:\n\(contextLines)"

        Task {
            do {
                try await OpenRouterService.shared.streamChat(
                    messages: [AIMessage(role: .user, content: promptContent)],
                    model: "meta-llama/llama-3-70b-instruct",
                    systemPrompt: sysPrompt
                ) { token in
                    await MainActor.run {
                        response += token
                    }
                }
                await MainActor.run {
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    response = "Error during generation: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }
}
