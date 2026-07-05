import SwiftUI

// MARK: - Gruvbox Theme Extension View
struct GruvboxThemeExtensionView: View {
    @State private var isActive = false
    @State private var contrast = "medium"

    private let swatches: [(String, Color)] = [
        ("Background", Color(red: 0.16, green: 0.16, blue: 0.11)),
        ("Foreground", Color(red: 0.98, green: 0.91, blue: 0.71)),
        ("Yellow", Color(red: 0.98, green: 0.74, blue: 0.18)),
        ("Orange", Color(red: 0.99, green: 0.52, blue: 0.18)),
        ("Red", Color(red: 0.80, green: 0.14, blue: 0.11)),
        ("Green", Color(red: 0.72, green: 0.73, blue: 0.15)),
        ("Aqua", Color(red: 0.55, green: 0.71, blue: 0.40)),
        ("Blue", Color(red: 0.51, green: 0.65, blue: 0.60)),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Set as Active Theme", isOn: $isActive)
                Picker("Contrast", selection: $contrast) {
                    Text("Soft").tag("soft")
                    Text("Medium").tag("medium")
                    Text("Hard").tag("hard")
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Gruvbox Theme", systemImage: "flame.fill")
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(swatches, id: \.0) { name, color in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color)
                                .frame(height: 32)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                            Text(name)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Color Palette")
            }
            Section {
                Text("Retro groove color scheme with warm earthy tones. Available in soft, medium, and hard contrast variants.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Gruvbox Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
