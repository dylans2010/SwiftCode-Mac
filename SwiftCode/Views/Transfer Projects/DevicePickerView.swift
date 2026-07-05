import SwiftUI
import MultipeerConnectivity

struct DevicePickerView: View {
    @Binding var selectedPeer: MCPeerID?
    @StateObject private var peerManager = PeerSessionManager.shared

    var body: some View {
        List(peerManager.nearbyPeers, id: \.displayName) { peer in
            Button {
                selectedPeer = peer
                peerManager.invite(peer)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(peer.displayName)
                        Text(stateText(peer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedPeer == peer {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle("Nearby Devices")
    }

    private func stateText(_ peer: MCPeerID) -> String {
        switch peerManager.peerStates[peer.displayName] ?? .notConnected {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .notConnected: return "Available"
        @unknown default: return "Unknown"
        }
    }
}
