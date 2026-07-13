import SwiftUI
import os.log

@Observable
@MainActor
final class AccessibilityContrastGridViewModel {
    var textColor: Color = .black
    var textHex: String = "#000000"

    func updateTextColorFromHex() {
        textColor = Color(hex: textHex)
    }
}

struct AccessibilityContrastGridDevToolView: View {
    @State private var viewModel = AccessibilityContrastGridViewModel()

    private let backgrounds: [(String, Color)] = [
        ("Pure White", .white),
        ("Soft Gray", Color(hex: "#F5F5F7")),
        ("Medium Gray", Color(hex: "#8E8E93")),
        ("Dark Gray", Color(hex: "#1C1C1E")),
        ("Pure Black", .black),
        ("Apple Blue", Color(hex: "#007AFF")),
        ("Warning Yellow", Color(hex: "#FFCC00")),
        ("Success Green", Color(hex: "#34C759"))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Grid visualizing your chosen text color on different common backgrounds to check readability and contrast.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Text Color HEX")
                        .font(.headline)
                    TextField("#000000", text: $viewModel.textHex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120)
                        .onChange(of: viewModel.textHex) {
                            viewModel.updateTextColorFromHex()
                        }

                    ColorPicker("", selection: $viewModel.textColor)
                        .onChange(of: viewModel.textColor) {
                            viewModel.textHex = viewModel.textColor.toHex
                        }
                }

                Divider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                    ForEach(backgrounds, id: \.0) { bgName, bgColor in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(bgName)
                                .font(.caption.bold())
                                .foregroundColor(bgColor == .white ? .black : .secondary)

                            VStack(alignment: .center) {
                                Spacer()
                                Text("Accessibility Text")
                                    .font(.headline)
                                    .foregroundColor(viewModel.textColor)
                                Text("Small body sample goes here")
                                    .font(.caption)
                                    .foregroundColor(viewModel.textColor)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(bgColor)
                            .cornerRadius(8)
                            .shadow(radius: 1)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Accessibility Contrast Grid")
    }
}
