import SwiftUI

struct PreviewConfigurationView: View {
    @State private var manager = PreviewManager.shared

    private let supportedDevices = [
        "iPhone 16 Pro",
        "iPhone 16",
        "iPad Pro 13-inch (M4)",
        "Apple Watch Series 10",
        "Apple Vision Pro"
    ]

    var body: some View {
        HStack(spacing: 12) {
            Picker("Preview Target Device", selection: $manager.configuration.deviceName) {
                ForEach(supportedDevices, id: \.self) { device in
                    Text(device).tag(device)
                }
            }
            .frame(width: 180)
            .pickerStyle(.menu)

            Button {
                manager.toggleOrientation()
            } label: {
                Image(systemName: manager.configuration.isPortrait ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                    .help("Toggle Device Orientation")
            }
            .buttonStyle(.bordered)

            Button {
                manager.toggleDarkMode()
            } label: {
                Image(systemName: manager.configuration.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .help("Toggle Appearance (Light/Dark)")
            }
            .buttonStyle(.bordered)

            HStack(spacing: 4) {
                Text("Zoom")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Scale", selection: $manager.scale) {
                    Text("50%").tag(0.5)
                    Text("75%").tag(0.75)
                    Text("100%").tag(1.0)
                    Text("125%").tag(1.25)
                }
                .frame(width: 80)
                .labelsHidden()
            }

            Spacer()

            if manager.isCompiling {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    Text("Compiling Previews...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Live View Ready")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
