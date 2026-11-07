import Foundation
import Testing
@testable import YcodeAssistant

@Suite struct AssistEditHistoryTests {
    @Test @MainActor func recordsEditTransactionAndGeneratesDiff() {
        let history = AssistEditHistory()
        let convId = UUID()
        let turnId = UUID()
        let filePath = "/path/to/Sample.swift"
        let original = "func greet() {\n    print(\"Hello\")\n}\n"
        let modified = "func greet() {\n    print(\"Hello, World!\")\n}\n"

        let tx = history.recordEdit(
            conversationId: convId,
            turnId: turnId,
            filePath: filePath,
            originalContent: original,
            modifiedContent: modified
        )

        #expect(tx.conversationId == convId)
        #expect(tx.turnId == turnId)
        #expect(tx.filePath == filePath)
        #expect(tx.diffResult.addedLines > 0)
        #expect(tx.diffResult.removedLines > 0)
        #expect(tx.status == .applied)

        let byConv = history.transactions(for: convId)
        #expect(byConv.count == 1)
        #expect(byConv.first?.id == tx.id)

        let byFile = history.transactions(for: filePath)
        #expect(byFile.count == 1)

        let reverted = try? history.revert(transactionId: tx.id)
        #expect(reverted == original)
        #expect(history.transaction(by: tx.id)?.status == .reverted)

        let reapplied = try? history.reapply(transactionId: tx.id)
        #expect(reapplied == modified)
        #expect(history.transaction(by: tx.id)?.status == .applied)

        let data = history.exportLedger()
        #expect(!data.isEmpty)

        history.clear(for: convId)
        #expect(history.transactions(for: convId).isEmpty)
    }
}
