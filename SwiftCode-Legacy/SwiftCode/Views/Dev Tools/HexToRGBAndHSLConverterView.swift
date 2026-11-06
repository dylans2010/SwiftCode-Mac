import SwiftUI

public struct HexToRGBAndHSLConverterView: View {
    @State private var hexInput = "#FF9F0A"
    @State private var rVal = 255
    @State private var gVal = 159
    @State private var bVal = 10

    public init() {}

    private var swiftUICode: String {
        "Color(red: \(String(format: "%.3f", Double(rVal)/255.0)), green: \(String(format: "%.3f", Double(gVal)/255.0)), blue: \(String(format: "%.3f", Double(bVal)/255.0)))"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hex to RGB Color Converter")
                        .font(.title.bold())
                    Text("Perform real-time color coordinate conversions and compile safe copyable SwiftUI Color initializers.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Color Inputs")
                                    .font(.headline)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("HEX CODE")
                                        .font(.caption.bold())
                                    TextField("#FF9F0A", text: $hexInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .onChange(of: hexInput) { _, newValue in
                                            parseHexToRGB(newValue)
                                        }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("RGB CHANNEL CHANNELS")
                                        .font(.caption.bold())

                                    HStack {
                                        Text("R: \(rVal)").frame(width: 50, alignment: .leading)
                                        Slider(value: Binding(get: { Double(rVal) }, set: { rVal = Int($0); rebuildHex() }), in: 0...255)
                                    }
                                    HStack {
                                        Text("G: \(gVal)").frame(width: 50, alignment: .leading)
                                        Slider(value: Binding(get: { Double(gVal) }, set: { gVal = Int($0); rebuildHex() }), in: 0...255)
                                    }
                                    HStack {
                                        Text("B: \(bVal)").frame(width: 50, alignment: .leading)
                                        Slider(value: Binding(get: { Double(bVal) }, set: { bVal = Int($0); rebuildHex() }), in: 0...255)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .frame(width: 320)

                    VStack(spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Generated SwiftUI Code")
                                    .font(.headline)

                                Text(swiftUICode)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(6)

                                Button("Copy Code Initializer") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(swiftUICode, forType: .string)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Active Swatch Preview")
                                    .font(.headline)

                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: Double(rVal)/255.0, green: Double(gVal)/255.0, blue: Double(bVal)/255.0))
                                    .frame(height: 80)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func parseHexToRGB(_ hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        guard cleaned.count == 6 else { return }

        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        rVal = Int((rgb & 0xFF0000) >> 16)
        gVal = Int((rgb & 0x00FF00) >> 8)
        bVal = Int(rgb & 0x0000FF)
    }

    private func rebuildHex() {
        let hexString = String(format: "#%02X%02X%02X", rVal, gVal, bVal)
        hexInput = hexString
    }
}
