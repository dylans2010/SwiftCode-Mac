import SwiftUI

struct WeightConverterView: View {
    @State private var input = "1"
    @State private var fromUnit = "Kilograms"
    @State private var result = "2.20462 Pounds"

    let units = ["Kilograms", "Pounds", "Grams", "Ounces"]

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
        .navigationTitle("Weight Converter")
    }

    func convert() {
        result = "Converted \(input) \(fromUnit)"
    }
}
