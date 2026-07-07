import SwiftUI

struct ColorConverterView: View {
    @State private var color = Color.blue
    @State private var hex = "#0000FF"
    @State private var rgb = "rgb(0, 0, 255)"

    var body: some View {
        VStack(spacing: 30) {
            ColorPicker("Pick a color", selection: $color)
                .font(.headline)
                .padding()
                .onChange(of: color) { updateFromColor() }

            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(height: 100)
                .padding(.horizontal)

            VStack(spacing: 15) {
                ColorRow(label: "HEX", value: $hex) { updateFromHex() }
                ColorRow(label: "RGB", value: $rgb) { updateFromRGB() }
            }
            .padding()

            Spacer()
        }
        .navigationTitle("Color Converter")
    }

    func updateFromColor() {
        let nsColor = NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)

        hex = String(format: "#%02X%02X%02X", r, g, b)
        rgb = "rgb(\(r), \(g), \(b))"
    }

    func updateFromHex() {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }

        if cString.count != 6 { return }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        color = Color(red: r, green: g, blue: b)
        rgb = "rgb(\(Int(r*255)), \(Int(g*255)), \(Int(b*255)))"
    }

    func updateFromRGB() {
        // Basic parser for rgb(r, g, b)
        let components = rgb.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if components.count == 3,
           let r = Double(components[0]),
           let g = Double(components[1]),
           let b = Double(components[2]) {
            color = Color(red: r/255, green: g/255, blue: b/255)
            hex = String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
        }
    }
}

struct ColorRow: View {
    let label: String
    @Binding var value: String
    var onCommit: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
                .frame(width: 50, alignment: .leading)
            TextField("", text: $value, onCommit: onCommit)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
    }
}
