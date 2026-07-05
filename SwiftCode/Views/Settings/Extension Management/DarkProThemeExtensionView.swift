import SwiftUI

// MARK: - Dark Pro Theme Extension View
struct DarkProThemeExtensionView: View {
    @State private var isActive = false

    private let swatches: [(String, Color)] = [
        ("Background", Color(red: 0.12, green: 0.12, blue: 0.12)),
        ("Foreground", Color(red: 0.85, green: 0.85, blue: 0.85)),
        ("Keywords", Color(red: 0.34, green: 0.61, blue: 0.87)),
        ("Strings", Color(red: 0.81, green: 0.52, blue: 0.35)),
        ("Comments", Color(red: 0.40, green: 0.62, blue: 0.40)),
        ("Functions", Color(red: 0.86, green: 0.86, blue: 0.56)),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Set as Active Theme", isOn: $isActive)
            } header: {
                Label("Dark Pro Theme", systemImage: "moon.stars.fill")
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
                Text("A professional dark theme inspired by VS Code Dark+. Optimized for long coding sessions with carefully tuned contrast ratios.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Dark Pro Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
