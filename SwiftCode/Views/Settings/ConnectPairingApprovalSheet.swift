import SwiftUI

struct ConnectPairingApprovalSheet: View {
    @Bindable var pairingManager = PairingManager.shared

    var body: some View {
        if let request = pairingManager.activePairingRequest {
            VStack(spacing: 16) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)

                Text("SwiftCode Connect")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)

                Text("New Device Request")
                    .font(.title2)
                    .bold()

                VStack(spacing: 4) {
                    Text(request.deviceName)
                        .font(.headline)
                    Text("\(request.deviceModel) • Code: \(request.verificationCode)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Text("Wants to connect to SwiftCode macOS as an authoritative controller.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Decline") {
                        pairingManager.declinePairing()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                    Button("Allow & Trust") {
                        pairingManager.approvePairing()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }
}
