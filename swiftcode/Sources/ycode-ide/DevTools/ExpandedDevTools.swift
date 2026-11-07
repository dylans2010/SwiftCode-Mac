import SwiftUI
import YcodeUI
import YcodeIDECore
import YcodeBuild
import os.log
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Security)
import Security
#endif
#if canImport(OSLog)
import OSLog
#endif
#if canImport(ImageIO)
import ImageIO
#endif

private struct ModernCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundColor(color)
                    Spacer()
                }
                content
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}

private enum ExpandedDevToolsShell {
    static func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) async -> (status: Int32, stdout: String, stderr: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }
            process.standardInput = FileHandle.nullDevice
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            final class Box: @unchecked Sendable { var data = Data() }
            let errBox = Box()
            let group = DispatchGroup()
            group.enter()
            Thread {
                errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }.start()
            do {
                try process.run()
            } catch {
                group.wait()
                return (status: -1, stdout: "", stderr: error.localizedDescription)
            }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            return (status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errBox.data, as: UTF8.self))
        }.value
    }
}

private enum ExpandedDevToolsFiles {
    static let skippedDirectoryNames: Set<String> = [".git", ".build", "DerivedData", "Pods", ".swiftpm", "node_modules", ".hg", ".svn", "checkouts"]

    static func collectFiles(at root: URL, extensions: Set<String>?, maxCount: Int = 5000) -> [URL] {
        var result: [URL] = []
        collectFiles(at: root, extensions: extensions, maxCount: maxCount, into: &result)
        return result
    }

    private static func collectFiles(at url: URL, extensions: Set<String>?, maxCount: Int, into result: inout [URL]) {
        guard result.count < maxCount else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard result.count < maxCount else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if skippedDirectoryNames.contains(item.lastPathComponent) { continue }
                collectFiles(at: item, extensions: extensions, maxCount: maxCount, into: &result)
            } else if extensions == nil || extensions!.contains(item.pathExtension.lowercased()) {
                result.append(item)
            }
        }
    }

    static func collectDirectories(at root: URL, extension ext: String, maxCount: Int = 200) -> [URL] {
        var result: [URL] = []
        collectDirectories(at: root, extension: ext, maxCount: maxCount, into: &result)
        return result
    }

    private static func collectDirectories(at url: URL, extension ext: String, maxCount: Int, into result: inout [URL]) {
        guard result.count < maxCount else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard result.count < maxCount else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if skippedDirectoryNames.contains(item.lastPathComponent) { continue }
            if item.pathExtension.lowercased() == ext.lowercased() {
                result.append(item)
            } else {
                collectDirectories(at: item, extension: ext, maxCount: maxCount, into: &result)
            }
        }
    }

    static func firstXcodeproj(in root: URL) -> URL? {
        collectDirectories(at: root, extension: "xcodeproj", maxCount: 1).first
    }
}

private enum ExpandedDevToolsPbxproj {
    struct BuildConfiguration {
        let name: String
        let settings: [String: String]
    }

    static func buildConfigurations(pbxprojURL: URL) -> [BuildConfiguration] {
        guard let text = try? String(contentsOf: pbxprojURL, encoding: .utf8) else { return [] }
        return buildConfigurations(text: text)
    }

    static func buildConfigurations(text: String) -> [BuildConfiguration] {
        var configs: [BuildConfiguration] = []
        var searchFrom = text.startIndex
        while let marker = text.range(of: "buildSettings = {", range: searchFrom..<text.endIndex) {
            let openBrace = text.index(marker.upperBound, offsetBy: -1)
            var depth = 0
            var cursor = openBrace
            var blockEnd: String.Index?
            while cursor < text.endIndex {
                let ch = text[cursor]
                if ch == "{" { depth += 1 } else if ch == "}" {
                    depth -= 1
                    if depth == 0 { blockEnd = cursor; break }
                }
                cursor = text.index(after: cursor)
            }
            guard let end = blockEnd else { break }
            let block = String(text[text.index(after: openBrace)..<end])
            var settings: [String: String] = [:]
            let lines = block.components(separatedBy: "\n")
            var i = 0
            while i < lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                guard let eq = line.firstIndex(of: "=") else { i += 1; continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { i += 1; continue }
                var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                while value.hasPrefix("(") && !value.hasSuffix(");") && i + 1 < lines.count {
                    i += 1
                    value += " " + lines[i].trimmingCharacters(in: .whitespaces)
                }
                if value.hasSuffix(";") { value.removeLast() }
                value = value.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                settings[key] = value
                i += 1
            }
            var name = "Unnamed"
            let tailEnd = text.index(end, offsetBy: 400, limitedBy: text.endIndex) ?? text.endIndex
            let tail = String(text[end..<tailEnd])
            if let nameMarker = tail.range(of: "name = ") {
                let after = tail[nameMarker.upperBound...]
                let token = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." })
                if !token.isEmpty { name = String(token) }
            }
            configs.append(BuildConfiguration(name: name, settings: settings))
            searchFrom = end < text.index(before: text.endIndex) ? text.index(after: end) : text.endIndex
        }
        return configs
    }

    static func frameworkNames(text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z0-9_+\-\.]+)\.framework"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var names = Set<String>()
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text) {
                names.insert(String(text[r]) + ".framework")
            }
        }
        return names.sorted()
    }
}

struct ExpandedDevToolsSigningSetting: Identifiable {
    let id: String
    let value: String

    init(key: String, value: String) {
        self.id = key
        self.value = value
    }

    var key: String { id }
}
struct ExpandedDevToolsSigningIdentity: Identifiable {
    let id: String
    let name: String

    static func parseFindIdentity(_ output: String) -> [ExpandedDevToolsSigningIdentity] {
        var identities: [ExpandedDevToolsSigningIdentity] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let closeParen = trimmed.firstIndex(of: ")") else { continue }
            let rest = trimmed[trimmed.index(after: closeParen)...].trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0])
            guard hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var name = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            identities.append(ExpandedDevToolsSigningIdentity(id: hash, name: name))
        }
        return identities
    }
}

#if canImport(AppKit)
private enum ExpandedDevToolsPicker {
    static func pickFile(allowedTypes: [String], canChooseDirectories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = !canChooseDirectories
        panel.allowedFileTypes = allowedTypes
        return panel.runModal() == .OK ? panel.url : nil
    }
}
#endif

struct EntitlementInspectorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var entitlementsContent = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Active Entitlements", icon: "shield.fill", color: .green) {
                    if entitlementsContent.isEmpty {
                        Text("No active entitlements file resolved. Use the editor to define custom sandbox permissions.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        Text(entitlementsContent)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Entitlement Inspector")
        .onAppear {
            if let project = sessionStore.activeProject,
               let url = ProjectResolutionService.shared.resolveEntitlements(for: project) {
                entitlementsContent = (try? String(contentsOf: url)) ?? ""
            }
        }
    }
}

struct ExpandedDevToolsProvisioningProfile: Identifiable {
    let id: String
    let name: String
    let appID: String
    let teamID: String
    let expiration: Date?

    var isExpired: Bool { expiration.map { $0 < Date() } ?? false }
}

struct ProvisioningProfileViewerView: View {
    @State private var profiles: [ExpandedDevToolsProvisioningProfile] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Provisioning Profiles", icon: "key.fill", color: .blue) {
                    if isLoading {
                        ProgressView("Reading provisioning profiles…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if profiles.isEmpty {
                        Text("No provisioning profiles found in ~/Library/MobileDevice/Provisioning Profiles.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profiles) { profile in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: profile.isExpired ? "xmark.seal.fill" : "checkmark.seal.fill")
                                        .foregroundColor(profile.isExpired ? .red : .green)
                                    Text(profile.name).font(.body)
                                    Spacer()
                                    Text(profile.isExpired ? "Expired" : "Active")
                                        .font(.caption)
                                        .foregroundColor(profile.isExpired ? .red : .green)
                                }
                                Text("App ID: \(profile.appID)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Team: \(profile.teamID) • Expires: \(profile.expiration?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Provisioning Profile Viewer")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            profiles = []
            return
        }
        var loaded: [ExpandedDevToolsProvisioningProfile] = []
        for url in urls where url.pathExtension == "mobileprovision" {
            let result = await ExpandedDevToolsShell.run("/usr/bin/security", ["cms", "-D", "-i", url.path])
            guard result.status == 0,
                  let plist = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil) as? [String: Any] else { continue }
            let name = plist["Name"] as? String ?? url.deletingPathExtension().lastPathComponent
            let uuid = plist["UUID"] as? String ?? url.lastPathComponent
            let team = (plist["TeamIdentifier"] as? [String])?.first ?? "—"
            let appID = (plist["Entitlements"] as? [String: Any])?["application-identifier"] as? String ?? "—"
            let expiration = plist["ExpirationDate"] as? Date
            loaded.append(ExpandedDevToolsProvisioningProfile(id: uuid, name: name, appID: appID, teamID: team, expiration: expiration))
        }
        profiles = loaded.sorted { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
    }
}

struct BundleIdentifierEditorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var bundleID = "com.example.app"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Bundle Configuration", icon: "barcode", color: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active Target Bundle Identifier")
                            .font(.subheadline)
                        TextField("com.example.app", text: $bundleID)
                            .textFieldStyle(.roundedBorder)

                        Button("Apply Bundle ID") {
                            if let project = sessionStore.activeProject {
                                var config = project.ciBuildConfiguration ?? CIBuildConfiguration()
                                config.bundleIdentifier = bundleID
                                sessionStore.updateCIBuildConfiguration(config, for: project)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Bundle Identifier Editor")
        .onAppear {
            if let project = sessionStore.activeProject {
                bundleID = project.ciBuildConfiguration?.bundleIdentifier ?? "com.example.app"
            }
        }
    }
}

struct BuildSettingsExplorerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var configurations: [ExpandedDevToolsPbxproj.BuildConfiguration] = []
    @State private var selectedConfigName: String?
    @State private var isLoading = false
    @State private var statusMessage: String?

    private var selectedConfig: ExpandedDevToolsPbxproj.BuildConfiguration? {
        configurations.first { $0.name == selectedConfigName } ?? configurations.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "PBXBuildConfiguration Settings", icon: "gearshape.fill", color: .indigo) {
                    if isLoading {
                        ProgressView("Reading project.pbxproj…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if let config = selectedConfig {
                        if configurations.count > 1 {
                            Picker("Configuration", selection: Binding(
                                get: { selectedConfigName ?? config.name },
                                set: { selectedConfigName = $0 }
                            )) {
                                ForEach(configurations, id: \.name) { c in Text(c.name).tag(c.name) }
                            }
                            .pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(config.settings.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text(key).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text(config.settings[key] ?? "").bold()
                                }
                                Divider()
                            }
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Build Settings Explorer")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            configurations = []
            return
        }
        let parsed = await Task.detached(priority: .userInitiated) { () -> [ExpandedDevToolsPbxproj.BuildConfiguration] in
            guard let xcodeproj = ExpandedDevToolsFiles.firstXcodeproj(in: root) else { return [] }
            return ExpandedDevToolsPbxproj.buildConfigurations(pbxprojURL: xcodeproj.appendingPathComponent("project.pbxproj"))
        }.value
        configurations = parsed
        if parsed.isEmpty {
            statusMessage = "No .xcodeproj with build configurations found in this project."
        } else if selectedConfigName == nil {
            selectedConfigName = parsed.first?.name
        }
    }
}

struct XCConfigViewerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var content = ""
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Active .xcconfig Settings", icon: "doc.text.fill", color: .purple) {
                    if isLoading {
                        ProgressView("Searching for .xcconfig files…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if files.isEmpty {
                        Text("No .xcconfig files found in this project.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("File", selection: $selectedFile) {
                            ForEach(files, id: \.self) { file in
                                Text(file.lastPathComponent).tag(Optional(file))
                            }
                        }
                        .pickerStyle(.menu)
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("XCConfig Viewer")
        .task { await load() }
        .onChange(of: selectedFile) { _, newValue in
            if let newValue {
                content = (try? String(contentsOf: newValue, encoding: .utf8)) ?? "Could not read \(newValue.lastPathComponent)."
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            files = []
            return
        }
        let found = await Task.detached(priority: .userInitiated) {
            ExpandedDevToolsFiles.collectFiles(at: root, extensions: ["xcconfig"])
        }.value
        files = found
        if let first = found.first {
            selectedFile = first
            content = (try? String(contentsOf: first, encoding: .utf8)) ?? ""
        }
    }
}

struct SigningInspectorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var identities: [ExpandedDevToolsSigningIdentity] = []
    @State private var projectSettings: [ExpandedDevToolsSigningSetting] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    private static let signingKeys: Set<String> = ["CODE_SIGN_STYLE", "DEVELOPMENT_TEAM", "CODE_SIGN_IDENTITY", "PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGN_ENTITLEMENTS"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Code Signing Details", icon: "lock.shield.fill", color: .green) {
                    if isLoading {
                        ProgressView("Reading signing identities…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Installed Signing Identities").font(.subheadline.bold())
                            if identities.isEmpty {
                                Text("No code signing identities found on this Mac.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(identities) { identity in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(identity.name).font(.body)
                                        Text(identity.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Divider()
                                }
                            }
                            Text("Project Signing Settings").font(.subheadline.bold())
                            if projectSettings.isEmpty {
                                Text("No CODE_SIGN_* settings found in the project's project.pbxproj.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(projectSettings) { entry in
                                    LabeledContent(entry.key, value: entry.value)
                                }
                            }
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Signing Inspector")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let result = await ExpandedDevToolsShell.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        if result.status != 0 {
            statusMessage = "Could not list signing identities: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            return
        }
        identities = ExpandedDevToolsSigningIdentity.parseFindIdentity(result.stdout)
        guard let root = sessionStore.activeProject?.directoryURL else {
            projectSettings = []
            return
        }
        let configs = await Task.detached(priority: .userInitiated) { () -> [ExpandedDevToolsPbxproj.BuildConfiguration] in
            guard let xcodeproj = ExpandedDevToolsFiles.firstXcodeproj(in: root) else { return [] }
            return ExpandedDevToolsPbxproj.buildConfigurations(pbxprojURL: xcodeproj.appendingPathComponent("project.pbxproj"))
        }.value
        var merged: [String: String] = [:]
        for config in configs {
            for (key, value) in config.settings where Self.signingKeys.contains(key) {
                merged[key] = value
            }
        }
        projectSettings = merged.keys.sorted().map { ExpandedDevToolsSigningSetting(key: $0, value: merged[$0] ?? "") }
    }
}

struct ExpandedDevToolsSymbol: Identifiable {
    let id = UUID()
    let kind: String
    let name: String
    let file: String
    let line: Int
}

struct ExpandedDevToolsSymbolCount: Identifiable {
    let id: String
    let count: Int

    var kind: String { id }
}

struct SymbolBrowserView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var symbols: [ExpandedDevToolsSymbol] = []
    @State private var counts: [ExpandedDevToolsSymbolCount] = []
    @State private var isTruncated = false
    @State private var isLoading = false
    @State private var statusMessage: String?

    private static let declarationPattern = #"^\s*(?:(?:public|private|fileprivate|internal|open|final|override|static|lazy|required|convenience|indirect|nonisolated|isolated|mutating|nonmutating|async)\s+){0,6}(class|struct|enum|protocol|actor|extension|func|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"#

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Source Code Symbols", icon: "list.bullet.indent", color: .blue) {
                    if isLoading {
                        ProgressView("Scanning Swift sources…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if symbols.isEmpty {
                        Text("No symbols found in this project.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 16) {
                            ForEach(counts) { entry in
                                Text("\(entry.kind): \(entry.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        List(symbols, id: \.id) { symbol in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(symbol.kind) \(symbol.name)")
                                    .font(.system(.body, design: .monospaced))
                                Text("\(symbol.file):\(symbol.line)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 300)
                        if isTruncated {
                            Text("Showing the first 200 symbols.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Symbol Browser")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            symbols = []
            return
        }
        let pattern = Self.declarationPattern
        let found = await Task.detached(priority: .userInitiated) { () -> (symbols: [ExpandedDevToolsSymbol], truncated: Bool) in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return ([], false) }
            var all: [ExpandedDevToolsSymbol] = []
            let files = ExpandedDevToolsFiles.collectFiles(at: root, extensions: ["swift"], maxCount: 1000)
            for url in files {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                let lines = text.components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                          match.numberOfRanges == 3,
                          let kindRange = Range(match.range(at: 1), in: line),
                          let nameRange = Range(match.range(at: 2), in: line) else { continue }
                    all.append(ExpandedDevToolsSymbol(kind: String(line[kindRange]), name: String(line[nameRange]), file: relative, line: index + 1))
                }
            }
            let truncated = all.count > 200
            return (Array(all.prefix(200)), truncated)
        }.value
        symbols = found.symbols
        isTruncated = found.truncated
        var totals: [String: Int] = [:]
        for symbol in found.symbols { totals[symbol.kind, default: 0] += 1 }
        counts = totals.keys.sorted().map { ExpandedDevToolsSymbolCount(id: $0, count: totals[$0] ?? 0) }
    }
}

struct ExpandedDevToolsAssetEntry: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let catalog: String
}

struct AssetCatalogBrowserView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var assets: [ExpandedDevToolsAssetEntry] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    private static func kind(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "appiconset": return "App Icon"
        case "imageset": return "Image Set"
        case "colorset": return "Color Set"
        case "dataset": return "Data Set"
        case "symbolset": return "Symbol Set"
        default: return "Catalog Item"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "XCAssets Catalog", icon: "photo.stack", color: .teal) {
                    if isLoading {
                        ProgressView("Enumerating asset catalogs…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if assets.isEmpty {
                        Text("No asset catalogs found in this project.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                            ForEach(assets) { asset in
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.title)
                                        .padding()
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(8)
                                    Text(asset.name)
                                        .font(.caption)
                                    Text(asset.kind)
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(asset.catalog)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Asset Catalog Browser")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            assets = []
            return
        }
        let found = await Task.detached(priority: .userInitiated) { () -> [ExpandedDevToolsAssetEntry] in
            var entries: [ExpandedDevToolsAssetEntry] = []
            for catalog in ExpandedDevToolsFiles.collectDirectories(at: root, extension: "xcassets") {
                guard let items = try? FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    let ext = item.pathExtension
                    guard ["appiconset", "imageset", "colorset", "dataset", "symbolset"].contains(ext.lowercased()) else { continue }
                    entries.append(ExpandedDevToolsAssetEntry(
                        name: item.deletingPathExtension().lastPathComponent,
                        kind: Self.kind(for: ext),
                        catalog: catalog.lastPathComponent))
                }
            }
            return entries
        }.value
        assets = found
    }
}

struct ExpandedDevToolsLocalizationFile: Identifiable {
    let id = UUID()
    let displayName: String
    let entryCount: Int
}

struct LocalizationExplorerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var localizedFiles: [ExpandedDevToolsLocalizationFile] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Active Localizations", icon: "globe", color: .orange) {
                    if isLoading {
                        ProgressView("Enumerating localizations…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if localizedFiles.isEmpty {
                        Text("No .lproj directories or .strings files found in this project.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(localizedFiles, id: \.id) { file in
                            HStack {
                                Text(file.displayName)
                                Spacer()
                                Text("\(file.entryCount) entries")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 250)
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Localization Explorer")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            localizedFiles = []
            return
        }
        let found = await Task.detached(priority: .userInitiated) { () -> [ExpandedDevToolsLocalizationFile] in
            var entries: [ExpandedDevToolsLocalizationFile] = []
            for lproj in ExpandedDevToolsFiles.collectDirectories(at: root, extension: "lproj") {
                guard let items = try? FileManager.default.contentsOfDirectory(at: lproj, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for item in items where item.pathExtension.lowercased() == "strings" {
                    entries.append(ExpandedDevToolsLocalizationFile(
                        displayName: "\(lproj.lastPathComponent)/\(item.lastPathComponent)",
                        entryCount: Self.entryCount(of: item)))
                }
            }
            for stringsFile in ExpandedDevToolsFiles.collectFiles(at: root, extensions: ["strings"]) {
                guard !stringsFile.path.contains(".lproj/") else { continue }
                let relative = stringsFile.path.replacingOccurrences(of: root.path + "/", with: "")
                entries.append(ExpandedDevToolsLocalizationFile(displayName: relative, entryCount: Self.entryCount(of: stringsFile)))
            }
            return entries.sorted { $0.displayName < $1.displayName }
        }.value
        localizedFiles = found
    }

    private static func entryCount(of url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("\"") && trimmed.contains("\" = \"")
        }.count
    }
}

struct ExpandedDevToolsPlistRow: Identifiable {
    let id = UUID()
    let key: String
    var value: String
    let isEditable: Bool
}

struct InfoPlistEditorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var rows: [ExpandedDevToolsPlistRow] = []
    @State private var originalPlist: [String: Any] = [:]
    @State private var plistURL: URL?
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Info.plist Editor Keys", icon: "list.bullet.rectangle", color: .red) {
                    if isLoading {
                        ProgressView("Resolving Info.plist…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else {
                        if let plistURL {
                            Text(plistURL.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rows.indices, id: \.self) { index in
                                HStack {
                                    Text(rows[index].key).font(.subheadline.bold())
                                    Spacer()
                                    if rows[index].isEditable {
                                        TextField("Value", text: $rows[index].value)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 200)
                                    } else {
                                        Text(rows[index].value).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        Button("Save Info.plist") { save() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        if let saveMessage {
                            Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Info.plist Editor")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        saveMessage = nil
        guard let project = sessionStore.activeProject else {
            statusMessage = "No project open."
            rows = []
            return
        }
        guard let url = ProjectResolutionService.shared.resolveInfoPlist(for: project) else {
            statusMessage = "No Info.plist resolved for this project."
            rows = []
            return
        }
        plistURL = url
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            statusMessage = "Could not parse \(url.lastPathComponent) as a property list."
            rows = []
            return
        }
        originalPlist = plist
        rows = plist.keys.sorted().map { key in
            let value = plist[key]
            if let string = value as? String {
                return ExpandedDevToolsPlistRow(key: key, value: string, isEditable: true)
            }
            return ExpandedDevToolsPlistRow(key: key, value: String(describing: value ?? ""), isEditable: false)
        }
    }

    private func save() {
        guard let url = plistURL else { return }
        var updated = originalPlist
        for row in rows where row.isEditable {
            updated[row.key] = row.value
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            originalPlist = updated
            saveMessage = "Saved to \(url.lastPathComponent)."
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

struct ExpandedDevToolsPackagePin: Identifiable {
    let id: String
    let version: String
    let location: String
}

struct PackageDependencyExplorerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var packages: [ExpandedDevToolsPackagePin] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Integrated Package dependencies", icon: "shippingbox.fill", color: .blue) {
                    if isLoading {
                        ProgressView("Reading Package.resolved…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if packages.isEmpty {
                        Text("No packages pinned — no Package.resolved found, or it pins nothing.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(packages, id: \.id) { pkg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(pkg.id) — \(pkg.version)")
                                    .font(.body)
                                Text(pkg.location)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 200)
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Package Dependency Explorer")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            packages = []
            return
        }
        let found = await Task.detached(priority: .userInitiated) { () -> [ExpandedDevToolsPackagePin] in
            var candidates: [URL] = [root.appendingPathComponent("Package.resolved")]
            for xcodeproj in ExpandedDevToolsFiles.collectDirectories(at: root, extension: "xcodeproj") {
                candidates.append(PackageResolver.resolvedFileURL(xcodeprojURL: xcodeproj))
            }
            let resolver = PackageResolver(checkoutsDirectory: FileManager.default.temporaryDirectory)
            for url in candidates {
                if let pins = resolver.readResolvedFile(url) {
                    return pins.map { pin in
                        let version = pin.version ?? pin.branch ?? "revision \(String(pin.revision.prefix(7)))"
                        return ExpandedDevToolsPackagePin(id: pin.identity, version: version, location: pin.location)
                    }
                }
            }
            return []
        }.value
        packages = found
        if found.isEmpty {
            statusMessage = "No Package.resolved found in this project. Resolve the package dependencies first."
        }
    }
}

struct SPMInspectorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var swiftVersion = ""
    @State private var pinCount: Int?
    @State private var cacheSize: String?
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Swift Package Manager Diagnostics", icon: "shippingbox.circle", color: .purple) {
                    if isLoading {
                        ProgressView("Querying SwiftPM…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Swift toolchain", value: swiftVersion.isEmpty ? "Unavailable" : swiftVersion)
                            LabeledContent("Resolved packages", value: pinCount.map { "\($0)" } ?? "No Package.resolved")
                            LabeledContent("Build cache path", value: "~/.swiftpm/cache")
                            LabeledContent("Build cache size", value: cacheSize ?? "Unavailable")
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("SPM Inspector")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let result = await ExpandedDevToolsShell.run("/usr/bin/env", ["swift", "--version"])
        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        swiftVersion = combined.components(separatedBy: "\n").first ?? ""
        if result.status != 0 {
            statusMessage = "Could not run `swift --version`: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            return
        }
        let cacheURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swiftpm/cache")
        let projectRoot = sessionStore.activeProject?.directoryURL
        let (pins, size) = await Task.detached(priority: .userInitiated) { () -> (Int?, String?) in
            var pinCount: Int?
            if let root = projectRoot {
                var candidates: [URL] = [root.appendingPathComponent("Package.resolved")]
                for xcodeproj in ExpandedDevToolsFiles.collectDirectories(at: root, extension: "xcodeproj") {
                    candidates.append(PackageResolver.resolvedFileURL(xcodeprojURL: xcodeproj))
                }
                let resolver = PackageResolver(checkoutsDirectory: FileManager.default.temporaryDirectory)
                for url in candidates {
                    if let pins = resolver.readResolvedFile(url) { pinCount = pins.count; break }
                }
            }
            let size: String?
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                size = DevToolsDiskUsage.allocatedSize(of: cacheURL).map { DevToolsDiskUsage.formatted($0) } ?? "0 bytes"
            } else {
                size = "Cache directory does not exist"
            }
            return (pinCount, size)
        }.value
        pinCount = pins
        cacheSize = size
    }
}

struct BinarySizeAnalyzerView: View {
    @State private var selectedBundleURL: URL?
    @State private var breakdown: AppBundleSizeBreakdown?
    @State private var isMeasuring = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Binary Size Analysis", icon: "chart.pie.fill", color: .pink) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let bundleURL = selectedBundleURL {
                            Text(bundleURL.lastPathComponent)
                                .font(.subheadline.bold())
                            Text(bundleURL.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("No bundle selected. Pick an .app bundle to measure it on disk.")
                                .foregroundStyle(.secondary)
                        }
                        if isMeasuring {
                            ProgressView("Measuring bundle…")
                        } else if let breakdown {
                            ForEach(breakdown.categories.indices, id: \.self) { index in
                                let category = breakdown.categories[index]
                                HStack {
                                    Text(category.label)
                                    Spacer()
                                    Text(DevToolsDiskUsage.formatted(category.bytes))
                                }
                            }
                            Divider()
                            HStack {
                                Text("Total App Bundle")
                                Spacer()
                                Text(DevToolsDiskUsage.formatted(breakdown.totalBytes)).bold()
                            }
                        }
#if canImport(AppKit)
                        Button(selectedBundleURL == nil ? "Select .app Bundle…" : "Select a Different Bundle…") {
                            if let url = ExpandedDevToolsPicker.pickFile(allowedTypes: ["app"], canChooseDirectories: true) {
                                selectedBundleURL = url
                                Task { await measure(url) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
#else
                        Text("Bundle picking requires macOS (AppKit).")
                            .foregroundStyle(.secondary)
#endif
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Binary Size Analyzer")
    }

    private func measure(_ bundle: URL) async {
        isMeasuring = true
        defer { isMeasuring = false }
        breakdown = await Task.detached(priority: .userInitiated) {
            AppBundleSizeBreakdown.measure(bundle: bundle)
        }.value
    }
}

struct FrameworkInspectorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var frameworks: [String] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Linked Frameworks", icon: "square.stack.3d.up.fill", color: .blue) {
                    if isLoading {
                        ProgressView("Reading project.pbxproj…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if frameworks.isEmpty {
                        Text("No frameworks referenced in this project's project.pbxproj.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(frameworks, id: \.self) { fw in
                            Text("📦 " + fw)
                        }
                        .frame(height: 250)
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Framework Inspector")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            frameworks = []
            return
        }
        let found = await Task.detached(priority: .userInitiated) { () -> [String] in
            guard let xcodeproj = ExpandedDevToolsFiles.firstXcodeproj(in: root),
                  let text = try? String(contentsOf: xcodeproj.appendingPathComponent("project.pbxproj"), encoding: .utf8) else { return [] }
            return ExpandedDevToolsPbxproj.frameworkNames(text: text)
        }.value
        frameworks = found
        if found.isEmpty {
            statusMessage = "No .xcodeproj found, or no frameworks referenced in this project."
        }
    }
}

struct ExpandedDevToolsCrashLog: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let modified: Date
}

struct CrashLogViewerView: View {
    @State private var logs: [ExpandedDevToolsCrashLog] = []
    @State private var selectedLog: ExpandedDevToolsCrashLog?
    @State private var logContent = ""
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Crashed Stacktrace Log", icon: "ant.fill", color: .red) {
                    if isLoading {
                        ProgressView("Listing crash logs…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if logs.isEmpty {
                        Text("No crash logs found in ~/Library/Logs/DiagnosticReports.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Crash log", selection: $selectedLog) {
                            ForEach(logs) { log in
                                Text("\(log.name) — \(log.modified.formatted(date: .abbreviated, time: .short))").tag(Optional(log))
                            }
                        }
                        .pickerStyle(.menu)
                        if !logContent.isEmpty {
                            Text(logContent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Crash Log Viewer")
        .task { await load() }
        .onChange(of: selectedLog) { _, newValue in
            if let newValue {
                Task { await loadContent(of: newValue) }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        let found = await Task.detached(priority: .userInitiated) { () -> [ExpandedDevToolsCrashLog] in
            guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
            let entries = urls.compactMap { url -> ExpandedDevToolsCrashLog? in
                guard ["ips", "crash"].contains(url.pathExtension.lowercased()) else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return ExpandedDevToolsCrashLog(url: url, name: url.lastPathComponent, modified: modified)
            }
            return Array(entries.sorted { $0.modified > $1.modified }.prefix(50))
        }.value
        logs = found
        if let first = found.first {
            selectedLog = first
            await loadContent(of: first)
        }
    }

    private func loadContent(of log: ExpandedDevToolsCrashLog) async {
        logContent = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: log.url) else { return "Could not read \(log.name)." }
            let text = String(decoding: data.prefix(200_000), as: UTF8.self)
            return data.count > 200_000 ? text + "\n… (truncated at 200 KB)" : text
        }.value
    }
}

struct ConsoleViewerView: View {
    @State private var logger = DeveloperLogStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Console stdout stream", icon: "terminal.fill", color: .gray) {
                    if logger.logs.isEmpty {
                        Text("No log entries recorded yet. Entries appear here when this process logs them.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(logger.logs) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(entry.category.rawValue)] \(entry.message)")
                                    .font(.system(.body, design: .monospaced))
                                Text(entry.timestamp.formatted(date: .omitted, time: .medium))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 300)
                        Button("Clear Logs") { logger.clearLogs() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Console Viewer")
    }
}

struct ExpandedDevToolsOSLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let message: String
}

struct DeviceLogViewerView: View {
    @State private var logs: [ExpandedDevToolsOSLogEntry] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Streaming Device Log", icon: "macbook.and.iphone", color: .orange) {
#if canImport(OSLog)
                    if isLoading {
                        ProgressView("Reading system log…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if logs.isEmpty {
                        Text("No system log entries for this process in the last 15 minutes.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("System log entries for this process on this Mac (last 15 minutes).")
                            .font(.caption).foregroundStyle(.secondary)
                        List(logs) { log in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.message)
                                    .font(.system(.body, design: .monospaced))
                                Text("\(log.date.formatted(date: .omitted, time: .medium)) • \(log.category)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 300)
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
#else
                    Text("Device log streaming requires macOS (OSLogStore is unavailable on this platform).")
                        .foregroundStyle(.secondary)
#endif
                }
            }
            .padding()
        }
        .navigationTitle("Device Log Viewer")
#if canImport(OSLog)
        .task { await load() }
#endif
    }

#if canImport(OSLog)
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let entries = await Task.detached(priority: .userInitiated) { () -> Result<[ExpandedDevToolsOSLogEntry], Error> in
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let position = store.position(date: Date().addingTimeInterval(-900))
                var collected: [ExpandedDevToolsOSLogEntry] = []
                for entry in try store.getEntries(at: position) {
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    collected.append(ExpandedDevToolsOSLogEntry(date: logEntry.date, category: logEntry.category, message: logEntry.composedMessage))
                    if collected.count >= 100 { break }
                }
                return .success(collected)
            } catch {
                return .failure(error)
            }
        }.value
        switch entries {
        case .success(let loaded):
            logs = loaded
        case .failure(let error):
            statusMessage = "Could not read the system log: \(error.localizedDescription)"
            logs = []
        }
    }
#endif
}

struct SimulatorManagerView: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "iOS Simulators Status", icon: "iphone.circle", color: .blue) {
                    if manager.devices.isEmpty {
                        Text("No simulators found. Refresh to reload from simctl, or install a runtime.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(manager.devices) { sim in
                            HStack {
                                Image(systemName: "play.fill")
                                    .foregroundColor(sim.state.isRunning ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sim.name)
                                    Text("\(sim.platform) \(sim.osVersion) — \(sim.state.rawValue)\(sim.isAvailable ? "" : " (Unavailable)")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 250)
                    }
                    Button("Refresh") {
                        Task { await manager.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.isRefreshing)
                }
            }
            .padding()
        }
        .navigationTitle("Simulator Manager")
    }
}

struct CertificateManagerView: View {
    @State private var certificates: [ExpandedDevToolsSigningIdentity] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Developer Certificates", icon: "checkmark.seal.fill", color: .green) {
                    if isLoading {
                        ProgressView("Reading certificates…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if certificates.isEmpty {
                        Text("No code signing identities found on this Mac.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(certificates) { cert in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cert.name)
                                Text(cert.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 200)
                        Text("Expiry dates are not reported by `security find-identity` and are not shown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Certificate Manager")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let result = await ExpandedDevToolsShell.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        if result.status != 0 {
            statusMessage = "Could not list signing identities: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            return
        }
        certificates = ExpandedDevToolsSigningIdentity.parseFindIdentity(result.stdout)
    }
}

struct ExpandedDevToolsKeychainItem: Identifiable {
    let id = UUID()
    let service: String
    let account: String
}

struct KeychainInspectorView: View {
    @State private var keychainItems: [ExpandedDevToolsKeychainItem] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Secure Keychain items catalog", icon: "key.fill", color: .yellow) {
#if canImport(Security)
                    if isLoading {
                        ProgressView("Querying keychain…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if keychainItems.isEmpty {
                        Text("No generic-password items found in the keychain.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(keychainItems) { item in
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.service)
                                    Text(item.account)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 250)
                    }
                    Text("Item names only — secret values are never read or displayed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
#else
                    Text("Keychain inspection requires macOS (Security framework is unavailable on this platform).")
                        .foregroundStyle(.secondary)
#endif
                }
            }
            .padding()
        }
        .navigationTitle("Keychain Inspector")
#if canImport(Security)
        .task { await load() }
#endif
    }

#if canImport(Security)
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[ExpandedDevToolsKeychainItem], String> in
            var result: CFTypeRef?
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
            ]
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                return .success([])
            }
            guard status == errSecSuccess else {
                return .failure("Keychain query failed (OSStatus \(status)).")
            }
            guard let array = result as? [[String: Any]] else {
                return .success([])
            }
            let items = array.map { dict in
                ExpandedDevToolsKeychainItem(
                    service: dict[kSecAttrService as String] as? String ?? "—",
                    account: dict[kSecAttrAccount as String] as? String ?? "—")
            }
            return .success(items.sorted { $0.service < $1.service })
        }.value
        switch outcome {
        case .success(let items):
            keychainItems = items
        case .failure(let message):
            statusMessage = message
            keychainItems = []
        }
    }
#endif
}

private struct ExpandedDevToolsCacheState {
    static func directorySizeLabel(for url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return DevToolsDiskUsage.allocatedSize(of: url).map { DevToolsDiskUsage.formatted($0) } ?? "0 bytes"
    }
}

struct BuildCacheManagerView: View {
    @State private var cacheSize: String?
    @State private var isWorking = false
    @State private var statusMessage: String?

    private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swiftpm/cache")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Xcodebuild cache diagnostics", icon: "folder.fill", color: .gray) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Current Cache Size")
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(cacheSize ?? "Cache directory does not exist").bold()
                            }
                        }
                        if let statusMessage {
                            Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Purge Build Cache") { Task { await purge() } }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(isWorking)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Build Cache Manager")
        .task { await rescan() }
    }

    private func rescan() async {
        isWorking = true
        defer { isWorking = false }
        cacheSize = await Task.detached(priority: .userInitiated) {
            ExpandedDevToolsCacheState.directorySizeLabel(for: Self.cacheURL)
        }.value
    }

    private func purge() async {
        isWorking = true
        defer { isWorking = false }
        let before = cacheSize
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try FileManager.default.removeItem(at: Self.cacheURL)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success:
            statusMessage = "Purged the SwiftPM cache (\(before ?? "unknown size"))."
        case .failure(let error):
            statusMessage = "Purge failed: \(error.localizedDescription)"
        }
        await rescan()
    }
}

struct DerivedDataManagerView: View {
    @State private var size: String?
    @State private var isWorking = false
    @State private var statusMessage: String?

    private static var derivedDataURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "DerivedData Directory Inspector", icon: "trash.fill", color: .red) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("DerivedData Storage")
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(size ?? "DerivedData directory does not exist").bold()
                            }
                        }
                        if let statusMessage {
                            Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Clean DerivedData") { Task { await clean() } }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(isWorking)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Derived Data Manager")
        .task { await rescan() }
    }

    private func rescan() async {
        isWorking = true
        defer { isWorking = false }
        size = await Task.detached(priority: .userInitiated) {
            ExpandedDevToolsCacheState.directorySizeLabel(for: Self.derivedDataURL)
        }.value
    }

    private func clean() async {
        isWorking = true
        defer { isWorking = false }
        let before = size
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try FileManager.default.removeItem(at: Self.derivedDataURL)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success:
            statusMessage = "Removed DerivedData (\(before ?? "unknown size"))."
        case .failure(let error):
            statusMessage = "Clean failed: \(error.localizedDescription)"
        }
        await rescan()
    }
}

struct ExpandedDevToolsEnvVar: Identifiable {
    let id: String
    var value: String
}

struct EnvVarEditorView: View {
    @State private var variables: [ExpandedDevToolsEnvVar] = []
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Process Environment Variables", icon: "chevron.left.forwardslash.chevron.right", color: .purple) {
                    VStack(alignment: .leading, spacing: 10) {
                        if variables.isEmpty {
                            Text("No environment variables in this process.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(variables.count) variables. Editing a value calls setenv(3) on this process.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(variables.indices, id: \.self) { index in
                                HStack {
                                    Text(variables[index].id).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    TextField("Value", text: $variables[index].value)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 260)
                                        .onSubmit { apply(variables[index]) }
                                }
                            }
                        }
                        if let statusMessage {
                            Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Refresh") { reload() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Environment Variables")
        .onAppear { reload() }
    }

    private func reload() {
        variables = ProcessInfo.processInfo.environment
            .sorted { $0.key < $1.key }
            .map { ExpandedDevToolsEnvVar(id: $0.key, value: $0.value) }
    }

    private func apply(_ variable: ExpandedDevToolsEnvVar) {
        if setenv(variable.id, variable.value, 1) == 0 {
            statusMessage = "Set \(variable.id) in this process."
            reload()
        } else {
            statusMessage = "Could not set \(variable.id)."
        }
    }
}

struct CodeMetricsView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var swiftFileCount: Int?
    @State private var totalLines: Int?
    @State private var nonBlankLines: Int?
    @State private var testFileCount: Int?
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Workspace Code Metrics", icon: "chart.xyaxis.line", color: .orange) {
                    if isLoading {
                        ProgressView("Counting workspace sources…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Lines of Code (LOC)", value: totalLines.map { "\($0) lines" } ?? "—")
                            LabeledContent("Non-Blank Lines", value: nonBlankLines.map { "\($0) lines" } ?? "—")
                            LabeledContent("Swift Files", value: swiftFileCount.map { "\($0) files" } ?? "—")
                            LabeledContent("Test Files", value: testFileCount.map { "\($0) files" } ?? "—")
                            if let totalLines, let swiftFileCount, swiftFileCount > 0 {
                                LabeledContent("Average Lines per File", value: "\(totalLines / swiftFileCount)")
                            }
                        }
                    }
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Code Metrics")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            swiftFileCount = nil
            totalLines = nil
            nonBlankLines = nil
            testFileCount = nil
            return
        }
        let counts = await Task.detached(priority: .userInitiated) { () -> (files: Int, lines: Int, nonBlank: Int, tests: Int) in
            var files = 0, lines = 0, nonBlank = 0, tests = 0
            for url in ExpandedDevToolsFiles.collectFiles(at: root, extensions: ["swift"], maxCount: 5000) {
                files += 1
                if url.lastPathComponent.hasSuffix("Tests.swift") || url.path.contains("/Tests/") { tests += 1 }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let fileLines = text.components(separatedBy: "\n")
                lines += fileLines.count
                nonBlank += fileLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            }
            return (files, lines, nonBlank, tests)
        }.value
        swiftFileCount = counts.files
        totalLines = counts.lines
        nonBlankLines = counts.nonBlank
        testFileCount = counts.tests
    }
}

struct ExpandedDevToolsDuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64
    let paths: [String]
}

struct DuplicateFileDetectorView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var duplicateGroups: [ExpandedDevToolsDuplicateGroup] = []
    @State private var scannedFileCount = 0
    @State private var hasScanned = false
    @State private var isScanning = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Redundant Duplicate files list", icon: "doc.on.doc.fill", color: .red) {
                    if isScanning {
                        ProgressView("Scanning workspace files…")
                    } else if let statusMessage {
                        Text(statusMessage).foregroundStyle(.secondary)
                    } else if !hasScanned {
                        Text("Not scanned yet. Press Scan Workspace to hash-compare the files in the active project.")
                            .foregroundStyle(.secondary)
                    } else if duplicateGroups.isEmpty {
                        Text("No duplicate files detected in project workspace. (\(scannedFileCount) files scanned.)")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(duplicateGroups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Identical files — \(DevToolsDiskUsage.formatted(group.size)) each")
                                    .font(.subheadline.bold())
                                ForEach(group.paths, id: \.self) { path in
                                    Text(path).font(.system(.caption, design: .monospaced))
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                        Text("\(scannedFileCount) files scanned.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Scan Workspace") { Task { await scan() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isScanning)
                }
            }
            .padding()
        }
        .navigationTitle("Duplicate File Detector")
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }
        statusMessage = nil
        guard let root = sessionStore.activeProject?.directoryURL else {
            statusMessage = "No project open."
            return
        }
        let outcome = await Task.detached(priority: .userInitiated) { () -> ([ExpandedDevToolsDuplicateGroup], Int) in
            let files = ExpandedDevToolsFiles.collectFiles(at: root, extensions: nil, maxCount: 5000)
            var bySize: [Int64: [URL]] = [:]
            for url in files {
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                      size <= 50_000_000 else { continue }
                bySize[Int64(size), default: []].append(url)
            }
            var groups: [ExpandedDevToolsDuplicateGroup] = []
            for (size, candidates) in bySize where candidates.count > 1 {
                var clusters: [[URL]] = []
                for candidate in candidates {
                    var placed = false
                    for index in clusters.indices {
                        if let representative = clusters[index].first,
                           FileManager.default.contentsEqual(atPath: candidate.path, andPath: representative.path) {
                            clusters[index].append(candidate)
                            placed = true
                            break
                        }
                    }
                    if !placed { clusters.append([candidate]) }
                }
                for cluster in clusters where cluster.count > 1 {
                    groups.append(ExpandedDevToolsDuplicateGroup(
                        size: size,
                        paths: cluster.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }.sorted()))
                }
            }
            return (groups.sorted { $0.paths.first ?? "" < $1.paths.first ?? "" }, files.count)
        }.value
        duplicateGroups = outcome.0
        scannedFileCount = outcome.1
        hasScanned = true
    }
}

struct PlistViewerView: View {
    @State private var selectedURL: URL?
    @State private var plistContent = ""
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "PropertyList Source XML", icon: "list.bullet.rectangle", color: .teal) {
                    if let selectedURL {
                        Text(selectedURL.path)
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let statusMessage {
                            Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(plistContent)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No plist file selected. Choose a .plist file to view its contents.")
                            .foregroundStyle(.secondary)
                    }
#if canImport(AppKit)
                    Button(selectedURL == nil ? "Choose .plist File…" : "Choose a Different File…") {
                        if let url = ExpandedDevToolsPicker.pickFile(allowedTypes: ["plist"], canChooseDirectories: false) {
                            selectedURL = url
                            load(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
#else
                    Text("File picking requires macOS (AppKit).")
                        .foregroundStyle(.secondary)
#endif
                }
            }
            .padding()
        }
        .navigationTitle("Plist Viewer")
    }

    private func load(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            plistContent = ""
            statusMessage = "Could not read \(url.lastPathComponent) as text."
            return
        }
        if (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil {
            statusMessage = "Warning: \(url.lastPathComponent) did not parse as a property list; showing raw text."
        } else {
            statusMessage = nil
        }
        plistContent = text
    }
}

struct ColorInspectorView: View {
    @State private var colorHex = "#FF5733"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Interactive Color Inspector", icon: "paintpalette.fill", color: .pink) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Color(hex: colorHex)
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                                .shadow(radius: 3)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected HEX Code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("#FF5733", text: $colorHex)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Color Inspector")
    }
}

struct FontBrowserView: View {
    @State private var fonts: [String] = []
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "Installed System Fonts", icon: "textformat", color: .blue) {
#if canImport(AppKit)
                    if fonts.isEmpty {
                        Text(statusMessage ?? "No font families found.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(fonts, id: \.self) { font in
                            HStack {
                                Text(font)
                                    .font(.custom(font, size: 14))
                                Spacer()
                                Text("Preview Text").foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 300)
                    }
#else
                    Text("Font enumeration requires macOS (AppKit).")
                        .foregroundStyle(.secondary)
#endif
                }
            }
            .padding()
        }
        .navigationTitle("Font Browser")
#if canImport(AppKit)
        .task {
            fonts = NSFontManager.shared.availableFontFamilies.sorted()
            if fonts.isEmpty {
                statusMessage = "No font families reported by NSFontManager."
            }
        }
#endif
    }
}

struct ExpandedDevToolsImageMetadataRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

struct ImageMetadataViewerView: View {
    @State private var selectedURL: URL?
    @State private var rows: [ExpandedDevToolsImageMetadataRow] = []
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModernCard(title: "EXIF Image Metadata properties", icon: "photo.fill", color: .purple) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let selectedURL {
                            Text(selectedURL.lastPathComponent)
                                .font(.subheadline.bold())
                            if let statusMessage {
                                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(rows) { row in
                                LabeledContent(row.key, value: row.value)
                            }
                        } else {
                            Text("No image selected. Choose an image file to read its real metadata.")
                                .foregroundStyle(.secondary)
                        }
#if canImport(AppKit)
                        Button(selectedURL == nil ? "Choose Image…" : "Choose a Different Image…") {
                            if let url = ExpandedDevToolsPicker.pickFile(
                                allowedTypes: ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"],
                                canChooseDirectories: false) {
                                selectedURL = url
                                Task { await load(url) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
#else
                        Text("Image picking requires macOS (AppKit).")
                            .foregroundStyle(.secondary)
#endif
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Image Metadata Viewer")
    }

    private func load(_ url: URL) async {
#if canImport(ImageIO)
        let loaded = await Task.detached(priority: .userInitiated) { () -> Result<[ExpandedDevToolsImageMetadataRow], String> in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return .failure("Could not open \(url.lastPathComponent) as an image.")
            }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                return .failure("No metadata found in \(url.lastPathComponent).")
            }
            var rows: [ExpandedDevToolsImageMetadataRow] = []
            if let type = CGImageSourceGetType(source) as String? {
                rows.append(ExpandedDevToolsImageMetadataRow(key: "Format", value: type))
            }
            if let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                rows.append(ExpandedDevToolsImageMetadataRow(key: "Resolution", value: "\(width) x \(height) pixels"))
            }
            if let dpiWidth = properties[kCGImagePropertyDPIWidth] as? Double,
               let dpiHeight = properties[kCGImagePropertyDPIHeight] as? Double {
                rows.append(ExpandedDevToolsImageMetadataRow(key: "DPI", value: "\(Int(dpiWidth)) x \(Int(dpiHeight))"))
            }
            if let colorModel = properties[kCGImagePropertyColorModel] as? String {
                rows.append(ExpandedDevToolsImageMetadataRow(key: "Color model", value: colorModel))
            }
            if let profile = properties[kCGImagePropertyProfileName] as? String {
                rows.append(ExpandedDevToolsImageMetadataRow(key: "Color space", value: profile))
            }
            if let orientation = properties[kCGImagePropertyOrientation] as? Int {
                rows.append(ExpandedDevToolsImageMetadataRow(key: "Orientation", value: "\(orientation)"))
            }
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                    rows.append(ExpandedDevToolsImageMetadataRow(key: "Date taken", value: date))
                }
                if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = iso.first {
                    rows.append(ExpandedDevToolsImageMetadataRow(key: "ISO", value: "\(first)"))
                }
                if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
                    rows.append(ExpandedDevToolsImageMetadataRow(key: "F-number", value: "f/\(fNumber)"))
                }
                if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double {
                    rows.append(ExpandedDevToolsImageMetadataRow(key: "Exposure time", value: "\(exposure) s"))
                }
                if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                    rows.append(ExpandedDevToolsImageMetadataRow(key: "Focal length", value: "\(focal) mm"))
                }
            }
            return .success(rows)
        }.value
        switch loaded {
        case .success(let loadedRows):
            rows = loadedRows
            statusMessage = loadedRows.isEmpty ? "No readable metadata in this image." : nil
        case .failure(let message):
            rows = []
            statusMessage = message
        }
#else
        rows = []
        statusMessage = "Image metadata requires macOS (ImageIO is unavailable on this platform)."
#endif
    }
}
