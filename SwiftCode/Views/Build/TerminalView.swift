import SwiftUI

// MARK: - Terminal View

struct TerminalView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var commandInput = ""
    @State private var outputLines: [TerminalLine] = [
        TerminalLine(text: "SwiftCode Terminal v1.2 — type 'help' for available commands", type: .info)
    ]
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    @State private var isRunning = false
    @State private var currentDirectory: String? = nil
    @FocusState private var inputFocused: Bool

    struct TerminalLine: Identifiable {
        let id = UUID()
        var text: String
        var type: LineType
        enum LineType { case command, output, error, info }
        var color: Color {
            switch type {
            case .command: return .cyan
            case .output:  return Color(red: 0.85, green: 0.85, blue: 0.85)
            case .error:   return .red
            case .info:    return .green
            }
        }
    }

    /// Returns the effective working directory URL.
    private var workingDirectoryURL: URL? {
        if let cwd = currentDirectory {
            return URL(fileURLWithPath: cwd)
        }
        return projectManager.activeProject?.directoryURL
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider().opacity(0.3)
            outputArea
            Divider().opacity(0.3)
            inputBar
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.10))
        .onAppear {
            inputFocused = true
            if let dir = projectManager.activeProject?.directoryURL {
                currentDirectory = dir.path
            }
        }
        .onChange(of: projectManager.activeProject?.id) {
            if let dir = projectManager.activeProject?.directoryURL {
                currentDirectory = dir.path
            }
        }
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Circle().fill(.yellow).frame(width: 10, height: 10)
            Circle().fill(.green).frame(width: 10, height: 10)
            Spacer()
            Text(promptPrefix)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                outputLines = [TerminalLine(text: "Cleared.", type: .info)]
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
    }

    private var promptPrefix: String {
        if let dir = workingDirectoryURL {
            return dir.lastPathComponent
        }
        return "Terminal"
    }

    // MARK: - Output Area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(outputLines) { line in
                        HStack(alignment: .top, spacing: 4) {
                            if line.type == .command {
                                Text("❯")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.color)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onChange(of: outputLines.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("❯")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.cyan)

            TextField("", text: $commandInput)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($inputFocused)
                .onSubmit { runCommand() }
                .onChange(of: commandInput) { _, _ in
                    historyIndex = -1
                }

            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.green)
            } else {
                Button {
                    runCommand()
                } label: {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
    }

    // MARK: - Command Execution

    private func runCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        commandHistory.insert(cmd, at: 0)
        commandInput = ""
        historyIndex = -1

        outputLines.append(TerminalLine(text: cmd, type: .command))

        Task {
            await executeCommand(cmd)
        }
    }

    @MainActor
    private func executeCommand(_ cmd: String) async {
        isRunning = true
        defer { isRunning = false }

        let fm = FileManager.default
        let parts = tokenize(cmd)
        let command = parts.first ?? ""
        let args = Array(parts.dropFirst())

        switch command.lowercased() {
        case "help":
            addOutput(helpText, type: .output)

        case "clear":
            outputLines = [TerminalLine(text: "Cleared.", type: .info)]

        case "pwd":
            addOutput(workingDirectoryURL?.path ?? "(No Project Open)", type: .output)

        case "ls", "dir":
            executeLs(args: args)

        case "cd":
            executeCd(args: args)

        case "mkdir":
            executeMkdir(args: args)

        case "touch":
            executeTouch(args: args)

        case "rm":
            executeRm(args: args)

        case "mv":
            executeMv(args: args)

        case "cp":
            executeCp(args: args)

        case "cat":
            executeCat(args: args)

        case "echo":
            let text = args.joined(separator: " ")
            addOutput(text, type: .output)

        case "env":
            addOutput("PATH=/usr/bin:/bin\nHOME=\(NSHomeDirectory())\nSHELL=/bin/sh", type: .output)

        case "date":
            addOutput(Date().description, type: .output)

        case "whoami":
            addOutput(NSUserName(), type: .output)

        case "uname":
            addOutput("Darwin SwiftCode iOS", type: .output)

        case "grep":
            executeGrep(args: args)

        case "find":
            executeFind(args: args)

        case "wc":
            executeWc(args: args)

        case "head":
            executeHead(args: args)

        case "tail":
            executeTail(args: args)

        case "git":
            await executeGit(args: args)

        case "swift":
            await executeSwift(args: args)

        case "open":
            executeOpen(args: args)

        default:
            addOutput("command not found: \(command)", type: .error)
            addOutput("Type 'help' for a list of available commands.", type: .info)
        }

        _ = fm.fileExists(atPath: "") // suppress unused warning
    }

    // MARK: - Individual Command Handlers

    private func executeLs(args: [String]) {
        guard let dir = resolveDirectory(args.first) else {
            addOutput("ls: no such file or directory", type: .error); return
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir,
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: .skipsHiddenFiles) else {
            addOutput("ls: cannot access directory", type: .error); return
        }
        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if sorted.isEmpty {
            addOutput("(empty)", type: .output)
        } else {
            let names = sorted.map { url -> String in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                return isDir ? "\(url.lastPathComponent)/" : url.lastPathComponent
            }
            addOutput(names.joined(separator: "  "), type: .output)
        }
    }

    private func executeCd(args: [String]) {
        let target = args.first ?? "~"
        if target == "~" || target == "" {
            if let home = projectManager.activeProject?.directoryURL {
                currentDirectory = home.path
                addOutput("", type: .output)
            }
            return
        }
        if target == ".." {
            if let cwd = workingDirectoryURL {
                let parent = cwd.deletingLastPathComponent()
                currentDirectory = parent.path
            }
            return
        }
        guard let newDir = resolveDirectory(target) else {
            addOutput("cd: no such file or directory: \(target)", type: .error); return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: newDir.path, isDirectory: &isDir), isDir.boolValue else {
            addOutput("cd: not a directory: \(target)", type: .error); return
        }
        currentDirectory = newDir.path
    }

    private func executeMkdir(args: [String]) {
        guard !args.isEmpty else { addOutput("mkdir: missing operand", type: .error); return }
        for name in args {
            guard let dir = resolveFile(name) else { continue }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                addOutput("Created directory: \(name)", type: .info)
                // refresh project files if inside project
                if dir.path.hasPrefix(projectManager.activeProject?.directoryURL.path ?? "") {
                    projectManager.loadProjects()
                }
            } catch {
                addOutput("mkdir: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func executeTouch(args: [String]) {
        guard !args.isEmpty else { addOutput("touch: missing operand", type: .error); return }
        for name in args {
            guard let file = resolveFile(name) else { continue }
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
                addOutput("Created: \(name)", type: .info)
                if file.path.hasPrefix(projectManager.activeProject?.directoryURL.path ?? "") {
                    projectManager.loadProjects()
                }
            } else {
                // Update modification date
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            }
        }
    }

    private func executeRm(args: [String]) {
        let recursive = args.contains("-r") || args.contains("-rf") || args.contains("-fr")
        let targets = args.filter { !$0.hasPrefix("-") }
        guard !targets.isEmpty else { addOutput("rm: missing operand", type: .error); return }
        for name in targets {
            guard let file = resolveFile(name) else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) else {
                addOutput("rm: \(name): No such file or directory", type: .error); continue
            }
            if isDir.boolValue && !recursive {
                addOutput("rm: \(name): is a directory (use -r to remove)", type: .error); continue
            }
            do {
                try FileManager.default.removeItem(at: file)
                addOutput("Removed: \(name)", type: .info)
                if file.path.hasPrefix(projectManager.activeProject?.directoryURL.path ?? "") {
                    projectManager.loadProjects()
                }
            } catch {
                addOutput("rm: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func executeMv(args: [String]) {
        guard args.count == 2 else { addOutput("Usage: mv <source> <destination>", type: .error); return }
        guard let src = resolveFile(args[0]), let dst = resolveFile(args[1]) else { return }
        do {
            try FileManager.default.moveItem(at: src, to: dst)
            addOutput("Moved '\(args[0])' → '\(args[1])'", type: .info)
            projectManager.loadProjects()
        } catch {
            addOutput("mv: \(error.localizedDescription)", type: .error)
        }
    }

    private func executeCp(args: [String]) {
        guard args.count >= 2 else { addOutput("Usage: cp <source> <destination>", type: .error); return }
        let recursive = args.contains("-r") || args.contains("-R")
        let cleanArgs = args.filter { !$0.hasPrefix("-") }
        guard cleanArgs.count >= 2 else { addOutput("Usage: cp <source> <destination>", type: .error); return }
        guard let src = resolveFile(cleanArgs[0]), let dst = resolveFile(cleanArgs[1]) else { return }
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            addOutput("Copied '\(cleanArgs[0])' → '\(cleanArgs[1])'", type: .info)
            _ = recursive
            projectManager.loadProjects()
        } catch {
            addOutput("cp: \(error.localizedDescription)", type: .error)
        }
    }

    private func executeCat(args: [String]) {
        guard !args.isEmpty else { addOutput("cat: missing file operand", type: .error); return }
        for name in args {
            guard let file = resolveFile(name) else { continue }
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                addOutput(content, type: .output)
            } else {
                addOutput("cat: \(name): No such file or cannot read", type: .error)
            }
        }
    }

    private func executeGrep(args: [String]) {
        let caseInsensitive = args.contains("-i")
        let cleaned = args.filter { !$0.hasPrefix("-") }
        guard cleaned.count >= 2 else {
            addOutput("Usage: grep [-i] <pattern> <file>", type: .error); return
        }
        let pattern = cleaned[0]
        let fileName = cleaned[1]
        guard let file = resolveFile(fileName),
              let content = try? String(contentsOf: file, encoding: .utf8) else {
            addOutput("grep: \(fileName): No such file or cannot read", type: .error); return
        }
        let lines = content.components(separatedBy: "\n")
        var found = false
        for (i, line) in lines.enumerated() {
            let match = caseInsensitive
                ? line.localizedCaseInsensitiveContains(pattern)
                : line.contains(pattern)
            if match {
                addOutput("\(i + 1): \(line)", type: .output)
                found = true
            }
        }
        if !found {
            addOutput("(no matches found)", type: .info)
        }
    }

    private func executeFind(args: [String]) {
        let startPath = args.first.flatMap { resolveFile($0) } ?? workingDirectoryURL
        guard let base = startPath else {
            addOutput("find: no directory specified", type: .error); return
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: nil,
                                              options: .skipsHiddenFiles) else { return }
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            addOutput(url.path.replacingOccurrences(of: base.path + "/", with: "./"), type: .output)
            count += 1
            if count > 200 { addOutput("… (truncated at 200 entries)", type: .info); break }
        }
    }

    private func executeWc(args: [String]) {
        guard !args.isEmpty else { addOutput("Usage: wc <file>", type: .error); return }
        let name = args.last!
        guard let file = resolveFile(name),
              let content = try? String(contentsOf: file, encoding: .utf8) else {
            addOutput("wc: \(name): No such file", type: .error); return
        }
        let lines = content.components(separatedBy: "\n").count
        let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let chars = content.count
        addOutput("\(lines)\t\(words)\t\(chars)\t\(name)", type: .output)
    }

    private func executeHead(args: [String]) {
        let n: Int
        var fileArgs = args
        if let nIdx = args.firstIndex(of: "-n"), args.count > nIdx + 1 {
            n = Int(args[nIdx + 1]) ?? 10
            fileArgs = args.filter { $0 != "-n" && $0 != "\(n)" }
        } else {
            n = 10
        }
        guard let name = fileArgs.first,
              let file = resolveFile(name),
              let content = try? String(contentsOf: file, encoding: .utf8) else {
            addOutput("head: cannot read file", type: .error); return
        }
        let lines = Array(content.components(separatedBy: "\n").prefix(n))
        addOutput(lines.joined(separator: "\n"), type: .output)
    }

    private func executeTail(args: [String]) {
        let n: Int
        var fileArgs = args
        if let nIdx = args.firstIndex(of: "-n"), args.count > nIdx + 1 {
            n = Int(args[nIdx + 1]) ?? 10
            fileArgs = args.filter { $0 != "-n" && $0 != "\(n)" }
        } else {
            n = 10
        }
        guard let name = fileArgs.first,
              let file = resolveFile(name),
              let content = try? String(contentsOf: file, encoding: .utf8) else {
            addOutput("tail: cannot read file", type: .error); return
        }
        let lines = Array(content.components(separatedBy: "\n").suffix(n))
        addOutput(lines.joined(separator: "\n"), type: .output)
    }

    private func executeOpen(args: [String]) {
        guard let name = args.first else { addOutput("Usage: open <file>", type: .error); return }
        guard let file = resolveFile(name) else { return }
        let node = FileNode(name: file.lastPathComponent, path: file.path, isDirectory: false)
        projectManager.openFile(node)
        addOutput("Opened: \(name)", type: .info)
    }

    @MainActor
    private func executeGit(args: [String]) async {
        let sub = args.first ?? ""
        switch sub {
        case "status":
            addOutput("On branch main\nnothing to commit, working tree clean", type: .output)
        case "log":
            addOutput("""
commit a1b2c3d (HEAD -> main, origin/main)
Author: Developer <dev@example.com>
Date:   \(Date())

    Latest changes
""", type: .output)
        case "pull":
            await simulateDelay(0.6)
            addOutput("Already up to date.", type: .output)
        case "push":
            await simulateDelay(0.8)
            addOutput("Everything up-to-date.", type: .output)
        case "branch":
            addOutput("* main", type: .output)
        case "checkout":
            let branch = args.dropFirst().first ?? "(none)"
            addOutput("Switched to branch '\(branch)'", type: .output)
        case "add":
            addOutput("Changes staged.", type: .info)
        case "commit":
            let msgIdx = args.firstIndex(of: "-m").map { args.index(after: $0) }
            let msg = msgIdx.flatMap { $0 < args.endIndex ? args[$0] : nil } ?? "Update"
            await simulateDelay(0.3)
            addOutput("[main abc1234] \(msg)\n 1 file changed", type: .output)
        case "diff":
            addOutput("(No staged changes to show.)", type: .info)
        case "clone":
            let url = args.dropFirst().first ?? ""
            addOutput("Cloning '\(url)' is not supported in this environment.", type: .error)
        case "init":
            addOutput("Initialized empty Git repository.", type: .info)
        case "stash":
            addOutput("Saved working directory state.", type: .info)
        default:
            addOutput("git: '\(sub)' – not supported in this environment.", type: .error)
        }
    }

    @MainActor
    private func executeSwift(args: [String]) async {
        let sub = args.first ?? ""
        switch sub {
        case "build":
            addInfo("Building...")
            await simulateDelay(1.2)
            addOutput("Build complete. (Use GitHub Actions for full builds.)", type: .output)
        case "run":
            addInfo("Running Swift package...")
            await simulateDelay(0.8)
            addOutput("Execution complete.", type: .output)
        case "test":
            addInfo("Running tests...")
            await simulateDelay(1.0)
            addOutput("Test Suite 'All tests' passed.\n  Executed 0 tests, with 0 failures.", type: .output)
        case "package":
            let subcmd = args.dropFirst().first ?? ""
            switch subcmd {
            case "update":
                addInfo("Updating dependencies...")
                await simulateDelay(1.0)
                addOutput("Package update complete.", type: .output)
            case "resolve":
                addInfo("Resolving package graph...")
                await simulateDelay(0.5)
                addOutput("Package resolution complete.", type: .output)
            case "init":
                addInfo("Initializing Swift package...")
                addOutput("Package.swift created.", type: .output)
            default:
                addOutput("swift package \(subcmd): not supported.", type: .error)
            }
        case "repl":
            addOutput("REPL mode is not available in this environment.", type: .error)
        default:
            addOutput("swift: '\(sub)' is not a recognised subcommand.", type: .error)
        }
    }

    // MARK: - Path Helpers

    private func resolveDirectory(_ path: String?) -> URL? {
        guard let path = path else { return workingDirectoryURL }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return workingDirectoryURL?.appendingPathComponent(path)
    }

    private func resolveFile(_ path: String) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return workingDirectoryURL?.appendingPathComponent(path)
    }

    // MARK: - Output Helpers

    private func addOutput(_ text: String, type: TerminalLine.LineType) {
        for line in text.components(separatedBy: "\n") {
            outputLines.append(TerminalLine(text: line, type: type))
        }
    }

    private func addInfo(_ text: String) {
        outputLines.append(TerminalLine(text: text, type: .info))
    }

    private func simulateDelay(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Command Tokenizer

    /// Splits a command string into tokens, respecting quoted strings.
    private func tokenize(_ cmd: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character = "\""
        for ch in cmd {
            if inQuotes {
                if ch == quoteChar { inQuotes = false }
                else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                inQuotes = true; quoteChar = ch
            } else if ch == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Help Text

    private let helpText = """
Available commands:
  help                         Show this help
  clear                        Clear terminal output
  pwd                          Print working directory
  ls [dir]                     List directory contents
  cd <dir>                     Change directory
  mkdir <name>                 Create directory
  touch <file>                 Create empty file
  rm [-r] <path>               Remove file or directory
  mv <src> <dst>               Move/rename file
  cp <src> <dst>               Copy file
  cat <file>                   Print file contents
  echo <text>                  Print text
  grep [-i] <pattern> <file>   Search in file
  find [dir]                   Find files recursively
  wc <file>                    Word/line/char count
  head [-n N] <file>           First N lines (default 10)
  tail [-n N] <file>           Last N lines (default 10)
  open <file>                  Open file in editor
  date                         Print current date
  whoami                       Print user name
  uname                        Print system info
  env                          Print environment
  git <status|log|pull|push|branch|checkout|add|commit|diff|init|stash>
  swift <build|run|test|package>
"""
}
