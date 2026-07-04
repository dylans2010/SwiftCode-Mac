import SwiftUI

struct ThemeEditorView: View {
    @Bindable var viewModel: ThemeViewModel

    var body: some View {
        Form {
            Section("Info") {
                TextField("Theme Name", text: $viewModel.currentTheme.name)
                    .disabled(viewModel.currentTheme.isBuiltIn)
            }

            Section("Colors") {
                ColorPickerView(label: "Background", hex: $viewModel.currentTheme.background)
                ColorPickerView(label: "Foreground", hex: $viewModel.currentTheme.foreground)
                ColorPickerView(label: "Accent", hex: $viewModel.currentTheme.accentColor)
                ColorPickerView(label: "Selection", hex: $viewModel.currentTheme.selectionColor)
                ColorPickerView(label: "Line Highlight", hex: $viewModel.currentTheme.lineHighlightColor)
                ColorPickerView(label: "Cursor", hex: $viewModel.currentTheme.cursorColor)
            }

            Section("Syntax") {
                ColorPickerView(label: "Keyword", hex: $viewModel.currentTheme.keywordColor)
                ColorPickerView(label: "String", hex: $viewModel.currentTheme.stringColor)
                ColorPickerView(label: "Comment", hex: $viewModel.currentTheme.commentColor)
                ColorPickerView(label: "Number", hex: $viewModel.currentTheme.numberColor)
                ColorPickerView(label: "Type", hex: $viewModel.currentTheme.typeColor)
            }

            Section("Font") {
                Picker("Font Family", selection: $viewModel.fontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("Courier").tag("Courier")
                }
                Slider(value: $viewModel.fontSize, in: 8...24, step: 1) {
                    Text("Font Size: \(Int(viewModel.fontSize))")
                }
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}

struct ColorPickerView: View {
    let label: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex) },
                set: { hex = $0.toHex() ?? hex }
            ))
            TextField("Hex", text: $hex)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }
}

extension Color {
    func toHex() -> String? {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
