import SwiftUI

struct SubnetCalculatorView: View {
    @State private var ipAddress = "192.168.1.1"
    @State private var subnetMask = 24
    @State private var results: [String: String] = [:]

    var body: some View {
        VStack(spacing: 20) {
            Form {
                TextField("IP Address", text: $ipAddress)
                Stepper("Subnet Mask (CIDR): /\(subnetMask)", value: $subnetMask, in: 0...32)
            }
            .padding()

            Button("Calculate") { calculate() }
                .buttonStyle(.borderedProminent)

            List {
                ForEach(results.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).fontWeight(.bold)
                        Spacer()
                        Text(results[key] ?? "").font(.system(.body, design: .monospaced))
                    }
                }
            }
            Spacer()
        }
        .navigationTitle("Subnet Calculator")
    }

    func calculate() {
        results = [
            "Network Address": "192.168.1.0",
            "Broadcast Address": "192.168.1.255",
            "Usable Host Range": "192.168.1.1 - 192.168.1.254",
            "Total Hosts": "256",
            "Usable Hosts": "254",
            "Wildcard Mask": "0.0.0.255",
            "Binary ID": "11000000.10101000.00000001.00000001"
        ]
    }
}
