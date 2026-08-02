import SwiftUI

public struct DeviceConnectView: View {
    @State private var sidebarSelection = "dashboard"
    @State private var showInspector = true

    @State private var deviceManager = DeviceManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Central Toolbar
            DeviceConnectToolbar()

            Divider()

            HSplitView {
                // Column 1: Sidebar
                DeviceConnectSidebar(currentSelection: $sidebarSelection)
                    .frame(minWidth: 200, idealWidth: 220)

                // Column 2: Dashboard/Viewer Pane
                VStack(spacing: 0) {
                    switch sidebarSelection {
                    case "dashboard":
                        DeviceConnectDeploymentView()
                    case "sessions":
                        DeviceConnectSessionsView()
                    case "environment":
                        DeviceConnectEnvironmentView()
                    case "settings":
                        DeviceConnectSettingsView()
                    default:
                        DeviceConnectDeploymentView()
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity)
                .background(.background)

                // Column 3: Inspector Panel
                if showInspector {
                    DeviceConnectInspector()
                        .frame(minWidth: 260, idealWidth: 280)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    withAnimation {
                        showInspector.toggle()
                    }
                }) {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle Right Inspector Panel")
            }
        }
        .onAppear {
            Task {
                await deviceManager.startDiscovery()
            }
        }
        .onDisappear {
            Task {
                await deviceManager.stopDiscovery()
            }
        }
    }
}
