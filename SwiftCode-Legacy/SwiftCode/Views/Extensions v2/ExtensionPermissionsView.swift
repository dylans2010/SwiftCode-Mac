import SwiftUI

public struct ExtensionPermissionsView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
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
