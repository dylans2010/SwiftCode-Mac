import SwiftUI

struct MinimapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("minimapEnabled") private var minimapEnabled = true
    @AppStorage("minimapWidth") private var minimapWidth: Double = 60
    @AppStorage("minimapOpacity") private var minimapOpacity: Double = 0.6

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Show Minimap", isOn: $minimapEnabled)

                    VStack(alignment: .leading) {
                        Text("Width: \(Int(minimapWidth))pt")
                            .font(.subheadline)
                        Slider(value: $minimapWidth, in: 40...100, step: 5)
                    }

                    VStack(alignment: .leading) {
                        Text("Opacity: \(Int(minimapOpacity * 100))%")
                            .font(.subheadline)
                        Slider(value: $minimapOpacity, in: 0.2...1.0, step: 0.1)
                    }
                }

                Section("Preview") {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 0.13, green: 0.13, blue: 0.17))
                            .frame(width: minimapWidth, height: 100)
                            .opacity(minimapOpacity)

                        VStack(spacing: 2) {
                            ForEach(0..<12, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(.white.opacity(0.3))
                                    .frame(width: minimapWidth * 0.7, height: 2)
                            }
                        }
                        .opacity(minimapOpacity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Minimap Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
