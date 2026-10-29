import SwiftUI

// MARK: - Extension details: real metadata, real state, real actions

public struct ExtensionDetailsView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
    @StateObject private var viewModel: ExtV2DetailsViewModel
    @State private var showRun = false
    @State private var errorMessage: String?

    public init(installed: ExtV2InstalledExtension) {
        _viewModel = StateObject(wrappedValue: ExtV2DetailsViewModel(installed: installed))
    }

    private var installed: ExtV2InstalledExtension {
        // Re-read from the manager so the sheet never shows stale state
        // after an install/enable/uninstall elsewhere.
        manager.installed.first { $0.id == viewModel.installed.id } ?? viewModel.installed
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(installed.metadata.displayName).font(.title2.bold())
                    Text("\(installed.metadata.publisher) · v\(installed.metadata.version) · \(installed.metadata.kind.displayName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(installed.metadata.description).font(.body)
                }
                Label(installed.state.displayName, systemImage: "circle.fill")
                    .font(.subheadline.bold())
                if let lastError = installed.lastError {
                    Text(lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        detailRow("Identifier", installed.id)
                        detailRow("Version", installed.metadata.version)
                        detailRow("Kind", installed.metadata.kind.displayName)
                        if let license = installed.metadata.license { detailRow("License", license) }
                        if let homepage = installed.metadata.homepage { detailRow("Homepage", homepage) }
                        if let engine = installed.metadata.engineRequirement { detailRow("Engine", engine) }
                        detailRow("Categories", installed.metadata.categories.isEmpty ? "—" : installed.metadata.categories.joined(separator: ", "))
                        detailRow("Install path", installed.installPath.isEmpty ? "In-app (native plugin)" : installed.installPath)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !installed.dependencies.isEmpty {
                    GroupBox("Dependencies") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(installed.dependencies, id: \.self) { dep in
                                let satisfied = manager.installed.contains { $0.id == dep && $0.isEnabled }
                                Label(dep, systemImage: satisfied ? "checkmark.circle" : "exclamationmark.triangle")
                                    .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let compatibility = viewModel.compatibility {
                    GroupBox("Compatibility") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(compatibility.compatible ? "Compatible with this host" : "Not fully compatible")
                                .font(.callout.bold())
                            ForEach(compatibility.reasons, id: \.self) { reason in
                                Text("• \(reason)").font(.callout).foregroundStyle(.secondary)
                            }
                            if !compatibility.unsupportedAPIs.isEmpty {
                                Text("Unsupported APIs: \(compatibility.unsupportedAPIs.joined(separator: ", "))")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 4) {
                        let granted = manager.permissions.grantedCapabilities(for: installed.id)
                        if granted.isEmpty {
                            Text("No capabilities granted.").font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(granted, id: \.self) { capability in
                                Text("• \(capability.displayName)").font(.callout)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    if installed.isEnabled {
                        Button("Disable") { manager.setEnabled(extensionId: installed.id, enabled: false) }
                            .buttonStyle(.bordered)
                        Button("Open") { showRun = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(installed.state == .incompatible || installed.state == .missingDependencies)
                    } else {
                        Button("Enable") { manager.setEnabled(extensionId: installed.id, enabled: true) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Uninstall", role: .destructive) {
                        Task { await manager.uninstall(extensionId: installed.id) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 520)
        .sheet(isPresented: $showRun) {
            ExtensionRunView(extensionId: installed.id)
        }
        .alert(
            "Action failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.callout.bold()).frame(width: 110, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
