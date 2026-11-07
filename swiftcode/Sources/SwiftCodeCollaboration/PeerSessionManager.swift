import Foundation
import MultipeerConnectivity

@MainActor
public final class PeerSessionManager: NSObject, ObservableObject {
    public static let shared = PeerSessionManager()

    @Published public private(set) var nearbyPeers: [MCPeerID] = []
    @Published public private(set) var peerStates: [String: MCSessionState] = [:]

    let localPeerID = MCPeerID(displayName: Host.current().localizedName ?? "macOS Device")
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

    public func invite(_ peer: MCPeerID) {
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
    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let safeHandler = invitationHandler
        Task { @MainActor in safeHandler(true, self.session) }
    }

    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { Task { @MainActor in self.nearbyPeers.removeAll { $0 == peerID } } }
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in if !self.nearbyPeers.contains(peerID) { self.nearbyPeers.append(peerID) } }
    }

    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) { Task { @MainActor in self.peerStates[peerID.displayName] = state } }
    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) { Task { @MainActor in self.onData?(data, peerID) } }
    public nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { Task { @MainActor in self.onResourceProgress?(resourceName, progress, peerID) } }
    public nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    public nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) { certificateHandler(true) }
}

extension MCPeerID: @retroactive @unchecked Sendable {}
