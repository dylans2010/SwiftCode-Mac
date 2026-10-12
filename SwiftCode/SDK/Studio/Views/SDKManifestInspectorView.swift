import Foundation
import SwiftUI

// MARK: - SDKManifestInspectorView
//
// Studio surface that loads one installed extension's `swiftcode.json`
// manifest (via `SDKExtensionRegistry`) and presents it in readable,
// sectioned form (spec Docs/Intro-to-SDK.md §7): identity, runtime, SDK
// reference, capability declarations (with plain-language explanations and
// risk badges from `SDKCapabilityRegistry`), contributed commands, and the
// Assist metadata flag (explicitly descriptive-only, never a grant).

public struct SDKManifestInspectorView: View {

    // MARK: - State

    private let extensionID: String

    @State private var loadState: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded(SDKInstalledExtension)
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
                ProgressView("Loading manifest…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let ext):
                inspectorContent(for: ext)
            case .notFound:
                ContentUnavailableView(
                    "Extension not found",
                    systemImage: "puzzlepiece.extension",
                    description: Text("No installed extension with id “\(extensionID)” was found. It may have been uninstalled, or its manifest failed validation during the last registry scan.")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "Could not read the manifest",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .task(id: extensionID) {
            await load()
        }
    }

    // MARK: - Loading

    private func load() async {
        do {
            let installed = try await SDKExtensionRegistry.shared.scan()
            if let ext = installed.first(where: { $0.id == extensionID }) {
                loadState = .loaded(ext)
            } else {
                loadState = .notFound
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Content

    private func inspectorContent(for ext: SDKInstalledExtension) -> some View {
        Form {
            identitySection(for: ext)
            runtimeSection(for: ext.manifest)
            sdkSection(for: ext.manifest)
            capabilitiesSection(for: ext.manifest)
            commandsSection(for: ext.manifest)
            assistSection(for: ext.manifest)
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
    }

    // MARK: - Sections

    private func identitySection(for ext: SDKInstalledExtension) -> some View {
        Section("Identity") {
            LabeledContent("ID", value: ext.id)
            LabeledContent("Name", value: ext.name)
            LabeledContent("Version", value: ext.version)
            if let description = ext.manifest.description, !description.isEmpty {
                LabeledContent("Description") {
                    Text(description)
                }
            }
            LabeledContent("Package digest") {
                Text(ext.packageDigest)
                    .font(.body.monospaced())
            }
        }
    }

    private func runtimeSection(for manifest: SDKManifest) -> some View {
        Section("Runtime") {
            LabeledContent("Language", value: manifest.runtime.language)
            LabeledContent("Entrypoint", value: manifest.runtime.entrypoint)
            LabeledContent("Minimum host version", value: manifest.runtime.minimumSwiftCodeVersion)
        }
    }

    private func sdkSection(for manifest: SDKManifest) -> some View {
        Section("SDK") {
            LabeledContent("Package", value: manifest.sdk.name)
            LabeledContent("Version range", value: manifest.sdk.versionRange)
            LabeledContent("Protocol version", value: String(manifest.sdk.protocolVersion))
        }
    }

    private func capabilitiesSection(for manifest: SDKManifest) -> some View {
        Section("Capabilities") {
            if manifest.capabilities.isEmpty {
                Text("This extension declares no capabilities.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manifest.capabilities, id: \.id) { capability in
                    capabilityRow(for: capability)
                }
            }
        }
    }

    private func capabilityRow(for capability: SDKManifestCapability) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(capability.id)
                    .font(.body.monospaced())
                Spacer()
                if let info = SDKCapabilityRegistry.info(forRawValue: capability.id) {
                    riskBadge(for: info.risk)
                } else {
                    Text("UNKNOWN")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.red)
                }
            }
            if let info = SDKCapabilityRegistry.info(forRawValue: capability.id) {
                Text(info.title)
                    .font(.headline)
                Text(info.description)
                    .foregroundStyle(.secondary)
                labeledLine(label: "Grants", value: info.grantsSummary)
                labeledLine(label: "Does not grant", value: info.doesNotGrant)
                if !info.grantableInCurrentRelease {
                    labeledLine(
                        label: "Grantable",
                        value: "No — not grantable in this release. Any request is denied."
                    )
                }
            } else {
                Text("Unknown capability id. The host does not recognize this capability and will reject it.")
                    .foregroundStyle(.red)
            }
            if !capability.reason.isEmpty {
                labeledLine(label: "Extension's reason", value: capability.reason)
            }
        }
        .padding(.vertical, 4)
    }

    private func riskBadge(for risk: SDKCapabilityRisk) -> some View {
        Text(riskLabel(for: risk))
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(riskColor(for: risk).opacity(0.15), in: Capsule())
            .foregroundStyle(riskColor(for: risk))
    }

    private func riskLabel(for risk: SDKCapabilityRisk) -> String {
        switch risk {
        case .low: return "LOW RISK"
        case .medium: return "MEDIUM RISK"
        case .high: return "HIGH RISK"
        case .restricted: return "RESTRICTED"
        }
    }

    private func riskColor(for risk: SDKCapabilityRisk) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .restricted: return .purple
        }
    }

    private func commandsSection(for manifest: SDKManifest) -> some View {
        Section("Commands") {
            let commands = manifest.contributes?.commands ?? []
            if commands.isEmpty {
                Text("This extension contributes no commands.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(commands, id: \.id) { command in
                    LabeledContent {
                        Text(command.title)
                    } label: {
                        Text(command.id)
                            .font(.body.monospaced())
                    }
                }
            }
        }
    }

    private func assistSection(for manifest: SDKManifest) -> some View {
        Section("Assist") {
            LabeledContent("Requested", value: manifest.assist.requested ? "Yes" : "No")
            Text("The “assist.requested” manifest field is descriptive metadata only. It is never a grant: Assist access requires SwiftCode's independent Assist authorization system, and extensions are denied Assist by default.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func labeledLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}
