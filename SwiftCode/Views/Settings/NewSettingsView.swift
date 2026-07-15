import SwiftUI

// MARK: - SettingsView (macOS AppKit native bridging shorthand fallback wrapper)

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Settings")
                .font(.title2.bold())
            Text("The settings panel opens in a dedicated native macOS window with search and favorites.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Open Settings Window") {
                SettingsWindowManager.shared.showSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 500, height: 400)
        .onAppear {
            SettingsWindowManager.shared.showSettings()
        }
    }
}
