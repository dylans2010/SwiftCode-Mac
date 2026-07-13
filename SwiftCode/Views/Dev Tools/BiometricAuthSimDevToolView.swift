import SwiftUI
import os.log

@Observable
@MainActor
final class BiometricAuthSimViewModel {
    var authLogs: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BiometricAuthSim")

    func triggerBiometrics(success: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        if success {
            authLogs.insert("[\(timestamp)] LAContext: Success (User authorized successfully)", at: 0)
            logger.info("Biometric Auth Sim: Simulated Success")
        } else {
            authLogs.insert("[\(timestamp)] LAContext: Error (BiometryLockout / UserCancel)", at: 0)
            logger.warning("Biometric Auth Sim: Simulated Error")
        }
    }
}

struct BiometricAuthSimDevToolView: View {
    @State private var viewModel = BiometricAuthSimViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Simulate LocalAuthentication FaceID/TouchID prompt responses for simulator workflows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(action: { viewModel.triggerBiometrics(success: true) }) {
                        Label("Simulate Success", systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: { viewModel.triggerBiometrics(success: false) }) {
                        Label("Simulate Failure", systemImage: "exclamationmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Spacer()

                    Button("Clear logs") {
                        viewModel.authLogs.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(viewModel.authLogs, id: \.self) { log in
                HStack {
                    Image(systemName: "shield.fill")
                        .foregroundColor(log.contains("Success") ? .green : .red)
                    Text(log)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("Biometric Authentication Simulator")
    }
}
