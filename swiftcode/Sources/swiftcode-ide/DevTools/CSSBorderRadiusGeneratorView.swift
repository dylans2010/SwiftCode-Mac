import SwiftUI

struct CSSBorderRadiusGeneratorView: View {
    @State private var topLeft: Double = 10
    @State private var topRight: Double = 10
    @State private var bottomLeft: Double = 10
    @State private var bottomRight: Double = 10

    var body: some View {
        VStack(spacing: 20) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 150, height: 150)
                .mask(
                    UnevenRoundedRectangle(topLeadingRadius: topLeft, bottomLeadingRadius: bottomLeft, bottomTrailingRadius: bottomRight, topTrailingRadius: topRight)
                )
                .padding()

            Form {
                Slider(value: $topLeft, in: 0...100) { Text("Top Left: \(Int(topLeft))%") }
                Slider(value: $topRight, in: 0...100) { Text("Top Right: \(Int(topRight))%") }
                Slider(value: $bottomLeft, in: 0...100) { Text("Bottom Left: \(Int(bottomLeft))%") }
                Slider(value: $bottomRight, in: 0...100) { Text("Bottom Right: \(Int(bottomRight))%") }
            }
            .padding()

            Text("border-radius: \(Int(topLeft))px \(Int(topRight))px \(Int(bottomRight))px \(Int(bottomLeft))px;")
                .font(.system(.caption, design: .monospaced))
                .padding()

            Spacer()
        }
        .navigationTitle("CSS Border Radius Generator")
    }
}
