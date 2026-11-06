import Foundation
import SwiftUI

// External MCP servers settings, adapted from Legacy's
// `SwiftCode/Views/Settings/AddMCPServerView.swift` and
// `AddedMCPServersView.swift` onto the config file the destination's
// MCP client actually reads: `~/.config/ycode/mcp-servers.json`
// (`{ "mcpServers": { "<name>": { "command": "…", "args": […] } } }`
// or `{ "url": "https://…" }`; see
// `YcodeMCP/YcodeTools+MCPClient.swift`, `externalMCPServers()`).
// This view reads and writes that same file with the same schema, so
// servers added here are the servers `use_mcp` connects to. No live
// connection is attempted from this view: the client tools own the
// stdio/HTTP exchange and the approval gate.

/// One external MCP server entry in the `mcp-servers.json` config file.
struct ExternalMCPServerEntry: Identifiable, Equatable, Hashable {
    var id: String { name }
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var url: String
    var headers: [String: String]
    var transport: String
}

/// List, add, edit and remove the external MCP servers in
/// `~/.config/ycode/mcp-servers.json`.
struct ExternalMCPServersView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var servers: [ExternalMCPServerEntry] = []
    @State private var selected: ExternalMCPServerEntry?
    @State private var draftName = ""
    @State private var draftTransport = "stdio"
    @State private var draftCommand = ""
    @State private var draftArgs = ""
    @State private var draftURL = ""
    @State private var draftEnv = ""
    @State private var showingAdd = false
    @State private var errorMessage: String?

    private var configURL: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("ycode").appendingPathComponent("mcp-servers.json")
    }

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("MCP Servers").font(ShellFonts.rowBold)
                Spacer()
                Button("Add Server") { beginAdd() }
                    .buttonStyle(.borderedProminent)
                Button("Refresh") { reload() }
            }
            .padding(10)
            Text(verbatim: "Config: \(configURL.path)")
                .font(ShellFonts.mini)
                .foregroundStyle(c.tertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            if let error = errorMessage {
                Text(verbatim: error)
                    .font(ShellFonts.small)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Hairline(color: c.separator)
            if servers.isEmpty {
                ContentUnavailableView(
                    "No MCP servers configured",
                    systemImage: "server.rack",
                    description: Text("Add a server to let the assistant call tools from an external MCP server. Each call still goes through the approval gate.")
                )
            } else {
                List(selection: $selected) {
                    ForEach(servers) { server in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: server.name).font(ShellFonts.rowBold)
                            Text(verbatim: server.transport == "http" || !server.url.isEmpty
                                 ? server.url : "\(server.command) \(server.args.joined(separator: " "))")
                                .font(ShellFonts.small)
                                .foregroundStyle(c.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(verbatim: server.transport)
                                .font(ShellFonts.mini)
                                .foregroundStyle(c.tertiaryLabel)
                        }
                        .tag(server)
                        .contextMenu {
                            Button("Delete Server", role: .destructive) { deleteServer(server) }
                        }
                    }
                }
                .listStyle(.plain)
            }
            if selected != nil {
                Hairline(color: c.separator)
                editForm(colors: c)
            }
        }
        .onAppear { reload() }
        .onChange(of: selected) { _, entry in
            guard let entry else { return }
            draftName = entry.name
            draftTransport = entry.transport
            draftCommand = entry.command
            draftArgs = entry.args.joined(separator: " ")
            draftURL = entry.url
            draftEnv = entry.env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
        }
        .sheet(isPresented: $showingAdd) {
            addSheet(colors: c)
        }
    }

    @ViewBuilder
    private func editForm(colors c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Server").font(ShellFonts.rowBold)
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            Picker("Transport", selection: $draftTransport) {
                Text("stdio").tag("stdio")
                Text("HTTP").tag("http")
            }
            .pickerStyle(.segmented)
            if draftTransport == "http" {
                TextField("Server URL (https://…)", text: $draftURL)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("Command (e.g. npx)", text: $draftCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Arguments (space separated)", text: $draftArgs)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Environment (one KEY=value per line)").font(ShellFonts.small).foregroundStyle(c.secondaryLabel)
            TextEditor(text: $draftEnv)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60)
                .border(c.fieldStroke)
            HStack {
                Button("Save") { saveEdit() }
                    .buttonStyle(.borderedProminent)
                Button("Delete", role: .destructive) {
                    if let selected { deleteServer(selected) }
                }
                Spacer()
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func addSheet(colors c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add MCP Server").font(ShellFonts.rowBold)
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            Picker("Transport", selection: $draftTransport) {
                Text("stdio").tag("stdio")
                Text("HTTP").tag("http")
            }
            .pickerStyle(.segmented)
            if draftTransport == "http" {
                TextField("Server URL (https://…)", text: $draftURL)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("Command (e.g. npx)", text: $draftCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Arguments (space separated)", text: $draftArgs)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Environment variables are edited after adding the server.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
            HStack {
                Spacer()
                Button("Cancel") { showingAdd = false }
                Button("Add") {
                    addServer()
                    showingAdd = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    // MARK: - Config file

    private func reload() {
        do {
            servers = try ExternalMCPServerEntry.load(from: configURL)
            errorMessage = nil
        } catch {
            servers = []
            errorMessage = "Could not read MCP config: \(error.localizedDescription)"
        }
        if let selected, !servers.contains(selected) {
            self.selected = nil
        }
    }

    private func persist() {
        do {
            try ExternalMCPServerEntry.save(servers, to: configURL)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save MCP config: \(error.localizedDescription)"
        }
    }

    private func beginAdd() {
        draftName = ""
        draftTransport = "stdio"
        draftCommand = ""
        draftArgs = ""
        draftURL = ""
        draftEnv = ""
        showingAdd = true
    }

    private func addServer() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !servers.contains(where: { $0.name == name }) else { return }
        let entry = ExternalMCPServerEntry(
            name: name,
            command: draftCommand.trimmingCharacters(in: .whitespaces),
            args: draftArgs.split(separator: " ").map(String.init),
            env: [:],
            url: draftURL.trimmingCharacters(in: .whitespaces),
            headers: [:],
            transport: draftTransport)
        servers.append(entry)
        servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        reload()
    }

    private func saveEdit() {
        guard let selected else { return }
        var env: [String: String] = [:]
        for line in draftEnv.components(separatedBy: .newlines) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...])
            if !key.isEmpty { env[key] = value }
        }
        let updated = ExternalMCPServerEntry(
            name: selected.name,
            command: draftCommand.trimmingCharacters(in: .whitespaces),
            args: draftArgs.split(separator: " ").map(String.init),
            env: env,
            url: draftURL.trimmingCharacters(in: .whitespaces),
            headers: selected.headers,
            transport: draftTransport)
        if let idx = servers.firstIndex(of: selected) {
            servers[idx] = updated
        }
        self.selected = updated
        persist()
        reload()
    }

    private func deleteServer(_ entry: ExternalMCPServerEntry) {
        servers.removeAll { $0 == entry }
        if selected == entry { selected = nil }
        persist()
        reload()
    }
}

extension ExternalMCPServerEntry {
    static func load(from url: URL) throws -> [ExternalMCPServerEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = root["mcpServers"] as? [String: Any] else {
            throw NSError(domain: "ExternalMCPServersView", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected {\"mcpServers\": {\"name\": {\"command\": \"…\", \"args\": […]} | {\"url\": \"https://…\"}}}"
            ])
        }
        var out: [ExternalMCPServerEntry] = []
        for (name, raw) in map {
            guard let cfg = raw as? [String: Any] else { continue }
            out.append(ExternalMCPServerEntry(
                name: name,
                command: cfg["command"] as? String ?? "",
                args: cfg["args"] as? [String] ?? [],
                env: cfg["env"] as? [String: String] ?? [:],
                url: cfg["url"] as? String ?? "",
                headers: cfg["headers"] as? [String: String] ?? [:],
                transport: cfg["transport"] as? String ?? ((cfg["url"] as? String) != nil ? "http" : "stdio")))
        }
        out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return out
    }

    static func save(_ servers: [ExternalMCPServerEntry], to url: URL) throws {
        var map: [String: Any] = [:]
        for server in servers {
            var cfg: [String: Any] = [:]
            if !server.command.isEmpty { cfg["command"] = server.command }
            if !server.args.isEmpty { cfg["args"] = server.args }
            if !server.env.isEmpty { cfg["env"] = server.env }
            if !server.url.isEmpty { cfg["url"] = server.url }
            if !server.headers.isEmpty { cfg["headers"] = server.headers }
            if !server.transport.isEmpty { cfg["transport"] = server.transport }
            map[server.name] = cfg
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["mcpServers": map], options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
