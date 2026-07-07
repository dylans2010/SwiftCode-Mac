import SwiftUI

struct CSSShadowGeneratorView: View {
    @State private var hOffset: Double = 10
    @State private var vOffset: Double = 10
    @State private var blur: Double = 5
    @State private var spread: Double = 0
    @State private var color = Color.black.opacity(0.5)

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 150, height: 150)
                    .shadow(color: color, radius: blur / 2, x: hOffset, y: vOffset)
            }
            .frame(height: 250)
            .background(Color.gray.opacity(0.1))

            Form {
                Slider(value: $hOffset, in: -50...50) { Text("H-Offset: \(Int(hOffset))px") }
                Slider(value: $vOffset, in: -50...50) { Text("V-Offset: \(Int(vOffset))px") }
                Slider(value: $blur, in: 0...50) { Text("Blur: \(Int(blur))px") }
                ColorPicker("Shadow Color", selection: $color)
            }
            .padding()

            Text("box-shadow: \(Int(hOffset))px \(Int(vOffset))px \(Int(blur))px 0px rgba(0,0,0,0.5);")
                .font(.system(.caption, design: .monospaced))
                .padding()

            Spacer()
        }
        .navigationTitle("CSS Shadow Generator")
    }
}
