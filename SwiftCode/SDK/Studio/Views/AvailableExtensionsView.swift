import Foundation
import SwiftUI

// MARK: - AvailableExtensionsView
//
// The Studio view where users see and use every installed extension/app
// (Docs/Intro-to-SDK.md §7).
//
// Real work only — every control calls a real API:
//   - The list comes from `SDKExtensionManager.snapshot()` (live discovery
//     of ~/.swiftcode/extensions merged with runtime lifecycle state).
//   - Each item shows its contributed commands (manifest-declared plus
//     commands the runtime registered via `context.commands`).
//   - Invoking a command calls `SDKExtensionManager.invokeCommand`, which
//     sends a `commands.execute` host event to the extension's TS runtime
//     and awaits its `commands.executeResult` — never native injection.
//   - Enable/disable/uninstall call the manager's real lifecycle paths.
// Errors are shown inline and are never swallowed.
//
// This view is hosted inside the Studio shell's NavigationStack; it does
// not create its own navigation container.

@MainActor
public struct AvailableExtensionsView: View {

    // MARK: - Nested types

    private struct CommandResult: Identifiable {
        let id = UUID()
        let extensionName: String
        let commandTitle: String
        let text: String
    }

    // MARK: - State

    @State private var items: [SDKManagedExtension] = []
    @State private var runtimeCommands: [String: [SDKCommandDefinition]] = [:]
    @State private var selection: String?
    // Starts true so the first paint doesn't flash the "no extensions"
    // empty state before the initial snapshot completes.
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmingUninstall = false
    @State private var invokingCommandKey: String?
    @State private var commandResult: CommandResult?

    public init() {}

    // MARK: - Derived

    private var selectedItem: SDKManagedExtension? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    private func commands(for item: SDKManagedExtension) -> [(id: String, title: String)] {
        var merged: [String: String] = [:]
        for command in item.declaredCommands {
            merged[command.id] = command.title
        }
        for command in runtimeCommands[item.id] ?? [] {
            merged[command.id] = command.title
        }
        return merged.sorted { $0.key < $1.key }.map { (id: $0.key, title: $0.value) }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                errorBanner(message: errorMessage)
            }
            if let statusMessage {
                statusBanner(message: statusMessage)
            }
            if items.isEmpty && !isLoading {
                emptyState
            } else {
                extensionList
            }
        }
        .navigationTitle("Available Extensions")
        .toolbar { toolbarContent }
        .task { await refresh() }
        .alert(
            "Uninstall Extension?",
            isPresented: $confirmingUninstall,
            presenting: selectedItem
        ) { item in
            Button("Uninstall", role: .destructive) { uninstall(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("Remove “\(item.name)” version \(item.version)? Its runtime state, contributed commands, capability grants, and stored secrets will all be removed. This cannot be undone.")
        }
        .sheet(item: $commandResult) { result in
            commandResultSheet(result)
        }
    }

    // MARK: - List

    private var extensionList: some View {
        List(items, id: \.id, selection: $selection) { item in
            extensionRow(item)
                .tag(item.id)
        }
    }

    private func extensionRow(_ item: SDKManagedExtension) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline)
                    Text(item.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                statusBadge(for: item)
                Toggle("Enabled", isOn: Binding(
                    get: { item.enabled },
                    set: { setEnabled(item, to: $0) }
                ))
                .disabled(isBusy)
            }
            HStack(spacing: 12) {
                Text("Version \(item.version)").font(.subheadline)
                if item.crashCount > 0 {
                    Text("Crashes: \(item.crashCount)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(item.lifecycleState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let diagnostic = item.diagnostic {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(diagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            let itemCommands = commands(for: item)
            if !itemCommands.isEmpty {
                DisclosureGroup("Commands (\(itemCommands.count))") {
                    ForEach(itemCommands, id: \.id) { command in
                        commandRow(item: item, commandID: command.id, title: command.title)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func commandRow(item: SDKManagedExtension, commandID: String, title: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(commandID)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if invokingCommandKey == "\(item.id)/\(commandID)" {
                ProgressView().controlSize(.small)
            } else {
                Button("Run") { invokeCommand(item, commandID: commandID, title: title) }
                    .disabled(isBusy || item.lifecycleState != .active)
                    .help(item.lifecycleState == .active
                        ? "Run this command in the extension's TypeScript runtime."
                        : "The extension must be running to invoke its commands.")
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(for item: SDKManagedExtension) -> some View {
        let (text, color): (String, Color) = {
            if item.quarantined { return ("Quarantined", .red) }
            switch item.lifecycleState {
            case .active: return ("Running", .green)
            case .failedValidation: return ("Invalid", .red)
            case .crashed, .timedOut: return ("Crashed", .orange)
            default: break
            }
            if !item.enabled { return ("Disabled", .gray) }
            return ("Stopped", .secondary)
        }()
        return Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Extensions Installed", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Extensions installed into ~/.swiftcode/extensions appear here once their swiftcode.json validates.")
        } actions: {
            Button("Refresh") { Task { await refresh() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(isLoading || isBusy)
            .help("Re-scan the extensions directory and refresh runtime state.")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Uninstall", systemImage: "trash") {
                confirmingUninstall = true
            }
            .disabled(selection == nil || isBusy)
            .help("Uninstall the selected extension: stops it, removes its commands, revokes its grants, wipes its secrets.")
        }
    }

    // MARK: - Banners and sheets

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .textSelection(.enabled)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
                .buttonStyle(.link)
        }
        .padding(8)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding([.horizontal, .top], 8)
    }

    private func statusBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)
            Text(message)
                .textSelection(.enabled)
            Spacer()
            Button("Dismiss") { statusMessage = nil }
                .buttonStyle(.link)
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding([.horizontal, .top], 8)
    }

    private func commandResultSheet(_ result: CommandResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.commandTitle).font(.headline)
            Text("“\(result.extensionName)” returned:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(result.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Close") { commandResult = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }

    // MARK: - Actions (all real)

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let snapshot = await SDKExtensionManager.shared.snapshot()
        items = snapshot
        var merged: [String: [SDKCommandDefinition]] = [:]
        for item in snapshot {
            merged[item.id] = await SDKCommandRegistry.shared.commands(for: item.id)
        }
        runtimeCommands = merged
        if let selection, !snapshot.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    private func setEnabled(_ item: SDKManagedExtension, to enabled: Bool) {
        Task {
            clearMessages()
            isBusy = true
            defer { isBusy = false }
            do {
                try await SDKExtensionManager.shared.setEnabled(enabled, extensionID: item.id)
                statusMessage = enabled
                    ? "“\(item.name)” enabled and starting."
                    : "“\(item.name)” disabled and stopped."
            } catch {
                showError(error)
            }
            await refresh()
        }
    }

    private func uninstall(_ item: SDKManagedExtension) {
        Task {
            clearMessages()
            isBusy = true
            defer { isBusy = false }
            do {
                try await SDKExtensionManager.shared.uninstall(extensionID: item.id)
                selection = nil
                statusMessage = "Uninstalled “\(item.name)”: runtime stopped, commands removed, grants revoked, secrets wiped."
            } catch {
                showError(error)
            }
            await refresh()
        }
    }

    private func invokeCommand(_ item: SDKManagedExtension, commandID: String, title: String) {
        Task {
            clearMessages()
            isBusy = true
            invokingCommandKey = "\(item.id)/\(commandID)"
            defer {
                isBusy = false
                invokingCommandKey = nil
            }
            do {
                let result = try await SDKExtensionManager.shared.invokeCommand(
                    extensionID: item.id,
                    commandID: commandID
                )
                commandResult = CommandResult(
                    extensionName: item.name,
                    commandTitle: title,
                    text: renderJSONValue(result)
                )
            } catch {
                showError(error)
            }
        }
    }

    // MARK: - Helpers

    private func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private func showError(_ error: Error) {
        if let sdkError = error as? SDKError {
            var text = sdkError.message
            if let suggestion = sdkError.suggestion, !suggestion.isEmpty {
                text += "\n\(suggestion)"
            }
            errorMessage = text
        } else {
            errorMessage = error.localizedDescription
        }
    }

    /// Renders an `SDKJSONValue` command result as readable text.
    private func renderJSONValue(_ value: SDKJSONValue, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case .string(let text):
            return indent == 0 ? text : "\"\(text)\""
        case .int(let number):
            return "\(number)"
        case .double(let number):
            return "\(number)"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .array(let elements):
            guard !elements.isEmpty else { return "[]" }
            let inner = elements
                .map { "\(pad)  \(renderJSONValue($0, indent: indent + 1))" }
                .joined(separator: ",\n")
            return "[\n\(inner)\n\(pad)]"
        case .object(let object):
            guard !object.isEmpty else { return "{}" }
            let inner = object
                .sorted { $0.key < $1.key }
                .map { "\(pad)  \"\($0.key)\": \(renderJSONValue($0.value, indent: indent + 1))" }
                .joined(separator: ",\n")
            return "{\n\(inner)\n\(pad)}"
        }
    }
}
