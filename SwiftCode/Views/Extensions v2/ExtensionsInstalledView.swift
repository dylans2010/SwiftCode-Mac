import SwiftUI

// MARK: - Installed extensions, driven by the manager's records

public struct ExtensionsInstalledView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
    @State private var selected: ExtV2InstalledExtension?
    @State private var runExtensionId: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if manager.installed.isEmpty {
                ContentUnavailableView(
                    "No extensions installed",
                    systemImage: "puzzlepiece",
                    description: Text("Discover extensions from the registry, or register the sample native plugin from Native Extensions."))
            } else {
                List(manager.installed, selection: $selected) { installed in
                    ExtensionSidebarRow(
                        metadata: installed.metadata,
                        state: installed.state,
                        onOpen: { runExtensionId = installed.id })
                        .tag(installed)
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selected) { installed in
            ExtensionDetailsView(installed: installed)
        }
        .sheet(item: Binding(
            get: { runExtensionId.map(ExtV2RunSheetID.init(id:)) },
            set: { runExtensionId = $0?.id }
        )) { sheet in
            ExtensionRunView(extensionId: sheet.id)
        }
        .toolbar {
            Button("Refresh") { manager.refreshInstalled() }
        }
    }
}

private struct ExtV2RunSheetID: Identifiable {
    let id: String
}
