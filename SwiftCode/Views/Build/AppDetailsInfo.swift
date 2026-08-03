import SwiftUI
import AppKit

public struct AppDetailsInfo: View {
    // Legacy bindings maintained for compatibility with WorkspaceView
    @Binding var appName: String
    @Binding var bundleIdentifier: String
    @Binding var marketingVersion: String
    @Binding var buildVersion: String
    @Binding var supportedDevices: String

    var onSkip: () -> Void
    var onContinue: () -> Void

    public init(
        appName: Binding<String>,
        bundleIdentifier: Binding<String>,
        marketingVersion: Binding<String>,
        buildVersion: Binding<String>,
        supportedDevices: Binding<String>,
        onSkip: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self._appName = appName
        self._bundleIdentifier = bundleIdentifier
        self._marketingVersion = marketingVersion
        self._buildVersion = buildVersion
        self._supportedDevices = supportedDevices
        self.onSkip = onSkip
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            // High fidelity statistics header for Sidebar panel
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Target Inspector")
                        .font(.headline)
                    Text("Active Configuration: \(appName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.06))

            Divider()

            ScrollView {
                XcodeProjectDetailsSheet()
                    .padding()
            }
            .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        }
    }
}

// MARK: - VisualEffectView NSViewRepresentable

public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .hudWindow
    public var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    public var state: NSVisualEffectView.State = .followsWindowActiveState

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        state: NSVisualEffectView.State = .followsWindowActiveState
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
