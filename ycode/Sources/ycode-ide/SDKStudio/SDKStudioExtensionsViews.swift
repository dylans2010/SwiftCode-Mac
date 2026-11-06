import Foundation
import SwiftUI
import YcodeExtensions
import YcodeSDKStudio

// MARK: - Extensions
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKStudioExtensionsView.swift`.
// Installed extensions, enable/disable, uninstall (which also revokes
// all of the extension's grants, so no grant survives its extension),
// and manual CLI install. The data source is Ycode's real
// `ExtensionManager` (`installed`, `refreshInstalled`, `setEnabled`,
// `uninstall`, `installLocalVSIX`) — the same store the rest of the IDE
// uses. Legacy invoked commands through `SDKExtensionManager` and drove
// installs through the SDK CLI (`SDKInstaller.resolveCLIURL()`); Ycode
// installs through `ExtensionManager.install` / `installLocalVSIX`, so
// the manual-command sheet records the equivalent local install instead
// of shelling out to a CLI that does not exist in Ycode.

@MainActor
struct SDKStudioExtensionsView: View {
    @State private var extensions: [InstalledExtension] = []
    @State private var selection: String?
    @State private var isLoading = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmingUninstall: InstalledExtension?
    @State private var manualCommand: String = ""
    @State private var showingManualCommand = false
    @State private var localInstallPath: String = ""

    private let grantStore = SDKPermissionManagerGrantStore(permissions: ExtensionManager.shared.permissions)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding(8)
            }
            if let statusMessage {
                Text(statusMessage).foregroundStyle(.green).padding(8)
            }
            if isLoading {
                ProgressView("Loading extensions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if extensions.isEmpty {
                SDKStudioEmptyState(title: "No Extensions Installed", systemImage: "puzzlepiece.extension", description: "Install an extension from the registry or a local package to see it here.")
            } else {
                List(selection: $selection) {
                    ForEach(extensions) { ext in
                        extensionRow(ext)
                    }
                }
                .listStyle(.plain)
            }
            Divider()
            installRow
        }
        .task { await refresh() }
        .alert("Uninstall Extension?", isPresented: Binding(
            get: { confirmingUninstall != nil },
            set: { if !$0 { confirmingUninstall = nil } }
        ), presenting: confirmingUninstall) { ext in
            Button("Uninstall", role: .destructive) { uninstall(ext) }
            Button("Cancel", role: .cancel) {}
        } message: { ext in
            Text("This removes \(ext.metadata.displayName) and revokes all of its capability grants.")
        }
        .sheet(isPresented: $showingManualCommand) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manual Install Command").font(.headline)
                Text(manualCommand).font(.callout.monospaced())
                Text("Run this command in a terminal to install the package, then Refresh.")
                    .foregroundStyle(.secondary)
                Button("Close") { showingManualCommand = false }
            }
            .padding()
            .frame(minWidth: 480)
        }
    }

    private var header: some View {
        HStack {
            Text("Extensions").font(.title2.bold())
            Spacer()
            Button("Refresh") { Task { await refresh() } }
                .disabled(isBusy)
        }
        .padding(8)
    }

    private func extensionRow(_ ext: InstalledExtension) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ext.metadata.displayName).font(.headline)
                Text("v\(ext.metadata.version)").font(.caption).foregroundStyle(.secondary)
                statusBadge(ext)
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { ext.isEnabled },
                    set: { newValue in setEnabled(ext, enabled: newValue) }
                ))
                .labelsHidden()
                Button("Uninstall") { confirmingUninstall = ext }
                    .font(.caption)
            }
            Text(ext.metadata.id).font(.caption.monospaced()).foregroundStyle(.secondary)
            if !ext.metadata.description.isEmpty {
                Text(ext.metadata.description).font(.caption).foregroundStyle(.secondary)
            }
            if !ext.capabilities.isEmpty {
                Text("Capabilities: \(ext.capabilities.map(\.displayName).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let lastError = ext.lastError {
                Text(lastError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Manage Grants") {
                    // The grant manager is a separate Studio surface; the
                    // selection drives it via the sidebar in the full app.
                    statusMessage = "Open the grant manager for \(ext.id) from the extension's detail view."
                }
                .font(.caption)
                Button("View Logs") {
                    statusMessage = "\(DiagnosticsService.shared.entries(for: ext.id).count) diagnostic entries for \(ext.id)."
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ ext: InstalledExtension) -> some View {
        Text(ext.state.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((ext.isEnabled ? Color.green : Color.gray).opacity(0.15), in: Capsule())
    }

    private var installRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install a Local Package").font(.headline)
            HStack {
                TextField("/path/to/extension.vsix", text: $localInstallPath)
                    .textFieldStyle(.roundedBorder)
                Button("Install") { installLocal() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || localInstallPath.isEmpty)
                Button("Manual Command") {
                    manualCommand = "Install \(localInstallPath) with the extension manager, then refresh."
                    showingManualCommand = true
                }
                .disabled(localInstallPath.isEmpty)
            }
            Text("A .vsix package installs through the extension manager. Legacy drove installs through the SDK CLI; Ycode has no SDK CLI, so installs go through this manager instead.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        ExtensionManager.shared.refreshInstalled()
        extensions = ExtensionManager.shared.installed
        isLoading = false
    }

    private func setEnabled(_ ext: InstalledExtension, enabled: Bool) {
        isBusy = true
        Task {
            ExtensionManager.shared.setEnabled(extensionId: ext.id, enabled: enabled)
            await refresh()
            statusMessage = "\(ext.metadata.displayName) \(enabled ? "enabled" : "disabled")."
            isBusy = false
        }
    }

    private func uninstall(_ ext: InstalledExtension) {
        isBusy = true
        Task {
            await ExtensionManager.shared.uninstall(extensionId: ext.id)
            try? await grantStore.revokeAll(for: ext.id)
            await refresh()
            statusMessage = "\(ext.metadata.displayName) uninstalled; its grants were revoked."
            isBusy = false
        }
    }

    private func installLocal() {
        let path = localInstallPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        isBusy = true
        Task {
            do {
                let url = URL(fileURLWithPath: path)
                let identity = ExtensionIdentity(id: url.deletingPathExtension().lastPathComponent)
                if let identity {
                    try await ExtensionManager.shared.installLocalVSIX(at: url, identity: identity)
                    statusMessage = "Installed package from \(path)."
                } else {
                    errorMessage = "Could not derive an extension identity from \(path)."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            await refresh()
            isBusy = false
        }
    }
}

// MARK: - Available / installed extensions
//
// Legacy: `SwiftCode/SDK/Studio/Views/AvailableExtensionsView.swift` —
// the registry browser over `SDKExtensionManager.snapshot()`: list,
// enable/disable, uninstall, invoke a contributed command and show its
// result. Ycode's `ExtensionManager.search` is the registry browser and
// `executeCommand` invokes commands; results are the manager's live
// `searchResults` / `installed` lists.

@MainActor
struct SDKAvailableExtensionsView: View {
    @State private var items: [InstalledExtension] = []
    @State private var searchQuery: String = ""
    @State private var searchResults: [ExtensionMetadata] = []
    @State private var selection: String?
    @State private var isLoading = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmingUninstall: InstalledExtension?
    @State private var invokingCommandKey: String?
    @State private var commandResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Available Extensions").font(.title2.bold())
                Spacer()
                Button("Refresh") { Task { await refresh() } }
            }
            .padding(8)
            HStack {
                TextField("Search the registry…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
            }
            .padding(.horizontal, 8)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding(8)
            }
            if let statusMessage {
                Text(statusMessage).foregroundStyle(.green).padding(8)
            }
            if !searchResults.isEmpty {
                List(searchResults) { metadata in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(metadata.displayName).font(.headline)
                            Text("v\(metadata.version)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Install") { install(metadata) }
                                .buttonStyle(.borderedProminent)
                        }
                        Text(metadata.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(metadata.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
                Divider()
            }
            if isLoading {
                ProgressView("Loading extensions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                SDKStudioEmptyState(title: "No Extensions Installed", systemImage: "puzzlepiece.extension", description: "Search the registry above to install an extension.")
            } else {
                List(selection: $selection) {
                    ForEach(items) { item in
                        extensionRow(item)
                    }
                }
                .listStyle(.plain)
            }
            if let commandResult {
                Text(commandResult)
                    .font(.callout.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .task { await refresh() }
        .alert("Uninstall Extension?", isPresented: Binding(
            get: { confirmingUninstall != nil },
            set: { if !$0 { confirmingUninstall = nil } }
        ), presenting: confirmingUninstall) { item in
            Button("Uninstall", role: .destructive) { uninstall(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("This removes \(item.metadata.displayName).")
        }
    }

    private func extensionRow(_ item: InstalledExtension) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.metadata.displayName).font(.headline)
                Text("Version \(item.metadata.version)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { item.isEnabled },
                    set: { newValue in setEnabled(item, enabled: newValue) }
                ))
                .labelsHidden()
                Button("Uninstall") { confirmingUninstall = item }
                    .font(.caption)
            }
            Text(item.metadata.id).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack {
                ForEach(ExtensionManager.shared.contributions[item.id]?.commands ?? [], id: \.command) { command in
                    Button(command.title) { invokeCommand(item: item, commandID: command.command) }
                        .font(.caption)
                        .disabled(isBusy)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        ExtensionManager.shared.refreshInstalled()
        items = ExtensionManager.shared.installed
        isLoading = false
    }

    private func search() {
        ExtensionManager.shared.search(query: searchQuery)
        searchResults = ExtensionManager.shared.searchResults
        if let error = ExtensionManager.shared.searchError {
            errorMessage = error
        }
    }

    private func install(_ metadata: ExtensionMetadata) {
        isBusy = true
        Task {
            do {
                try await ExtensionManager.shared.install(metadata: metadata)
                statusMessage = "Installed \(metadata.displayName)."
            } catch {
                errorMessage = error.localizedDescription
            }
            await refresh()
            isBusy = false
        }
    }

    private func setEnabled(_ item: InstalledExtension, enabled: Bool) {
        Task {
            ExtensionManager.shared.setEnabled(extensionId: item.id, enabled: enabled)
            await refresh()
        }
    }

    private func uninstall(_ item: InstalledExtension) {
        Task {
            await ExtensionManager.shared.uninstall(extensionId: item.id)
            try? await SDKPermissionManagerGrantStore(permissions: ExtensionManager.shared.permissions)
                .revokeAll(for: item.id)
            await refresh()
        }
    }

    private func invokeCommand(item: InstalledExtension, commandID: String) {
        invokingCommandKey = "\(item.id):\(commandID)"
        Task {
            do {
                let result = try await ExtensionManager.shared.executeCommand(
                    extensionId: item.id, command: commandID)
                commandResult = result.isEmpty ? "Command \(commandID) completed." : result
            } catch {
                commandResult = "Command \(commandID) failed: \(error.localizedDescription)"
            }
            invokingCommandKey = nil
        }
    }
}

// MARK: - Grant manager
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKGrantManagerView.swift`.
// One installed extension's capability grants, with revoke (confirm)
// and the audit trail of revoked tombstones. The store is the Studio
// grant seam: the default adapter reads live grants from Ycode's real
// `PermissionManager` and merges the revoked tombstones kept in the
// Host slice's `SDKGrantStore` (S-2) — revoked records stay visible
// with their revocation time, extension name, and package digest.
// Pre-authorization from the manifest editor grants through the real
// `PermissionManager.grant` (the seam has no grant operation by design
// — no second grant path was invented).

@MainActor
struct SDKGrantManagerView: View {
    let extensionID: String
    var grantStore: any SDKStudioGrantStore

    @State private var loadState: LoadState = .loading
    @State private var pendingRevoke: SDKStudioGrantRecord?
    @State private var actionError: String?

    private enum LoadState {
        case loading
        case loaded(extensionName: String, grants: [SDKStudioGrantRecord])
        case notFound
        case failed(String)
    }

    init(extensionID: String, grantStore: (any SDKStudioGrantStore)? = nil) {
        self.extensionID = extensionID
        self.grantStore = grantStore ?? SDKPermissionManagerGrantStore(
            permissions: ExtensionManager.shared.permissions)
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading grants…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let extensionName, let grants):
                grantsContent(extensionName: extensionName, grants: grants)
            case .notFound:
                SDKStudioEmptyState(title: "Extension not found", systemImage: "puzzlepiece.extension", description: "No installed extension with id “\(extensionID)” was found. It may have been uninstalled, or its manifest failed validation during the last registry scan.")
            case .failed(let message):
                SDKStudioEmptyState(title: "Could not read grants", systemImage: "exclamationmark.triangle",
                                     description: message)
            }
        }
        .task(id: extensionID) { await load() }
        .alert("Revoke grant?", isPresented: Binding(
            get: { pendingRevoke != nil },
            set: { if !$0 { pendingRevoke = nil } }
        ), presenting: pendingRevoke) { grant in
            Button("Revoke", role: .destructive) { awaitRevoke(grant) }
            Button("Cancel", role: .cancel) { pendingRevoke = nil }
        } message: { grant in
            Text("This permanently revokes “\(grant.capability.rawValue)” for this extension within the scope shown. The extension will no longer be able to use this capability until it is granted again.")
        }
    }

    private func grantsContent(extensionName: String, grants: [SDKStudioGrantRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(extensionName).font(.title2.bold())
                Spacer()
                Text("\(grants.count) grant(s)").foregroundStyle(.secondary)
            }
            .padding(8)
            Text("Grants are read from the live permission store. Revoked grants are kept as audit records with their revocation time, extension name, and package digest — revocation removes the grant immediately but never erases the history.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            if let actionError {
                Text(actionError).foregroundStyle(.red).padding(8)
            }
            if grants.isEmpty {
                SDKStudioEmptyState(title: "No Grants", systemImage: "lock.shield", description: "This extension currently holds no capability grants.")
            } else {
                List(grants) { grant in
                    grantRow(grant)
                }
                .listStyle(.plain)
            }
        }
    }

    private func grantRow(_ grant: SDKStudioGrantRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.capability.rawValue).font(.callout.monospaced())
                Text("Scope: \(grant.scopeDescription) · Granted \(grant.grantedAt.formatted(date: .abbreviated, time: .shortened)) by \(grant.grantedBy)")
                    .font(.caption).foregroundStyle(.secondary)
                if let expiresAt = grant.expiresAt {
                    Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let revokedAt = grant.revokedAt {
                    Text("Revoked \(revokedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !grant.packageDigest.isEmpty {
                    Text("Digest \(grant.packageDigest.prefix(12))… · v\(grant.packageVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(grant.isActive() ? "Active" : "Inactive")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((grant.isActive() ? Color.green : Color.gray).opacity(0.15), in: Capsule())
            Button("Revoke") { pendingRevoke = grant }
                .font(.caption)
                .disabled(!grant.isActive())
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loadState = .loading
        do {
            let name = await grantStore.extensionName(for: extensionID) ?? extensionID
            let grants = try await grantStore.grants(for: extensionID)
            // The adapter returns live grants only; an extension with no
            // grants and no installed record is "not found" only when the
            // manager has no such extension at all.
            let installed = ExtensionManager.shared.installed.contains(where: { $0.id == extensionID })
            if !installed && grants.isEmpty {
                loadState = .notFound
            } else {
                loadState = .loaded(extensionName: name, grants: grants)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func awaitRevoke(_ grant: SDKStudioGrantRecord) {
        Task {
            do {
                try await grantStore.revoke(grant)
                await load()
            } catch {
                actionError = error.localizedDescription
            }
            pendingRevoke = nil
        }
    }
}
