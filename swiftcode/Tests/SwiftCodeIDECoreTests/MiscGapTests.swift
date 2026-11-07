import Foundation
import StoreKitConfiguration
import StoreKitEngine
import SwiftCodeDebug
import SwiftCodeHealthStore
import SwiftCodeLanguage
import Testing
@testable import SwiftCodeIDECore

@Suite("Misc gap tests — StoreKit, CSV, SQLite, LSP")
struct MiscGapTests {

    @Suite("StoreKit simulation session")
    struct StoreKitSimulationTests {
        private static let coins = ConfiguredProduct(
            type: .consumable, productID: "com.example.coins100",
            referenceName: "100 Coins", internalID: "1", displayPrice: "0.99")
        private static let monthly = ConfiguredProduct(
            type: .recurringSubscription, productID: "com.example.pro_monthly",
            referenceName: "Pro Monthly", internalID: "2", displayPrice: "4.99",
            subscriptionGroupID: "1", recurringSubscriptionPeriod: "P1M")

        private static func testConfiguration() -> StoreConfiguration {
            StoreConfiguration(
                identifier: "test",
                products: [coins],
                subscriptionGroups: [
                    SubscriptionGroup(id: "1", name: "Pro", subscriptions: [monthly]),
                ])
        }

        private static func makeSession(clock: ManualClock? = nil) -> (StoreKitSimulationSession, ManualClock) {
            let clock = clock ?? ManualClock(Date())
            let session = StoreKitSimulationSession(cacheDirectory: nil, clock: clock)
            return (session, clock)
        }

        @Test("A purchase with no configuration installed is blocked, not invented")
        func purchaseWithoutConfigurationBlocked() {
            let (session, _) = Self.makeSession()
            session.executePurchase(product: Self.coins)
            #expect(session.transactions.isEmpty)
            #expect(session.entitlements.isEmpty)
            #expect(session.activityEvents.contains { $0.title == "Purchase Blocked" })
        }

        @Test("An offline purchase is blocked before the store is touched")
        func offlinePurchaseBlocked() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.isOfflineMode = true
            session.executePurchase(product: Self.coins)
            #expect(session.transactions.isEmpty)
            #expect(session.activityEvents.contains {
                $0.title == "Purchase Blocked" && $0.message.contains("offline")
            })
        }

        @Test("A consumable purchase records a transaction and an entitlement")
        func consumablePurchaseSucceeds() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.executePurchase(product: Self.coins)
            #expect(session.transactions.count == 1)
            #expect(session.transactions.first?.productID == "com.example.coins100")
            #expect(session.transactions.first?.purchaseState == "purchased")
            #expect(session.entitlements.contains { $0.productID == "com.example.coins100" && $0.isActive })
            #expect(session.activityEvents.contains { $0.title == "Transaction Successful" })
        }

        @Test("A simulated network failure blocks the purchase honestly")
        func networkFailureBlocksPurchase() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.shouldSimulateNetworkFailure = true
            session.executePurchase(product: Self.coins)
            #expect(session.transactions.isEmpty)
            #expect(session.activityEvents.contains {
                $0.title == "Purchase Blocked" && $0.message.contains("Simulated network failure")
            })
        }

        @Test("Ask to Buy pends the purchase until the parent approves it")
        func askToBuyPendsThenApproves() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.isAskToBuyEnabled = true
            session.executePurchase(product: Self.coins)
            let pending = session.transactions.first { $0.purchaseState == "pending" }
            #expect(pending != nil)
            #expect(session.activityEvents.contains { $0.title == "Ask To Buy Sent" })
            #expect(session.entitlements.contains { $0.productID == "com.example.coins100" } == false)
            session.approvePendingTransaction(id: pending!.id)
            #expect(session.transactions.first?.purchaseState == "purchased")
            #expect(session.entitlements.contains { $0.productID == "com.example.coins100" && $0.isActive })
        }

        @Test("A declined Ask to Buy leaves no purchase behind")
        func askToBuyDeclineLeavesNothing() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.isAskToBuyEnabled = true
            session.executePurchase(product: Self.coins)
            let pending = session.transactions.first { $0.purchaseState == "pending" }
            #expect(pending != nil)
            session.declinePendingTransaction(id: pending!.id)
            #expect(session.transactions.contains { $0.purchaseState == "purchased" } == false)
            #expect(session.entitlements.isEmpty)
        }

        @Test("A refund marks the transaction refunded and drops the entitlement")
        func refundMarksRefunded() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.executePurchase(product: Self.coins)
            #expect(session.transactions.first?.purchaseState == "purchased")
            session.triggerRefund(productID: "com.example.coins100")
            #expect(session.transactions.first?.purchaseState == "refunded")
            #expect(session.entitlements.contains { $0.productID == "com.example.coins100" } == false)
            #expect(session.activityEvents.contains { $0.title == "Purchase Refunded" })
        }

        @Test("Expiring a subscription deactivates its entitlement")
        func expirationDeactivatesEntitlement() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.executePurchase(product: Self.monthly)
            #expect(session.entitlements.contains { $0.productID == "com.example.pro_monthly" && $0.isActive })
            session.simulateExpiration(productID: "com.example.pro_monthly")
            #expect(session.entitlements.contains { $0.productID == "com.example.pro_monthly" } == false)
            #expect(session.transactions.first { $0.productID == "com.example.pro_monthly" }?.subscriptionCycleState == "Expired")
            #expect(session.activityEvents.contains { $0.title == "Subscription Expired" })
        }

        @Test("Time travel past the period renews the subscription")
        func timeTravelRenewsSubscription() {
            let clock = ManualClock(Date())
            let (session, _) = Self.makeSession(clock: clock)
            session.installConfiguration(Self.testConfiguration())
            session.executePurchase(product: Self.monthly)
            #expect(session.transactions.count == 1)
            clock.advance(by: 40 * 24 * 60 * 60)
            session.advanceSimulation()
            #expect(session.transactions.contains { $0.subscriptionCycleState == "Renewal" })
            #expect(session.entitlements.contains { $0.productID == "com.example.pro_monthly" && $0.isActive })
        }

        @Test("Reset clears transactions and entitlements")
        func resetClearsAll() {
            let (session, _) = Self.makeSession()
            session.installConfiguration(Self.testConfiguration())
            session.executePurchase(product: Self.coins)
            #expect(!session.transactions.isEmpty)
            session.resetSimulator()
            #expect(session.transactions.isEmpty)
            #expect(session.entitlements.isEmpty)
        }

        @Test("The four built-in scenario profiles are present")
        func builtInProfilesPresent() {
            let (session, _) = Self.makeSession()
            #expect(session.availableProfiles.contains { $0.name == "SaaS Premium Subscriber" })
            #expect(session.availableProfiles.contains { $0.name == "Child Sandbox Account" && $0.isAskToBuy })
            #expect(session.availableProfiles.contains { $0.name == "Offline Airplane Mode" && $0.isOffline })
            #expect(session.availableProfiles.contains { $0.name == "JWS Cryptographic Failure" && $0.failJWSVerification })
        }
    }

    @Suite("CSV parser edge cases")
    struct CSVParserTests {
        @Test("A plain table parses row by row")
        func plainTable() throws {
            let rows = try DatabaseCSVParser.parse("a,b,c\n1,2,3\n")
            #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
        }

        @Test("Quoted fields keep commas, and doubled quotes become one")
        func quotedFields() throws {
            let rows = try DatabaseCSVParser.parse("name,note\n\"Doe, Jane\",\"said \"\"hi\"\"\"\n")
            #expect(rows[1] == ["Doe, Jane", "said \"hi\""])
        }

        @Test("Quoted fields may contain newlines")
        func embeddedNewlines() throws {
            let rows = try DatabaseCSVParser.parse("a,b\n\"line one\nline two\",2\n")
            #expect(rows.count == 2)
            #expect(rows[1][0] == "line one\nline two")
        }

        @Test("CRLF and CR line endings parse like LF")
        func lineEndings() throws {
            #expect(try DatabaseCSVParser.parse("a,b\r\n1,2\r\n") == [["a", "b"], ["1", "2"]])
            #expect(try DatabaseCSVParser.parse("a,b\r1,2\r") == [["a", "b"], ["1", "2"]])
        }

        @Test("Empty fields and trailing commas are kept")
        func emptyFields() throws {
            let rows = try DatabaseCSVParser.parse("a,,c\n,,\n")
            #expect(rows[0] == ["a", "", "c"])
            #expect(rows[1] == ["", "", ""])
        }

        @Test("An unterminated quote throws instead of returning a partial row")
        func unterminatedQuoteThrows() {
            #expect(throws: DatabaseCSVError.unterminatedQuote) {
                try DatabaseCSVParser.parse("a,b\n\"oops,2\n")
            }
        }

        @Test("Empty input throws instead of returning no rows")
        func emptyInputThrows() {
            #expect(throws: DatabaseCSVError.emptyInput) {
                try DatabaseCSVParser.parse("")
            }
        }
    }

    @Suite("SQLite value model and backups")
    struct SQLiteModelTests {
        @Test("The value model round-trips through an in-memory database")
        func inMemoryRoundTrip() throws {
            let db = try SQLiteDatabase(path: ":memory:", create: true)
            try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL, data BLOB)")
            let rows = try db.query(
                "INSERT INTO t (name, score, data) VALUES (?, ?, ?) RETURNING id, name, score, data",
                [.text("hello"), .real(1.5), .blob([0x01, 0x02])])
            #expect(rows.count == 1)
            #expect(rows[0][0].int == 1)
            #expect(rows[0][1].text == "hello")
            #expect(rows[0][2].real == 1.5)
            #expect(rows[0][3] == .blob([0x01, 0x02]))
            let selected = try db.query("SELECT name FROM t WHERE id = ?", [.int(1)])
            #expect(selected == [[.text("hello")]])
        }

        @Test("A bad statement throws instead of returning partial rows")
        func badStatementThrows() throws {
            let db = try SQLiteDatabase(path: ":memory:", create: true)
            #expect(throws: HealthStoreError.self) {
                try db.query("SELECT * FROM no_such_table")
            }
        }

        @Test("DatabaseSQL quotes identifiers and renders literals")
        func sqlHelpers() {
            #expect(DatabaseSQL.quoted("plain") == "\"plain\"")
            #expect(DatabaseSQL.quoted("we\"ird") == "\"we\"\"ird\"")
            #expect(DatabaseSQL.literal(.null) == "NULL")
            #expect(DatabaseSQL.literal(.int(42)) == "42")
            #expect(DatabaseSQL.literal(.text("o'clock")) == "'o''clock'")
            #expect(DatabaseSQL.literal(.blob([0xAB, 0x00])) == "X'ab00'")
        }

        @Test("Backup, modify, restore round-trips a temp database file")
        func backupRestoreRoundTrip() throws {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-db-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let dbPath = dir.appendingPathComponent("app.db").path
            try "version-one".write(toFile: dbPath, atomically: true, encoding: .utf8)
            let manager = DatabaseBackupManager(databasePath: dbPath, backupDirectory: dir)
            let backup = try manager.createBackup(date: Date(timeIntervalSince1970: 1_000_000))
            #expect(manager.listBackups().count == 1)
            #expect(backup.sizeBytes == Int64("version-one".utf8.count))
            try "version-two".write(toFile: dbPath, atomically: true, encoding: .utf8)
            try manager.restore(backup)
            #expect(try String(contentsOfFile: dbPath, encoding: .utf8) == "version-one")
        }

        @Test("Prune keeps the newest backups and deletes the rest")
        func pruneKeepsNewest() throws {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-db-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let dbPath = dir.appendingPathComponent("app.db").path
            try "v1".write(toFile: dbPath, atomically: true, encoding: .utf8)
            let manager = DatabaseBackupManager(databasePath: dbPath, backupDirectory: dir)
            _ = try manager.createBackup(date: Date(timeIntervalSince1970: 1_000_000))
            _ = try manager.createBackup(date: Date(timeIntervalSince1970: 2_000_000))
            _ = try manager.createBackup(date: Date(timeIntervalSince1970: 3_000_000))
            #expect(manager.listBackups().count == 3)
            #expect(try manager.prune(keeping: 1) == 2)
            #expect(manager.listBackups().count == 1)
        }
    }

    @Suite("LSP client")
    struct LSPClientTests {
        @Test("Initialize against a process that exits immediately fails instead of hanging")
        func initializeAgainstDeadProcessFails() async throws {
            let transport = ProcessTransport(executable: "/usr/bin/false")
            let client = try LSPClient(transport: transport)
            defer { client.close() }
            let root = FileManager.default.temporaryDirectory
            await #expect(throws: Error.self) {
                try await client.initialize(root: root)
            }
        }
    }
}
