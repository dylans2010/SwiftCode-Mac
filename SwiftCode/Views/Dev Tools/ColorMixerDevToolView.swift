import SwiftUI
import os.log

@Observable
@MainActor
final class ColorMixerViewModel {
    var red: Double = 128.0
    var green: Double = 128.0
    var blue: Double = 128.0

    var hexCode: String {
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct ColorMixerDevToolView: View {
    @State private var viewModel = ColorMixerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Interactively adjust Red, Green, and Blue color channels to build and inspect color values.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: viewModel.hexCode))
                        .frame(height: 120)
                        .shadow(radius: 2)

                    Text(viewModel.hexCode)
                        .font(.system(.title3, design: .monospaced))
                        .bold()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading) {
                        Text("Red Channel: \(Int(viewModel.red))")
                            .font(.headline)
                        Slider(value: $viewModel.red, in: 0.0...255.0)
                            .accentColor(.red)
                    }

                    VStack(alignment: .leading) {
                        Text("Green Channel: \(Int(viewModel.green))")
                            .font(.headline)
                        Slider(value: $viewModel.green, in: 0.0...255.0)
                            .accentColor(.green)
                    }

                    VStack(alignment: .leading) {
                        Text("Blue Channel: \(Int(viewModel.blue))")
                            .font(.headline)
                        Slider(value: $viewModel.blue, in: 0.0...255.0)
                            .accentColor(.blue)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Color Mixer")
    }
}
