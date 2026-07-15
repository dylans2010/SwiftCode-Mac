import SwiftUI
import AppKit

// MARK: - SettingsView (macOS AppKit sidebar-native bridging wrapper)

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        SettingsViewRepresentable()
            .frame(minWidth: 850, idealWidth: 1050, minHeight: 600, idealHeight: 750)
    }
}

private struct SettingsViewRepresentable: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> SettingsSplitViewController {
        let coordinator = SettingsCoordinator()
        let splitVC = SettingsSplitViewController(coordinator: coordinator)
        return splitVC
    }

    func updateNSViewController(_ nsViewController: SettingsSplitViewController, context: Context) {
        // No-op, managed natively by AppKit and SwiftUI Environment
    }
}
