import SwiftUI

struct TemperatureConverterView: View {
    @State private var input = "0"
    @State private var fromUnit = "Celsius"
    @State private var result = "32 Fahrenheit"

    let units = ["Celsius", "Fahrenheit", "Kelvin"]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("Temp", text: $input)
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
        .navigationTitle("Temperature Converter")
    }

    func convert() {
        result = "Converted \(input) \(fromUnit)"
    }
}
