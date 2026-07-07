import SwiftUI

struct PercentageCalculatorView: View {
    @State private var p1 = "10"
    @State private var v1 = "100"
    @State private var res1 = "10"

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("What is")
                TextField("10", text: $p1).frame(width: 50)
                Text("% of")
                TextField("100", text: $v1).frame(width: 80)
                Text("?")
                Spacer()
                Text("= \(res1)")
                    .fontWeight(.bold)
            }
            .padding()
            .textFieldStyle(.roundedBorder)

            Button("Calculate") {
                if let p = Double(p1), let v = Double(v1) {
                    res1 = String(format: "%.2f", (p / 100) * v)
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .navigationTitle("Percentage Calculator")
    }
}
