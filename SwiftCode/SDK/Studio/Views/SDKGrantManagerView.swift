import Foundation
import SwiftUI

// MARK: - SDKGrantManagerView
//
// Studio surface for inspecting and revoking capability grants held by one
// installed extension (spec Docs/Intro-to-SDK.md §8). Grants are read from
// `SDKGrantStore.shared` and include revoked tombstones, so this view also
// serves as the audit trail. Revocation stamps `revokedAt` and takes effect
// at the host authorization boundary immediately; records are never
// deleted. Reinstalling or changing the package content does not silently
// inherit grants for a different package identity — re-approval is
// required (spec §8.7).

public struct SDKGrantManagerView: View {

    // MARK: - State

    private let extensionID: String

    @State private var loadState: LoadState = .loading
    @State private var pendingRevoke: SDKGrantRecord?
    @State private var actionError: String?

    private enum LoadState {
        case loading
        case loaded(extensionName: String, grants: [SDKGrantRecord])
        case notFound
        case failed(String)
    }

    // MARK: - Init

    public init(extensionID: String) {
        self.extensionID = extensionID
    }

    // MARK: - Body

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading grants…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let extensionName, let grants):
                grantsContent(extensionName: extensionName, grants: grants)
            case .notFound:
                ContentUnavailableView(
                    "Extension not found",
                    systemImage: "puzzlepiece.extension",
                    description: Text("No installed extension with id “\(extensionID)” was found. It may have been uninstalled, or its manifest failed validation during the last registry scan.")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "Could not read grants",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .task(id: extensionID) {
            await load()
        }
        .alert(
            "Revoke grant?",
            isPresented: Binding(
                get: { pendingRevoke != nil },
                set: { if !$0 { pendingRevoke = nil } }
            ),
            presenting: pendingRevoke
        ) { grant in
            Button("Revoke", role: .destructive) {
                awaitRevoke(grant)
            }
            Button("Cancel", role: .cancel) {
                pendingRevoke = nil
            }
        } message: { grant in
            Text("This permanently revokes “\(grant.capability.rawValue)” for this extension within the scope shown. The extension will no longer be able to use this capability until it is granted again. A revoked record is kept as an audit tombstone.")
        }
        .alert("Revocation failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {
                actionError = nil
            }
        } message: {
            Text(actionError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Loading

    private func load() async {
        do {
            let installed = try await SDKExtensionRegistry.shared.scan()
            guard let ext = installed.first(where: { $0.id == extensionID }) else {
                loadState = .notFound
                return
            }
            let grants = await SDKGrantStore.shared.grants(for: extensionID)
            loadState = .loaded(extensionName: ext.name, grants: grants)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func awaitRevoke(_ grant: SDKGrantRecord) {
        pendingRevoke = nil
        Task {
            do {
                try await SDKGrantStore.shared.revoke(
                    extensionID: extensionID,
                    capability: grant.capability
                )
                await load()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Content

    private func grantsContent(extensionName: String, grants: [SDKGrantRecord]) -> some View {
        Form {
            Section("About grants") {
                Text("Grants are scoped to a single approved project, they are revocable at any time, and revocation takes effect immediately at the host authorization boundary. If the extension is reinstalled or its package content changes (new digest), previously granted capabilities are not silently inherited — the user must approve them again.")
                    .foregroundStyle(.secondary)
            }
            Section("\(extensionName) — \(grants.count) grant\(grants.count == 1 ? "" : "s")") {
                if grants.isEmpty {
                    Text("No grants recorded for this extension. Any capability it requests will be denied until the user explicitly approves it.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(grants, id: \.id) { grant in
                        grantRow(for: grant)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
    }

    // MARK: - Grant rows

    private func grantRow(for grant: SDKGrantRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SDKCapabilityRegistry.info(for: grant.capability).title)
                        .font(.headline)
                    Text(grant.capability.rawValue)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                grantStateBadge(for: grant)
            }
            LabeledContent("Scope", value: grant.scope.projectRootPath)
            LabeledContent("Granted", value: Self.dateFormatter.string(from: grant.grantedAt))
            LabeledContent("Granted by", value: grant.grantedBy)
            if let expiresAt = grant.expiresAt {
                LabeledContent("Expires", value: Self.dateFormatter.string(from: expiresAt))
            } else {
                LabeledContent("Expires", value: "Never")
            }
            LabeledContent("Package", value: grant.packageVersion)
            if let revokedAt = grant.revokedAt {
                LabeledContent("Revoked", value: Self.dateFormatter.string(from: revokedAt))
            }
            if grant.isActive() {
                HStack {
                    Spacer()
                    Button("Revoke", role: .destructive) {
                        pendingRevoke = grant
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func grantStateBadge(for grant: SDKGrantRecord) -> some View {
        let (label, color): (String, Color) = {
            if grant.revokedAt != nil {
                return ("REVOKED", .red)
            }
            if !grant.isActive() {
                return ("EXPIRED", .orange)
            }
            return ("ACTIVE", .green)
        }()
        return Text(label)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    @MainActor private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
