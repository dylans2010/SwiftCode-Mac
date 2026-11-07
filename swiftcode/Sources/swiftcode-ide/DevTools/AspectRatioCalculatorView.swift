import SwiftUI

struct AspectRatioCalculatorView: View {
    @State private var width = "1920"
    @State private var height = "1080"
    @State private var ratio = "16:9"

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack {
                    Text("Width")
                    TextField("W", text: $width)
                }
                VStack {
                    Text("Height")
                    TextField("H", text: $height)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding()

            Button("Calculate Ratio") { calculate() }
                .buttonStyle(.borderedProminent)

            Text("Ratio: \(ratio)")
                .font(.largeTitle)

            Spacer()
        }
        .navigationTitle("Aspect Ratio Calculator")
    }

    func calculate() {
        if let w = Int(width), let h = Int(height) {
            let common = gcd(w, h)
            ratio = "\(w/common):\(h/common)"
        }
    }

    func gcd(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? a : gcd(b, a % b)
    }
}
