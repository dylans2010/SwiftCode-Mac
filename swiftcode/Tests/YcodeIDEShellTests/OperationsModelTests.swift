import Foundation
import Testing
@testable import YcodeIDECore
@testable import YcodeIDEShell

@Suite(.serialized)
@MainActor
struct OperationsModelTests {
    @Test func buildHistoryRecordsAndClears() {
        let history = OperationsBuildHistory()
        history.clearHistory()
        history.recordBuild(projectName: "Demo", duration: 12.5, warnings: 2, errors: 0, sdk: "macosx", destination: "My Mac", configuration: "Debug", status: "Succeeded")
        history.recordBuild(projectName: "Demo", duration: 9.0, warnings: 0, errors: 3, sdk: "macosx", destination: "My Mac", configuration: "Debug", status: "Failed")
        #expect(history.buildRecords.count == 2)
        #expect(history.buildRecords.first?.status == "Failed")
        #expect(history.successRate == 0.5)
        history.clearHistory()
        #expect(history.buildRecords.isEmpty)
    }

    @Test func archiveStoreRoundTrip() {
        let store = OperationsArchiveStore()
        let archive = OperationsArchive(projectName: "Demo", version: "1.2.3", buildNumber: "42")
        store.addArchive(archive)
        #expect(store.archives.contains { $0.id == archive.id })
        store.removeArchive(id: archive.id)
        #expect(!store.archives.contains { $0.id == archive.id })
    }

    @Test func notificationsMarkRead() {
        let store = OperationsNotificationStore()
        store.post(title: "Build finished", subtitle: "Demo succeeded", type: "Build")
        let note = store.notifications.first { $0.title == "Build finished" }
        #expect(note != nil)
        #expect(store.unreadCount >= 1)
        if let note { store.markRead(id: note.id) }
        #expect(store.notifications.first { $0.title == "Build finished" }?.isRead == true)
    }

    @Test func healthFactorsFromMeasuredInputs() {
        let history = OperationsBuildHistory()
        history.clearHistory()
        let factors = OperationsHealth.factors(workspaceURL: FileManager.default.temporaryDirectory, buildHistory: history, registryCount: 0)
        #expect(factors.contains { $0.name == "Disk space" && $0.healthy })
        #expect(factors.contains { $0.name == "Build success rate" })
        #expect(factors.contains { $0.name == "Project registry" && !$0.healthy })
    }

    @Test func secretScanFindsPlantedKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-ops-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exampleKey = "AKIA" + "IOSFODNN7EXAMPLE"
        try "let key = \"\(exampleKey)\"\n".write(to: dir.appendingPathComponent("Secrets.swift"), atomically: true, encoding: .utf8)
        try "nothing here\n".write(to: dir.appendingPathComponent("Clean.swift"), atomically: true, encoding: .utf8)
        let findings = OperationsSecurity.scan(root: dir)
        #expect(findings.count == 1)
        #expect(findings.first?.file == "Secrets.swift")
        #expect(findings.first?.line == 1)
    }

    @Test func secretScanSkipsGitDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-ops-scan2-\(UUID().uuidString)")
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let exampleKey = "AKIA" + "IOSFODNN7EXAMPLE"
        try "\(exampleKey)\n".write(to: gitDir.appendingPathComponent("config.txt"), atomically: true, encoding: .utf8)
        let findings = OperationsSecurity.scan(root: dir)
        #expect(findings.isEmpty)
    }
}
