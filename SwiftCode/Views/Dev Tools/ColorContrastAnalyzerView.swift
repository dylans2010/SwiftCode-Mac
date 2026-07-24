import SwiftUI

public struct ColorContrastAnalyzerView: View {
    @State private var textHex = "#000000"
    @State private var bgHex = "#FFFFFF"

    public init() {}

    private var contrastRatio: Double {
        let textL = relativeLuminance(from: textHex)
        let bgL = relativeLuminance(from: bgHex)

        let l1 = max(textL, bgL)
        let l2 = min(textL, bgL)

        return (l1 + 0.05) / (l2 + 0.05)
    }

    private var aaLargeScore: Bool { contrastRatio >= 3.0 }
    private var aaNormalScore: Bool { contrastRatio >= 4.5 }
    private var aaaLargeScore: Bool { contrastRatio >= 4.5 }
    private var aaaNormalScore: Bool { contrastRatio >= 7.0 }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WCAG Contrast Ratio Analyzer")
                        .font(.title.bold())
                    Text("Pick text and background hex coordinate parameters to evaluate compliance indexes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    // Left Input panel
                    VStack(spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Color Coordinates Input")
                                    .font(.headline)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Text Hex Color")
                                        .font(.caption.bold())
                                    TextField("#000000", text: $textHex)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Background Hex Color")
                                        .font(.caption.bold())
                                    TextField("#FFFFFF", text: $bgHex)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Calculated Contrast Index")
                                    .font(.headline)

                                Text(String(format: "%.2f : 1", contrastRatio))
                                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .frame(width: 280)

                    // Right Compliance metrics
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Compliance Guidelines Checklist")
                                    .font(.headline)

                                Divider()

                                complianceRow(title: "WCAG 2.0 AA (Large Text)", passing: aaLargeScore, req: "3.0 : 1")
                                complianceRow(title: "WCAG 2.0 AA (Normal Text)", passing: aaNormalScore, req: "4.5 : 1")
                                complianceRow(title: "WCAG 2.0 AAA (Large Text)", passing: aaaLargeScore, req: "4.5 : 1")
                                complianceRow(title: "WCAG 2.0 AAA (Normal Text)", passing: aaaNormalScore, req: "7.0 : 1")
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Visual Contrast Sandbox Preview")
                                    .font(.headline)

                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorFromHex(bgHex))
                                        .frame(height: 100)

                                    Text("Sample Reference Text")
                                        .font(.title2.bold())
                                        .foregroundColor(colorFromHex(textHex))
                                }
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

    private func complianceRow(title: String, passing: Bool, req: String) -> some View {
        HStack {
            Image(systemName: passing ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passing ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text("Required ratio limit: \(req)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // Helper functions for relative luminance
    private func relativeLuminance(from hex: String) -> Double {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        guard cleaned.count == 6 else { return 0.0 }

        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        let r_ = r <= 0.03928 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4)
        let g_ = g <= 0.03928 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4)
        let b_ = b <= 0.03928 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4)

        return 0.2126 * r_ + 0.7152 * g_ + 0.0722 * b_
    }

    private func colorFromHex(_ hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        guard cleaned.count == 6 else { return .secondary }

        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}
