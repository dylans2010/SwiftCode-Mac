import SwiftUI

// MARK: - Permissions: grant and revoke, with the boundary stated
//
// Toggling a capability here IS the user's approval — this is the
// settings surface, not a prompt the extension can trigger on its own.
// The enforcement itself lives in ExtV2PermissionManager and the
// bridges, which check grants on every call; revoking here takes
// effect on the next call an extension makes.

public struct ExtensionPermissionsView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
    // The permission manager is not itself observable, so a toggle
    // bumps this to re-read grants after each grant/revoke.
    @State private var refreshTick = 0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A permission prompt is not a sandbox. Extensions run out-of-process through a validated IPC protocol, and the bridges check these grants on every call. Revocation takes effect immediately.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
            Divider()
            if manager.installed.isEmpty {
                ContentUnavailableView("No extensions", systemImage: "lock", description: Text("Install an extension to manage its capabilities."))
            } else {
                List(manager.installed) { installed in
                    Section {
                        ForEach(ExtV2Capability.allCases, id: \.self) { capability in
                            Toggle(capability.displayName, isOn: Binding(
                                get: { manager.permissions.isGranted(extensionId: installed.id, capability: capability) },
                                set: { newValue in
                                    if newValue {
                                        manager.permissions.grant(extensionId: installed.id, capability: capability)
                                    } else {
                                        manager.permissions.revoke(extensionId: installed.id, capability: capability)
                                    }
                                    refreshTick += 1
                                }))
                            .toggleStyle(.switch)
                        }
                    } header: {
                        Text("\(installed.metadata.displayName) (\(installed.id))")
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
