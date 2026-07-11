import SwiftUI

/// Toolbar selector that triggers instant layout and visual toggles inside the Preview Canvas.
public struct PreviewConfigurationView: View {
    @Environment(PreviewManager.self) private var previewManager

    public var body: some View {
        HStack {
            let config = previewManager.configuration

            // Device Picker
            Picker("Device", selection: Binding(
                get: { config.deviceName },
                set: { newDevice in
                    var updated = config
                    updated.deviceName = newDevice
                    Task {
                        await previewManager.updateConfiguration(updated)
                    }
                }
            )) {
                Text("iPhone 16 Pro").tag("iPhone 16 Pro")
                Text("iPhone 16 Pro Max").tag("iPhone 16 Pro Max")
                Text("iPhone SE").tag("iPhone SE")
                Text("iPad Pro (13-inch)").tag("iPad Pro (13-inch)")
                Text("Apple Watch Series 10").tag("Apple Watch Series 10")
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Divider()
                .frame(height: 16)

            // Appearance Toggle
            Button(action: {
                var updated = config
                updated.interfaceStyle = config.interfaceStyle == .light ? .dark : .light
                Task {
                    await previewManager.updateConfiguration(updated)
                }
            }) {
                Image(systemName: config.interfaceStyle == .light ? "sun.max.fill" : "moon.stars.fill")
                    .foregroundStyle(config.interfaceStyle == .light ? .orange : .purple)
            }
            .buttonStyle(.plain)
            .help("Toggle Light/Dark Mode")

            Divider()
                .frame(height: 16)

            // Orientation Toggle
            Button(action: {
                var updated = config
                updated.orientation = config.orientation == .portrait ? .landscapeLeft : .portrait
                Task {
                    await previewManager.updateConfiguration(updated)
                }
            }) {
                Image(systemName: config.orientation == .portrait ? "rectangle.portrait" : "rectangle.landscape")
            }
            .buttonStyle(.plain)
            .help("Toggle Device Orientation")

            Divider()
                .frame(height: 16)

            // Scale Picker
            Picker("Scale", selection: Binding(
                get: { config.zoomScale },
                set: { newScale in
                    var updated = config
                    updated.zoomScale = newScale
                    Task {
                        await previewManager.updateConfiguration(updated)
                    }
                }
            )) {
                Text("50%").tag(0.5)
                Text("75%").tag(0.75)
                Text("100%").tag(1.0)
                Text("125%").tag(1.25)
            }
            .pickerStyle(.menu)
            .frame(width: 80)

            Divider()
                .frame(height: 16)

            // Toggle Safe Area Lines
            Toggle("Show Safe Area", isOn: Binding(
                get: { config.showSafeArea },
                set: { newValue in
                    var updated = config
                    updated.showSafeArea = newValue
                    Task {
                        await previewManager.updateConfiguration(updated)
                    }
                }
            ))
            .toggleStyle(.checkbox)

            Spacer()

            // Reload Button
            Button(action: {
                Task {
                    await previewManager.triggerReload()
                }
            }) {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}
