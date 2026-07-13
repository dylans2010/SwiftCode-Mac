import SwiftUI
import os.log

@Observable
@MainActor
final class ColorBlendingViewModel {
    var firstColor: Color = .blue
    var secondColor: Color = .yellow
    var blendRatio: Double = 0.5

    var blendedColor: Color {
        // Blend algorithm
        #if canImport(AppKit)
        let ns1 = NSColor(firstColor).usingColorSpace(.sRGB) ?? .black
        let ns2 = NSColor(secondColor).usingColorSpace(.sRGB) ?? .black
        let r = (ns1.redComponent * (1.0 - blendRatio)) + (ns2.redComponent * blendRatio)
        let g = (ns1.greenComponent * (1.0 - blendRatio)) + (ns2.greenComponent * blendRatio)
        let b = (ns1.blueComponent * (1.0 - blendRatio)) + (ns2.blueComponent * blendRatio)
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: 1.0)
        #else
        return .purple
        #endif
    }
}

struct ColorBlendingDevToolView: View {
    @State private var viewModel = ColorBlendingViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Blend two custom colors using customizable ratios, viewing the resulting color output values.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    VStack {
                        Text("Color 1")
                            .font(.headline)
                        ColorPicker("", selection: $viewModel.firstColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    VStack {
                        Text("Color 2")
                            .font(.headline)
                        ColorPicker("", selection: $viewModel.secondColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Blend Ratio: \(Int(viewModel.blendRatio * 100))%")
                        .font(.headline)
                    Slider(value: $viewModel.blendRatio, in: 0.0...1.0)
                }

                Divider()

                VStack(alignment: .center, spacing: 12) {
                    Text("Resulting Blended Color")
                        .font(.headline)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(viewModel.blendedColor)
                        .frame(width: 140, height: 140)
                        .shadow(radius: 2)

                    Text("HEX: \(viewModel.blendedColor.toHex)")
                        .font(.system(.body, design: .monospaced))
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Color Blending Tool")
    }
}
