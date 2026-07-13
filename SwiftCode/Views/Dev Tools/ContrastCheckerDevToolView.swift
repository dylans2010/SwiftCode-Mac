import SwiftUI
import os.log

@Observable
@MainActor
final class ContrastCheckerViewModel {
    var textHex: String = "#000000"
    var bgHex: String = "#FFFFFF"

    var contrastRatio: Double {
        #if canImport(AppKit)
        let nsText = NSColor(Color(hex: textHex)).usingColorSpace(.sRGB) ?? .black
        let nsBg = NSColor(Color(hex: bgHex)).usingColorSpace(.sRGB) ?? .white

        let l1 = relativeLuminance(r: nsText.redComponent, g: nsText.greenComponent, b: nsText.blueComponent)
        let l2 = relativeLuminance(r: nsBg.redComponent, g: nsBg.greenComponent, b: nsBg.blueComponent)

        let lighter = max(l1, l2)
        let darker = min(l1, l2)

        return (lighter + 0.05) / (darker + 0.05)
        #else
        return 21.0
        #endif
    }

    private func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> Double {
        let rs = r <= 0.03928 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4)
        let gs = g <= 0.03928 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4)
        let bs = b <= 0.03928 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4)
        return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs
    }
}

struct ContrastCheckerDevToolView: View {
    @State private var viewModel = ContrastCheckerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Verify WCAG 2.1 accessibility compliance for text contrast on solid color backgrounds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text Color (HEX)")
                            .font(.headline)
                        TextField("#000000", text: $viewModel.textHex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Background Color (HEX)")
                            .font(.headline)
                        TextField("#FFFFFF", text: $viewModel.bgHex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Divider()

                VStack(alignment: .center, spacing: 12) {
                    Text("Resulting Contrast Ratio")
                        .font(.headline)

                    Text(String(format: "%.1f : 1", viewModel.contrastRatio))
                        .font(.system(.largeTitle, design: .rounded))
                        .bold()
                        .foregroundColor(viewModel.contrastRatio >= 4.5 ? .green : .red)

                    HStack(spacing: 20) {
                        VStack {
                            Text("Normal Text")
                                .font(.caption.bold())
                            Text(viewModel.contrastRatio >= 4.5 ? "PASS (AA)" : "FAIL")
                                .bold()
                                .foregroundColor(viewModel.contrastRatio >= 4.5 ? .green : .red)
                        }

                        VStack {
                            Text("Large Text")
                                .font(.caption.bold())
                            Text(viewModel.contrastRatio >= 3.0 ? "PASS (AA)" : "FAIL")
                                .bold()
                                .foregroundColor(viewModel.contrastRatio >= 3.0 ? .green : .red)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Contrast Checker")
    }
}
