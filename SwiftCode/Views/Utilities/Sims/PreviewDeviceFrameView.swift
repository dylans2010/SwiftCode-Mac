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

                // Outer Bezel / Frame
                VStack(spacing: 0) {
                    if showTopNotch {
                        notchView
                    }

                    content()
                        .frame(width: deviceSize.width, height: deviceSize.height)
                        .background(isDarkMode ? Color.black : Color.white)
                        .colorScheme(isDarkMode ? .dark : .light)

                    if showHomeIndicator {
                        homeIndicatorView
                    }
                }
                .padding(8) // bezel thickness
                .background(Color(white: 0.15)) // Metal hardware color
                .cornerRadius(bezelCornerRadius)
                .shadow(color: Color.black.opacity(0.4), radius: 15, x: 0, y: 10)
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
        var base = CGSize(width: 393, height: 852) // iPhone 16 Pro default

        if deviceName.contains("iPad") {
            base = CGSize(width: 820, height: 1180)
        } else if deviceName.contains("Watch") {
            base = CGSize(width: 198, height: 242)
        } else if deviceName.contains("Vision") {
            base = CGSize(width: 1200, height: 800)
        } else if deviceName.contains("iPhone 16") && !deviceName.contains("Pro") {
            base = CGSize(width: 393, height: 852)
        }

        return isPortrait ? base : CGSize(width: base.height, height: base.width)
    }

    private var bezelCornerRadius: CGFloat {
        if deviceName.contains("iPad") {
            return 32
        } else if deviceName.contains("Watch") {
            return 24
        } else if deviceName.contains("Vision") {
            return 40
        }
        return 48 // Phone
    }

    private var showTopNotch: Bool {
        isPortrait && (deviceName.contains("iPhone") || deviceName.contains("Pro"))
    }

    private var showHomeIndicator: Bool {
        deviceName.contains("iPhone") || deviceName.contains("iPad")
    }

    private var notchView: some View {
        Capsule()
            .fill(Color.black)
            .frame(width: 110, height: 30)
            .padding(.top, 4)
            .padding(.bottom, -15)
            .zIndex(10)
    }

    private var homeIndicatorView: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 120, height: 5)
            .padding(.top, -15)
            .padding(.bottom, 6)
            .zIndex(10)
    }
}
