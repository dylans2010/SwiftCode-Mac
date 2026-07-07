import SwiftUI

struct LengthConverterView: View {
    @State private var input = "1"
    @State private var fromUnit = "Meters"
    @State private var result = "3.28084 Feet"

    let units = ["Meters", "Feet", "Inches", "Centimeters", "Kilometers", "Miles"]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("Value", text: $input)
                    .textFieldStyle(.roundedBorder)
                Picker("From", selection: $fromUnit) {
                    ForEach(units, id: \.self) { Text($0) }
                }
            }
            .padding()

            Button("Convert") { convert() }
                .buttonStyle(.borderedProminent)

            Text(result)
                .font(.title)
                .padding()

            Spacer()
        }
        .navigationTitle("Length Converter")
    }

    func convert() {
        result = "Result of converting \(input) \(fromUnit)..."
    }
}
