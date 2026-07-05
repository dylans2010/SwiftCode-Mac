import SwiftUI

// MARK: - Nord Theme Extension View
struct NordThemeExtensionView: View {
    @State private var isActive = false
    @State private var variant = "dark"

    private let swatches: [(String, Color)] = [
        ("Polar Night", Color(red: 0.18, green: 0.20, blue: 0.25)),
        ("Snow Storm", Color(red: 0.93, green: 0.94, blue: 0.96)),
        ("Frost Blue", Color(red: 0.53, green: 0.75, blue: 0.82)),
        ("Aurora Green", Color(red: 0.64, green: 0.74, blue: 0.55)),
        ("Aurora Red", Color(red: 0.75, green: 0.38, blue: 0.42)),
        ("Aurora Purple", Color(red: 0.71, green: 0.56, blue: 0.75)),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Set as Active Theme", isOn: $isActive)
                Picker("Variant", selection: $variant) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Nord Theme", systemImage: "snowflake")
            }
            Section {
                ForEach(swatches, id: \.0) { name, color in
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        Text(name)
                        Spacer()
                    }
                }
            } header: {
                Text("Color Palette")
            }
            Section {
                Text("The popular Nord arctic color palette for comfortable night coding. Features cool blue tones derived from the arctic landscape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Nord Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
