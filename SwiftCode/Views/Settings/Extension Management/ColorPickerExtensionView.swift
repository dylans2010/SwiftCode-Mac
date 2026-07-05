import SwiftUI

// MARK: - Color Picker Extension View
struct ColorPickerExtensionView: View {
    @State private var showInlineSwatches = true
    @State private var colorFormat = "hex"
    @State private var previewSize = "medium"

    var body: some View {
        Form {
            Section {
                Toggle("Show Inline Swatches", isOn: $showInlineSwatches)
                Picker("Color Format", selection: $colorFormat) {
                    Text("Hex (#FF5733)").tag("hex")
                    Text("RGB (255, 87, 51)").tag("rgb")
                    Text("HSB (11°, 80%, 100%)").tag("hsb")
                }
                Picker("Swatch Size", selection: $previewSize) {
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
            } header: {
                Label("Color Picker", systemImage: "eyedropper.halffull")
            }
            Section {
                HStack(spacing: 12) {
                    ForEach([Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple], id: \.self) { color in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: 28, height: 28)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            }
            Section {
                Text("Displays inline color swatches next to UIColor and SwiftUI Color literals. Tap a swatch to open the system color picker and update the value in code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Color Picker")
        .navigationBarTitleDisplayMode(.inline)
    }
}
