import SwiftUI

public struct SimulatorMainView: View {
    @State private var manager = SimulatorManager.shared
    @State private var selection: SimulatorSidebarSelection? = .service(.previews)
    @State private var showSidebar = true
    @State private var showingDiagnostics = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            AdaptivePage {
                VStack(spacing: 0) {
                    // Header Toolbar Action Control Group
                    headerToolbarView

                    Divider()

                    // Main View Content Workspace (Split Layout)
                    HSplitView {
                        if showSidebar {
                            SimulatorSidebar(selection: $selection)
                                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
                                .transition(.move(edge: .leading))
                        }

                        detailWorkspaceView
                            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Simulator & SwiftUI Previews Workspace")
            .sheet(isPresented: $showingDiagnostics) {
                SimulatorDiagnosticsView()
            }
            .onAppear {
                if let devID = manager.selectedDeviceID {
                    selection = .device(devID)
                }
            }
            .onChange(of: manager.selectedDeviceID) { _, newID in
                if let newID = newID {
                    selection = .device(newID)
                }
            }
            .onChange(of: selection) { _, newSelection in
                if let newSelection = newSelection {
                    switch newSelection {
                    case .service:
                        manager.selectedDeviceID = nil
                    case .device(let udid):
                        manager.selectedDeviceID = udid
                    }
                }
            }
        }
    }

    private var headerToolbarView: some View {
        HStack(spacing: 16) {
            // Sidebar Toggle
            Button {
                withAnimation {
                    showSidebar.toggle()
                }
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
            .buttonStyle(.bordered)
            .help("Toggle the navigation sidebar")

            Spacer()

            if manager.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading simulator runtimes")
            }

            Button(action: {
                Task {
                    await manager.refreshAll()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(manager.isRefreshing)

            Button {
                showingDiagnostics = true
            } label: {
                Label("Diagnostics", systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    @ViewBuilder
    private var detailWorkspaceView: some View {
        if let sel = selection {
            switch sel {
            case .service(let item):
                switch item {
                case .previews:
                    SimulatorPreviewView()
                        .simulatorWorkspaceEmbedded()
                case .deviceManager:
                    ScrollView {
                        VStack(spacing: 24) {
                            DeviceManagementView()
                            SimulatorSettingsView()
                        }
                        .padding(24)
                    }
                    .simulatorWorkspaceEmbedded()
                case .runtimes:
                    ScrollView {
                        VStack(spacing: 24) {
                            SimulatorRuntimeView()
                            RuntimeManagementView()
                        }
                        .padding(24)
                    }
                    .simulatorWorkspaceEmbedded()
                case .dragDropDeploy:
                    ScrollView {
                        VStack(spacing: 24) {
                            ApplicationDeploymentView()
                        }
                        .padding(24)
                    }
                    .simulatorWorkspaceEmbedded()
                }
            case .device(let udid):
                if let device = manager.devices.first(where: { $0.udid == udid }) {
                    SimulatorDetailView(device: device)
                        .simulatorWorkspaceEmbedded()
                } else {
                    noSelectionPlaceholder
                }
            }
        } else {
            noSelectionPlaceholder
        }
    }

    private var noSelectionPlaceholder: some View {
        ContentUnavailableView {
            Label("No Simulator or Service Selected", systemImage: "iphone")
        } description: {
            Text("Select a service or an active/offline simulator from the left sidebar to start booting, deploying, and tracing logs.")
        }
        .simulatorWorkspaceEmbedded()
    }
}
