import SwiftUI

struct DeviceResolution: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let points: String
    let pixels: String
    let scale: String
    let aspect: String
}

public struct iOSScreenResolutionsView: View {
    @State private var filterQuery = ""

    private let devices = [
        DeviceResolution(name: "iPhone 15 Pro Max / Plus", points: "430 x 932 pt", pixels: "1290 x 2796 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone 15 Pro / 15", points: "393 x 852 pt", pixels: "1179 x 2556 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone 14 Pro Max", points: "430 x 932 pt", pixels: "1290 x 2796 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone 14 Pro", points: "393 x 852 pt", pixels: "1179 x 2556 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone 13 / 14 Plus", points: "428 x 926 pt", pixels: "1284 x 2778 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone 13 Pro / 14 / 13", points: "390 x 844 pt", pixels: "1170 x 2532 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone 12 / 13 mini", points: "360 x 780 pt", pixels: "1080 x 2340 px", scale: "@3x", aspect: "19.5:9"),
        DeviceResolution(name: "iPhone SE (3rd Gen)", points: "375 x 667 pt", pixels: "750 x 1334 px", scale: "@2x", aspect: "16:9"),
        DeviceResolution(name: "iPad Pro 12.9-inch", points: "1024 x 1366 pt", pixels: "2048 x 2732 px", scale: "@2x", aspect: "4:3"),
        DeviceResolution(name: "iPad Pro 11-inch", points: "834 x 1194 pt", pixels: "1668 x 2388 px", scale: "@2x", aspect: "1.43:1")
    ]

    private var filteredDevices: [DeviceResolution] {
        devices.filter { d in
            filterQuery.isEmpty || d.name.lowercased().contains(filterQuery.lowercased())
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("iOS Device Screen Catalog", systemImage: "iphone")
                    .font(.title2.bold())
                Text("Lookup active screen resolutions, aspect ratios, scale multipliers, and dimensions in points vs pixels.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search model name...", text: $filterQuery)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            List {
                HStack {
                    Text("Device Model").font(.caption.bold()).frame(width: 220, alignment: .leading)
                    Text("Points Size").font(.caption.bold()).frame(width: 140, alignment: .leading)
                    Text("Pixels Size").font(.caption.bold()).frame(width: 140, alignment: .leading)
                    Text("Scale").font(.caption.bold()).frame(width: 60, alignment: .leading)
                    Text("Aspect Ratio").font(.caption.bold())
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 4)

                Divider()

                ForEach(filteredDevices) { d in
                    HStack {
                        Text(d.name)
                            .font(.headline)
                            .frame(width: 220, alignment: .leading)
                        Text(d.points)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 140, alignment: .leading)
                        Text(d.pixels)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 140, alignment: .leading)
                        Text(d.scale)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.orange)
                        Text(d.aspect)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
