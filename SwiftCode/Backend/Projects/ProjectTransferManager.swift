import Foundation
import MultipeerConnectivity

@MainActor
final class ProjectTransferManager: ObservableObject {
    static let shared = ProjectTransferManager()

    @Published private(set) var sessions: [TransferSession] = []
    @Published private(set) var incomingSession: TransferSession?
    @Published private(set) var lastError: String?

    private let serializer = ProjectSerializer()
    private let chunkSize = 256_000
    private var stagedPayloads: [UUID: Data] = [:]
    private var pendingChunks: [UUID: [Int: Data]] = [:]
    private var expectedChunks: [UUID: Int] = [:]

    private init() {
        PeerSessionManager.shared.onData = { [weak self] data, peer in
            Task { @MainActor in self?.receive(data: data, from: peer) }
        }
    }

    func startTransfer(project: Project, to peer: MCPeerID, permission: TransferPermission) async throws {
        let session = TransferSession(
            projectID: project.id,
            projectName: project.name,
            sender: .init(peerID: PeerSessionManager.shared.localPeerID.displayName, displayName: PeerSessionManager.shared.localPeerID.displayName),
            receiver: .init(peerID: peer.displayName, displayName: peer.displayName),
            permission: permission,
            state: .connecting,
            totalFiles: project.fileCount
        )
        sessions.insert(session, at: 0)
        let encoded = try serializer.serialize(project: project, permission: permission)
        stagedPayloads[session.id] = encoded
        try await transmit(sessionID: session.id, payload: encoded, to: peer)
    }

    func respondToIncoming(accept: Bool) {
        guard var session = incomingSession else { return }
        session.state = accept ? .authorizing : .rejected
        update(session)
        incomingSession = nil
    }

    func permission(for project: Project) -> TransferPermission {
        project.transferConfiguration?.permission ?? .owner
    }

    private func transmit(sessionID: UUID, payload: Data, to peer: MCPeerID) async throws {
        let totalChunks = Int(ceil(Double(payload.count) / Double(chunkSize)))
        for index in 0..<totalChunks {
            let start = index * chunkSize
            let end = min(start + chunkSize, payload.count)
            let chunk = payload.subdata(in: start..<end)
            let envelope = TransferEnvelope(sessionID: sessionID, index: index, total: totalChunks, payload: chunk)
            try PeerSessionManager.shared.send(try JSONEncoder().encode(envelope), to: [peer])
            updateProgress(for: sessionID, totalBytes: Int64(payload.count), chunkBytes: Int64(chunk.count), completedFiles: 0)
        }
    }

    private func receive(data: Data, from peer: MCPeerID) {
        do {
            let envelope = try JSONDecoder().decode(TransferEnvelope.self, from: data)
            pendingChunks[envelope.sessionID, default: [:]][envelope.index] = envelope.payload
            expectedChunks[envelope.sessionID] = envelope.total
            var session = sessions.first(where: { $0.id == envelope.sessionID }) ?? TransferSession(
                id: envelope.sessionID,
                projectID: UUID(),
                projectName: "Incoming Project",
                sender: .init(peerID: peer.displayName, displayName: peer.displayName),
                permission: .makePreset(.readOnly),
                state: .authorizing
            )
            if incomingSession == nil { incomingSession = session }
            let assembledCount = pendingChunks[envelope.sessionID]?.count ?? 0
            session.progress = Double(assembledCount) / Double(max(envelope.total, 1))
            update(session)
            if assembledCount == envelope.total {
                let payload = (0..<envelope.total).compactMap { pendingChunks[envelope.sessionID]?[$0] }.reduce(into: Data(), { $0.append($1) })
                let package = try serializer.deserialize(payload)
                try importPackage(package, peer: peer, sessionID: envelope.sessionID)
                pendingChunks.removeValue(forKey: envelope.sessionID)
                expectedChunks.removeValue(forKey: envelope.sessionID)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func importPackage(_ package: SerializedProjectPackage, peer: MCPeerID, sessionID: UUID) throws {
        var project = package.project
        project.name = uniqueProjectName(for: project.name)
        let projectURL = ProjectManager.shared.projectsDirectory.appendingPathComponent(project.name)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true, attributes: nil)
        for entry in package.fileEntries {
            let fileURL = projectURL.appendingPathComponent(entry.relativePath)
            if entry.isDirectory {
                try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true, attributes: nil)
            } else {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try entry.data.write(to: fileURL)
            }
        }
        project.transferConfiguration = .init(originPeerID: peer.displayName, permission: package.permission, lastTransferSessionID: sessionID, lastTransferDate: Date())
        project.files = ProjectManager.shared.rebuildFileTree(at: projectURL)
        try ProjectManager.shared.saveImportedProject(project)
        var completed = sessions.first(where: { $0.id == sessionID })
        completed?.projectName = project.name
        completed?.state = .completed
        completed?.progress = 1
        completed?.permission = package.permission
        if let completed { update(completed) }
    }

    private func uniqueProjectName(for base: String) -> String {
        var candidate = base
        var counter = 2
        while FileManager.default.fileExists(atPath: ProjectManager.shared.projectsDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    private func updateProgress(for sessionID: UUID, totalBytes: Int64, chunkBytes: Int64, completedFiles: Int) {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.bytesTransferred += chunkBytes
        session.totalBytes = totalBytes
        session.progress = totalBytes == 0 ? 0 : Double(session.bytesTransferred) / Double(totalBytes)
        session.transferredFiles = completedFiles
        session.state = session.progress >= 1 ? .completed : .transferring
        session.lastUpdated = Date()
        update(session)
    }

    private func update(_ session: TransferSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }
}

private struct TransferEnvelope: Codable {
    let sessionID: UUID
    let index: Int
    let total: Int
    let payload: Data
}
