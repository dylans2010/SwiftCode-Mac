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
        // Mock implementation of color conversion
        // In a real app, you would extract components from NSColor/UIColor
        hex = "#3B82F6"
        rgb = "rgb(59, 130, 246)"
    }

    func updateFromHex() {
        // Logic to update color from hex string
    }

    func updateFromRGB() {
        // Logic to update color from RGB string
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
