import SwiftUI

public struct AddArtboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, String, String, Bool, String, Double, Bool, String) -> Void

    @State private var name: String = "MyCustomView"
    @State private var selectedDevice: String = "iPhone 16 Pro"
    @State private var appearance: String = "System"
    @State private var isPortrait: Bool = true
    @State private var dynamicTypeSize: String = "Medium"
    @State private var previewScale: Double = 1.0
    @State private var showSafeAreas: Bool = true
    @State private var sourceCode: String = """
import SwiftUI

struct MyCustomView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Custom Compiled Artboard")
                .font(.title)
                .bold()

            Text("This view is rendered dynamically from your source code using the Preview Engine!")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
"""

    public init(onAdd: @escaping (String, String, String, Bool, String, Double, Bool, String) -> Void) {
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Custom Artboard")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Form {
                Section(header: Text("Layout Configurations").font(.subheadline.bold())) {
                    TextField("Artboard Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("Target Device", selection: $selectedDevice) {
                        Text("iPhone 16 Pro").tag("iPhone 16 Pro")
                        Text("iPad Pro").tag("iPad Pro")
                        Text("Apple Watch").tag("Apple Watch")
                        Text("Apple Vision Pro").tag("Apple Vision Pro")
                        Text("MacBook Pro").tag("MacBook Pro")
                    }

                    Picker("Appearance", selection: $appearance) {
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                        Text("System").tag("System")
                    }

                    Picker("Orientation", selection: Binding(
                        get: { isPortrait ? "Portrait" : "Landscape" },
                        set: { isPortrait = ($0 == "Portrait") }
                    )) {
                        Text("Portrait").tag("Portrait")
                        Text("Landscape").tag("Landscape")
                    }

                    Picker("Dynamic Type Size", selection: $dynamicTypeSize) {
                        Text("Small").tag("Small")
                        Text("Medium").tag("Medium")
                        Text("Large").tag("Large")
                        Text("Extra Large").tag("Extra Large")
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Preview Scale")
                            Spacer()
                            Text(String(format: "%.2f", previewScale))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $previewScale, in: 0.5...1.5, step: 0.1)
                    }

                    Toggle("Safe Area Enabled", isOn: $showSafeAreas)
                }
                .padding(.bottom, 12)

                Section(header: Text("SwiftUI Source Code").font(.subheadline.bold())) {
                    TextEditor(text: $sourceCode)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Add Artboard") {
                    onAdd(name, selectedDevice, appearance, isPortrait, dynamicTypeSize, previewScale, showSafeAreas, sourceCode)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 550, height: 680)
    }
}
