import SwiftUI
import Network

struct PortScannerView: View {
    @State private var host = "127.0.0.1"
    @State private var startPort = 80
    @State private var endPort = 100
    @State private var results = "Results will appear here..."
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 20) {
            Form {
                TextField("Host", text: $host)
                HStack {
                    VStack {
                        Text("Start Port")
                        TextField("80", value: $startPort, format: .number)
                    }
                    VStack {
                        Text("End Port")
                        TextField("100", value: $endPort, format: .number)
                    }
                }
            }
            .padding()

            Button(isScanning ? "Scanning..." : "Start Scan") { scan() }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)

            ScrollView {
                Text(results)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding()

            Spacer()
        }
        .navigationTitle("Port Scanner")
    }

    func scan() {
        isScanning = true
        results = "Scanning ports on \(host)...\n"

        let group = DispatchGroup()
        let ports = Array(startPort...endPort)

        for port in ports {
            group.enter()
            checkPort(host: host, port: NWEndpoint.Port(integerLiteral: UInt16(port))) { isOpen in
                DispatchQueue.main.async {
                    results += "Port \(port): \(isOpen ? "OPEN" : "CLOSED")\n"
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            isScanning = false
            results += "\nScan complete."
        }
    }

    func checkPort(host: String, port: NWEndpoint.Port, completion: @escaping (Bool) -> Void) {
        let hostEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        let connection = NWConnection(to: hostEndpoint, using: .tcp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completion(true)
                connection.cancel()
            case .failed(_):
                completion(false)
                connection.cancel()
            case .waiting(_):
                // In a real scan we might timeout
                break
            default:
                break
            }
        }

        connection.start(queue: .global())

        // Timeout after 2 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if connection.state != .ready {
                connection.cancel()
                completion(false)
            }
        }
    }
}
