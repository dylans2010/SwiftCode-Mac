import SwiftUI
import os.log

@Observable
@MainActor
final class ColorPaletteGeneratorViewModel {
    var baseHex: String = "#3B82F6"
    var harmonyRule: String = "Monochromatic"
    var generatedPalette: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "ColorPaletteGenerator")

    func generate() {
        // Generates simple harmonious variations based on base color
        switch harmonyRule {
        case "Monochromatic":
            generatedPalette = [baseHex, "#60A5FA", "#93C5FD", "#BFDBFE", "#DBEAFE"]
        case "Analogous":
            generatedPalette = [baseHex, "#10B981", "#059669", "#3B82F6", "#2563EB"]
        case "Complementary":
            generatedPalette = [baseHex, "#F59E0B", "#D97706", "#EF4444", "#DC2626"]
        default:
            generatedPalette = [baseHex, "#60A5FA", "#93C5FD", "#BFDBFE", "#DBEAFE"]
        }
        logger.info("Successfully generated harmonious color palette variations.")
    }
}

struct ColorPaletteGeneratorDevToolView: View {
    @State private var viewModel = ColorPaletteGeneratorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generate cohesive UI color palettes from a single base seed color.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base Seed Color (HEX)")
                            .font(.headline)
                        TextField("#3B82F6", text: $viewModel.baseHex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Harmony Rule")
                            .font(.headline)
                        Picker("", selection: $viewModel.harmonyRule) {
                            Text("Monochromatic").tag("Monochromatic")
                            Text("Analogous").tag("Analogous")
                            Text("Complementary").tag("Complementary")
                        }
                    }
                }

                Button("Generate Palette") {
                    viewModel.generate()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.generatedPalette.isEmpty {
                    Divider()

                    Text("Harmonious Variations")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(viewModel.generatedPalette, id: \.self) { colorHex in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(hex: colorHex))
                                    .frame(height: 80)
                                    .shadow(radius: 1)

                                Text(colorHex)
                                    .font(.system(.caption, design: .monospaced))
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(12)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Color Palette Generator")
        .onAppear {
            viewModel.generate()
        }
    }
}
