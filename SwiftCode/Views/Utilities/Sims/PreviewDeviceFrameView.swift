import SwiftUI

/// Draws a realistic hardware bezel representing the physical device around the preview canvas.
public struct PreviewDeviceFrameView<Content: View>: View {
    public let deviceName: String
    public let orientation: PreviewConfiguration.DeviceOrientation
    public let style: PreviewConfiguration.InterfaceStyle
    public let showSafeArea: Bool
    public let viewSize: CGSize
    @ViewBuilder public let content: () -> Content

    private var hasDynamicIsland: Bool {
        deviceName.lowercased().contains("pro") || deviceName.lowercased().contains("16") || deviceName.lowercased().contains("15")
    }

    private var hasHomeIndicator: Bool {
        !deviceName.lowercased().contains("watch") && !deviceName.lowercased().contains("se")
    }

    public var body: some View {
        ZStack {
            // Bezel Outer Shadow & Shell
            RoundedRectangle(cornerRadius: bezelCornerRadius, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .shadow(color: Color.black.opacity(0.4), radius: 15, x: 0, y: 10)

            // Bezel Screen Area (Clips Content)
            content()
                .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
                .padding(bezelThickness)

            // Safe Area Overlays (Notches, dynamic islands, bars)
            if showSafeArea {
                VStack(spacing: 0) {
                    statusBarOverlay
                    Spacer()
                    if hasHomeIndicator {
                        homeIndicatorOverlay
                    }
                }
                .padding(bezelThickness)
            }
        }
        .aspectRatio(viewSize.width / viewSize.height, contentMode: .fit)
    }

    // MARK: - Safe Area Layout Helpers

    private var statusBarOverlay: some View {
        HStack {
            if deviceName.lowercased().contains("watch") {
                EmptyView()
            } else {
                // Left metrics: Time
                Text(Date(), style: .time)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(style == .dark ? .white : .black)

                Spacer()

                if hasDynamicIsland {
                    // Center: Dynamic Island Capsule
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 85, height: 20)
                        .overlay {
                            Circle()
                                .fill(Color(red: 0.05, green: 0.05, blue: 0.10))
                                .frame(width: 8, height: 8)
                                .padding(.trailing, 45)
                        }
                    Spacer()
                }

                // Right metrics: Cell Signal, Wifi, Battery Icons
                HStack(spacing: 4) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 10))
                .foregroundStyle(style == .dark ? .white : .black)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var homeIndicatorOverlay: some View {
        Capsule()
            .fill(style == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
            .frame(width: 120, height: 4)
            .padding(.bottom, 8)
    }

    private var bezelThickness: CGFloat {
        if deviceName.lowercased().contains("watch") { return 6.0 }
        if deviceName.lowercased().contains("ipad") { return 14.0 }
        return 10.0
    }

    private var bezelCornerRadius: CGFloat {
        if deviceName.lowercased().contains("watch") { return 30.0 }
        if deviceName.lowercased().contains("ipad") { return 24.0 }
        return 40.0
    }

    private var screenCornerRadius: CGFloat {
        if deviceName.lowercased().contains("watch") { return 24.0 }
        if deviceName.lowercased().contains("ipad") { return 18.0 }
        return 32.0
    }
}
