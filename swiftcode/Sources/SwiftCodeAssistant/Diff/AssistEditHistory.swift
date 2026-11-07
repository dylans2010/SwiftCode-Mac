import Foundation
import Observation
import os

public enum TransactionStatus: String, Codable, Sendable {
    case staged
    case applied
    case reverted
}

public struct EditTransaction: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let turnId: UUID
    public let conversationId: UUID
    public let timestamp: Date
    public let filePath: String
    public let originalContent: String
    public let modifiedContent: String
    public let diffResult: UnifiedDiffResult
    public var status: TransactionStatus
    public let summary: String

    public init(
        id: UUID = UUID(),
        turnId: UUID = UUID(),
        conversationId: UUID,
        timestamp: Date = Date(),
        filePath: String,
        originalContent: String,
        modifiedContent: String,
        diffResult: UnifiedDiffResult,
        status: TransactionStatus = .applied,
        summary: String? = nil
    ) {
        self.id = id
        self.turnId = turnId
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.filePath = filePath
        self.originalContent = originalContent
        self.modifiedContent = modifiedContent
        self.diffResult = diffResult
        self.status = status
        let name = (filePath as NSString).lastPathComponent
        self.summary = summary ?? "+\(diffResult.addedLines)/-\(diffResult.removedLines) in \(name)"
    }
}

public typealias CodingAssistantEditHistory = AssistEditHistory

@MainActor
@Observable
public final class AssistEditHistory {
    public static let shared = AssistEditHistory()

    public private(set) var transactions: [EditTransaction] = []

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistEditHistory")

    public var storageDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftCode/EditHistory", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var ledgerFileURL: URL {
        storageDirectoryURL.appendingPathComponent("ledger.json")
    }

    public init() {
        loadLedger()
    }

    @discardableResult
    public func recordEdit(
        conversationId: UUID,
        turnId: UUID = UUID(),
        filePath: String,
        originalContent: String,
        modifiedContent: String
    ) -> EditTransaction {
        let diff = AssistDiffEngine.shared.createUnifiedDiff(
            filePath: filePath,
            oldContent: originalContent,
            newContent: modifiedContent
        )
        let tx = EditTransaction(
            turnId: turnId,
            conversationId: conversationId,
            filePath: filePath,
            originalContent: originalContent,
            modifiedContent: modifiedContent,
            diffResult: diff,
            status: .applied
        )
        transactions.append(tx)
        saveLedger()
        return tx
    }

    public func transactions(for conversationId: UUID) -> [EditTransaction] {
        transactions.filter { $0.conversationId == conversationId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func transactions(for filePath: String) -> [EditTransaction] {
        transactions.filter { $0.filePath == filePath }
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func transaction(by id: UUID) -> EditTransaction? {
        transactions.first(where: { $0.id == id })
    }

    @discardableResult
    public func revert(transactionId: UUID) throws -> String {
        guard let idx = transactions.firstIndex(where: { $0.id == transactionId }) else {
            throw DiffConflictError.targetNotFound(target: transactionId.uuidString, file: "ledger")
        }
        transactions[idx].status = .reverted
        saveLedger()
        return transactions[idx].originalContent
    }

    @discardableResult
    public func reapply(transactionId: UUID) throws -> String {
        guard let idx = transactions.firstIndex(where: { $0.id == transactionId }) else {
            throw DiffConflictError.targetNotFound(target: transactionId.uuidString, file: "ledger")
        }
        transactions[idx].status = .applied
        saveLedger()
        return transactions[idx].modifiedContent
    }

    public func clear(for conversationId: UUID) {
        transactions.removeAll(where: { $0.conversationId == conversationId })
        saveLedger()
    }

    public func clearAll() {
        transactions.removeAll()
        saveLedger()
    }

    public func exportLedger() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(transactions)) ?? Data()
    }

    public func importLedger(from data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let imported = try? decoder.decode([EditTransaction].self, from: data) {
            self.transactions = imported
            saveLedger()
        }
    }

    private func saveLedger() {
        let data = exportLedger()
        try? data.write(to: ledgerFileURL, options: .atomic)
    }

    private func loadLedger() {
        guard fileManager.fileExists(atPath: ledgerFileURL.path),
              let data = try? Data(contentsOf: ledgerFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([EditTransaction].self, from: data) {
            self.transactions = loaded
        }
    }
}
