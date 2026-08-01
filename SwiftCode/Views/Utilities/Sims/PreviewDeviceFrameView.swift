import SwiftUI

@MainActor
struct PreviewDeviceFrameView<Content: View>: View {
    let deviceName: String
    let isPortrait: Bool
    let isDarkMode: Bool
    let scale: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                // Outer Bezel / Frame - Simple and sleek native decorative boundary
                VStack(spacing: 0) {
                    content()
                        .frame(width: deviceSize.width, height: deviceSize.height)
                        .background(isDarkMode ? Color.black : Color.white)
                        .colorScheme(isDarkMode ? .dark : .light)
                }
                .padding(8) // bezel thickness
                .background(Color(white: 0.12)) // Sleek space-gray anodized hardware finish
                .cornerRadius(bezelCornerRadius)
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 8)
                .scaleEffect(scale)
                .animation(.spring(), value: deviceName)
                .animation(.spring(), value: isPortrait)
                .animation(.spring(), value: scale)

                Spacer()
            }
            Spacer()
        }
        .simulatorWorkspaceEmbedded()
    }

    private var deviceSize: CGSize {
        let metrics = PreviewDeviceManager.shared.device(named: deviceName)
        let base = CGSize(width: metrics.width, height: metrics.height)
        return isPortrait ? base : CGSize(width: base.height, height: base.width)
    }

    private var bezelCornerRadius: CGFloat {
        let metrics = PreviewDeviceManager.shared.device(named: deviceName)
        return metrics.cornerRadius + 8.0
    }
}
