import SwiftUI

public struct AppDetailsInfo: View {
    // Legacy bindings maintained for compatibility with WorkspaceView if any other calls exist
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
        XcodeProjectDetailsSheet()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
