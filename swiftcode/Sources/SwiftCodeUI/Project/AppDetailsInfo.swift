// AppDetailsInfo.swift
//
// Ported from Legacy `SwiftCode/Views/Build/AppDetailsInfo.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: inspector wrapper embedding project details with Skip/Continue flow
// Legacy source: in-repo SwiftCode-Legacy/ lacks this file; ported from the earlier staging copy at ~/SwiftCode-Migration-Workspace/staging/SwiftCode/Views/Build/AppDetailsInfo.swift (derived from Legacy).
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): VisualEffectView.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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
            .liquidGlass(style: .subtle, cornerRadius: 0)

            Divider()

            ScrollView {
                XcodeProjectDetailsSheet()
                    .padding()
            }
            .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        }
    }
}
