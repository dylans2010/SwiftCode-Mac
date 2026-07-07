import SwiftUI

struct ColorGradientGeneratorView: View {
    @State private var color1 = Color.blue
    @State private var color2 = Color.purple
    @State private var angle: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(gradient: Gradient(colors: [color1, color2]), startPoint: .leading, endPoint: .trailing))
                .frame(height: 200)
                .padding()

            HStack {
                ColorPicker("Start Color", selection: $color1)
                ColorPicker("End Color", selection: $color2)
            }
            .padding()

            VStack(alignment: .leading) {
                Text("SwiftUI Code:")
                Text("LinearGradient(gradient: Gradient(colors: [\(color1.description), \(color2.description)]), startPoint: .leading, endPoint: .trailing)")
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color.secondary.opacity(0.1))
            }
            .padding()

            Spacer()
        }
        .navigationTitle("Color Gradient Generator")
    }
}
