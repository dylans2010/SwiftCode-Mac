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

                VStack(spacing: 6) {
                    Text(request.deviceName)
                        .font(.headline)
                    Text("\(request.deviceModel) • SwiftCode iOS")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Text("Pairing Code")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(request.verificationCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Text("Does this code match the iPhone?")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Reject") {
                        pairingManager.declinePairing()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                    Button("Approve") {
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
