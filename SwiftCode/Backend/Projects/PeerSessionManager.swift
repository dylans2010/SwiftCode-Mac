import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class PeerSessionManager: NSObject, ObservableObject {
    static let shared = PeerSessionManager()

    @Published private(set) var nearbyPeers: [MCPeerID] = []
    @Published private(set) var peerStates: [String: MCSessionState] = [:]

    let localPeerID = MCPeerID(displayName: UIDevice.current.name)
    private let serviceType = "swiftcode-p2p"
    let session: MCSession
    private lazy var advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: ["role": "swiftcode"], serviceType: serviceType)
    private lazy var browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)

    var onData: ((Data, MCPeerID) -> Void)?
    var onResourceProgress: ((String, Progress, MCPeerID) -> Void)?

    private override init() {
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func invite(_ peer: MCPeerID) {
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func send(_ data: Data, to peers: [MCPeerID]) throws {
        guard !peers.isEmpty else { return }
        try session.send(data, toPeers: peers, with: .reliable)
    }

    func sendDataToAll(_ data: Data) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        try? send(data, to: peers)
    }
}

extension PeerSessionManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in invitationHandler(true, self.session) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { Task { @MainActor in self.nearbyPeers.removeAll { $0 == peerID } } }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in if !self.nearbyPeers.contains(peerID) { self.nearbyPeers.append(peerID) } }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) { Task { @MainActor in self.peerStates[peerID.displayName] = state } }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) { Task { @MainActor in self.onData?(data, peerID) } }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { Task { @MainActor in self.onResourceProgress?(resourceName, progress, peerID) } }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) { certificateHandler(true) }
}
