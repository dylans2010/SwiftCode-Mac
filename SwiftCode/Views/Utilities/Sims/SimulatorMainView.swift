import SwiftUI

public struct SimulatorMainView: View {
    @State private var manager = SimulatorManager.shared
    @State private var activeTab: Tab = .simulator
    @State private var showingDiagnostics = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private enum Tab {
        case simulator
        case previewCanvas
        case deviceManager
        case runtimes
        case dragDropDeploy
    }

    public var body: some View {
        NavigationStack {
            AdaptivePage {
                VStack(spacing: 0) {
                    // Header Toolbar Action Control Group
                    headerToolbarView

                    Divider()

                    // Main View Content Workspace
                    mainWorkspaceView
                }
            }
            .navigationTitle("Simulator & SwiftUI Previews Workspace")
            .sheet(isPresented: $showingDiagnostics) {
                SimulatorDiagnosticsView()
            }
        }
    }

    private var headerToolbarView: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $activeTab) {
                Label("Apple Simulator", systemImage: "iphone")
                    .tag(Tab.simulator)
                Label("SwiftUI Previews", systemImage: "sparkles")
                    .tag(Tab.previewCanvas)
                Label("Device Registry", systemImage: "macbook.and.iphone")
                    .tag(Tab.deviceManager)
                Label("SDK Runtimes", systemImage: "square.stack.3d.down.right")
                    .tag(Tab.runtimes)
                Label("Deploy App", systemImage: "square.and.arrow.down")
                    .tag(Tab.dragDropDeploy)
            }
            .pickerStyle(.segmented)
            .frame(width: 700)

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
    private var mainWorkspaceView: some View {
        switch activeTab {
        case .simulator:
            HSplitView {
                SimulatorSidebar()
                    .simulatorWorkspaceEmbedded()
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)

                if let selected = manager.selectedDevice {
                    SimulatorDetailView(device: selected)
                        .simulatorWorkspaceEmbedded()
                        .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No Simulator Selected", systemImage: "iphone")
                    } description: {
                        Text("Select a simulator from the left sidebar to start booting, deploying, and tracing logs.")
                    }
                    .simulatorWorkspaceEmbedded()
                }
            }

        case .previewCanvas:
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
    }
}
