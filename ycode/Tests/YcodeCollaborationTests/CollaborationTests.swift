// Tests for the collaboration + transfer port (Legacy -> YcodeCollaboration).
// Static only: not executed here (no Swift toolchain in this environment).
// No network / Multipeer involved: permission presets, the serializer
// round-trip, and the project model are pinned on local temp directories.

import Foundation
import Testing
@testable import YcodeCollaboration

@Suite("Collaboration ports")
@MainActor
struct CollaborationTests {

    @Test("TransferPermission presets: read-only can view, not edit or delete")
    func readOnlyPreset() {
        let permission = TransferPermission.makePreset(.readOnly)
        #expect(permission.allows(.viewFiles))
        #expect(!permission.allows(.editFiles))
        #expect(!permission.allows(.deleteFiles))
        #expect(!permission.allows(.terminalAccess))
    }

    @Test("TransferPermission presets: full access allows editing and terminal")
    func fullAccessPreset() {
        let permission = TransferPermission.makePreset(.fullAccess)
        #expect(permission.allows(.viewFiles))
        #expect(permission.allows(.editFiles))
        #expect(permission.allows(.deleteFiles))
        #expect(permission.allows(.terminalAccess))
        #expect(permission.allows(.buildProject))
    }

    @Test("TransferPermission presets: limited edit allows editing, not deleting")
    func limitedEditPreset() {
        let permission = TransferPermission.makePreset(.limitedEdit)
        #expect(permission.allows(.editFiles))
        #expect(!permission.allows(.deleteFiles))
    }

    @Test("TransferConfiguration JSON round-trips")
    func transferConfigurationRoundTrip() throws {
        let config = TransferConfiguration(originPeerID: "peer-1",
                                           permission: TransferPermission.makePreset(.readOnly),
                                           lastTransferSessionID: UUID(),
                                           lastTransferDate: Date())
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TransferConfiguration.self, from: data)
        #expect(decoded == config)
    }

    @Test("CollaborationProject counts files under its directory")
    func collaborationProjectFileCount() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "a".write(to: dir.appendingPathComponent("Sources/a.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent("Sources/b.swift"), atomically: true, encoding: .utf8)
        let project = CollaborationProject(name: "Demo", directoryURL: dir)
        #expect(project.fileCount == 2)
    }

    @Test("ProjectTransferSerializer round-trips a project and rejects tampering")
    func serializerRoundTrip() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let project = CollaborationProject(name: "Demo", directoryURL: dir)
        let serializer = ProjectTransferSerializer()
        let data = try serializer.serialize(project: project, permission: TransferPermission.makePreset(.readOnly))
        let package = try serializer.deserialize(data)
        #expect(package.project.name == "Demo")
        #expect(package.fileEntries.contains(where: { $0.relativePath == "main.swift" && !$0.isDirectory }))
        #expect(package.checksum.count == 64)

        // Tamper with the recorded checksum (not the payload bytes, which
        // would break JSON decoding instead): the checksum must reject it.
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["checksum"] = String(repeating: "0", count: 64)
        let tampered = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: ProjectSerializationError.self) {
            try serializer.deserialize(tampered)
        }
    }
}
