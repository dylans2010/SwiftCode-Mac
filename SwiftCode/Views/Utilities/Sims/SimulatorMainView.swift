import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SimulatorMainView")

/// The primary simulator and preview management workspace.
public struct SimulatorMainView: View {
    @State private var simulatorManager = SimulatorManager.shared
    @State private var previewManager = PreviewManager.shared
    @State private var selectedSidebarTab: SimulatorSidebarTab? = .devices
    @State private var selectedDeviceID: String? = nil

    public init() {}

    public var body: some View {
        AdaptivePage {
            HSplitView {
                // Left Navigator Sidebar
                SimulatorSidebar(
                    selectedTab: $selectedSidebarTab,
                    selectedDeviceID: $selectedDeviceID
                )
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 400)
                .background(Color(NSColor.windowBackgroundColor))

                // Right Workspace
                VStack(spacing: 0) {
                    // Toolbars
                    SimulatorToolbar()
                        .environment(simulatorManager)

                    Divider()

                    // Main Content Split
                    VSplitView {
                        SimulatorDetailView(selectedTab: selectedSidebarTab, selectedDeviceID: selectedDeviceID)
                            .frame(minWidth: 400, minHeight: 300)
                            .background(Color(NSColor.controlBackgroundColor))

                        // Bottom Developer Console
                        SimulatorConsoleView()
                            .frame(minHeight: 120, maxHeight: 400)
                            .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }
        }
        .environment(simulatorManager)
        .environment(previewManager)
        .onAppear {
            logger.info("SimulatorMainView did appear.")
            Task {
                await simulatorManager.refresh()
                selectedDeviceID = simulatorManager.selectedDeviceID
            }
        }
    }
}

/// Tabs or navigation items in the Simulator Sidebar.
public enum SimulatorSidebarTab: String, Identifiable, CaseIterable, Sendable {
    case devices = "Devices"
    case runtimes = "Runtimes"
    case deployments = "Deployments"
    case previews = "SwiftUI Previews"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .devices: return "iphone"
        case .runtimes: return "cpu"
        case .deployments: return "arrow.down.doc"
        case .previews: return "sparkles"
        }
    }
}
