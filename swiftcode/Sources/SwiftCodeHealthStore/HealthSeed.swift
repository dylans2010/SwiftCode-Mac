import Foundation
import SwiftCodeSimFeatures

public struct HealthSeedResult: Equatable, Sendable, CustomStringConvertible {
    public var seeded: [String: Int] = [:]
    public var provenance: Int64 = 0
    public var madeProvenance = false

    public var total: Int { seeded.values.reduce(0, +) }
    public var description: String {
        "seeded \(total) samples (" + seeded.sorted { $0.key < $1.key }.map { "\(HealthTypes.all[$0.key]?.shortName ?? $0.key) \($0.value)" }
            .joined(separator: ", ") + ") under the system source (provenance \(provenance)\(madeProvenance ? ", new" : ""))"
    }
}

public enum HealthSeedError: Error, CustomStringConvertible, Equatable {
    case noCode(String)
    case noSystemSource
    case noProvenanceToCopy
    case notSeedable(String)

    public var description: String {
        switch self {
        case .noCode(let t): "\(t): no store type code is known for it (health-simulation.md §6.3), so it cannot be seeded"
        case .noSystemSource: "the store has no system source of this device yet (boot the device once)"
        case .noProvenanceToCopy:
            "the store has no sample provenance of this device to copy (write any sample with SwiftCode's agent first, then seed)"
        case .notSeedable(let t): "\(t) cannot be seeded"
        }
    }
}

extension HealthStore {
    public static func storedECGClassification(_ value: Int) -> Int {
        [0: 0, 1: 3, 2: 4, 3: 6, 4: 5, 5: 1, 6: 2][value] ?? 0
    }

    public func systemSourceID() throws -> Int? {
        try open().query("SELECT ROWID FROM sources WHERE local_device = 1 ORDER BY ROWID LIMIT 1").first?.first?.int
    }

    func openProtected() throws -> SQLiteDatabase {
        guard FileManager.default.fileExists(atPath: protectedPath) else { throw HealthStoreError.noStore(protectedPath) }
        return try SQLiteDatabase(path: protectedPath)
    }

    static func columns(_ db: SQLiteDatabase, _ table: String) throws -> [String] {
        try db.query("PRAGMA table_info(\(table))").compactMap { $0.count > 1 ? $0[1].text : nil }
    }

    func deviceRow(model: String) throws -> Int? {
        try open().query("SELECT ROWID FROM source_devices WHERE model = ? ORDER BY ROWID LIMIT 1", [.text(model)]).first?.first?.int
    }

    func systemProvenance(_ db: SQLiteDatabase, system: Int, model: String) throws -> (Int64, Bool) {
        if let p = try db.query("SELECT ROWID FROM data_provenances WHERE source_id = ? AND sync_provenance = 0 ORDER BY ROWID LIMIT 1",
                                [.int(Int64(system))]).first?.first?.int {
            return (Int64(p), false)
        }
        let agent = try sourceIDs(bundleID: HealthChannel.agentBundleID)
        var template: Int?
        for s in agent {
            template = try db.query("SELECT ROWID FROM data_provenances WHERE source_id = ? AND sync_provenance = 0 ORDER BY ROWID LIMIT 1",
                                    [.int(Int64(s))]).first?.first?.int
            if template != nil { break }
        }
        if template == nil {
            template = try db.query("SELECT ROWID FROM data_provenances WHERE sync_provenance = 0 ORDER BY ROWID LIMIT 1").first?.first?.int
        }
        guard let template else { throw HealthSeedError.noProvenanceToCopy }
        let cols = try Self.columns(db, "data_provenances").filter { $0 != "ROWID" }
        let list = cols.joined(separator: ", ")
        try db.query("INSERT INTO data_provenances (\(list)) SELECT \(list) FROM data_provenances WHERE ROWID = ?", [.int(Int64(template))])
        let id = db.lastInsertRowID
        try db.query("UPDATE data_provenances SET source_id = ? WHERE ROWID = ?", [.int(Int64(system)), .int(id)])
        if let device = try deviceRow(model: model) {
            try db.query("UPDATE data_provenances SET device_id = ? WHERE ROWID = ?", [.int(Int64(device)), .int(id)])
        }
        return (id, true)
    }

    @discardableResult
    public func seed(_ samples: [HealthSample], model: String, now: Date = Date()) throws -> HealthSeedResult {
        for s in samples {
            guard let t = HealthTypes.all[s.type] else { throw HealthSeedError.notSeedable(s.type) }
            guard t.storeCode != nil else { throw HealthSeedError.noCode(s.type) }
            guard t.kind == .category || t.kind == .quantity || t.identifier == HealthTypes.ecg else { throw HealthSeedError.notSeedable(s.type) }
            if t.kind == .quantity, s.storeValue() == nil { throw HealthSeedError.notSeedable("\(s.type) in \(s.unit ?? "no unit")") }
        }
        guard let system = try systemSourceID() else { throw HealthSeedError.noSystemSource }
        let db = try openProtected()
        return try db.transaction {
            var result = HealthSeedResult()
            let (prov, made) = try systemProvenance(db, system: system, model: model)
            result.provenance = prov
            result.madeProvenance = made
            let created = SQLiteDatabase.Value.real(Self.storeTime(now))
            for s in samples {
                let t = HealthTypes.all[s.type]!
                var uuid = UUID().uuid
                let bytes = withUnsafeBytes(of: &uuid) { [UInt8]($0) }
                try db.query("INSERT INTO objects (uuid, provenance, type, creation_date) VALUES (?, ?, 1, ?)", [.blob(bytes), .int(prov), created])
                let id = db.lastInsertRowID
                try db.query("INSERT INTO samples (data_id, start_date, end_date, data_type) VALUES (?, ?, ?, ?)",
                             [.int(id), .real(Self.storeTime(s.start)), .real(Self.storeTime(s.end)), .int(Int64(t.storeCode!))])
                if t.identifier == HealthTypes.ecg {
                    let bpm: Double = { if case .number(let n)? = s.metadata["averageHeartRate"] { n } else { 70 } }()
                    let symptoms: Int64 = { if case .number(let n)? = s.metadata["symptomsStatus"] { Int64(n) } else { 1 } }()
                    try db.query("INSERT INTO ecg_samples (data_id, private_classification, average_heart_rate, voltage_payload, symptoms_status) "
                                 + "VALUES (?, ?, ?, ?, ?)",
                                 [.int(id), .int(Int64(Self.storedECGClassification(Int(s.value)))), .real(bpm), .blob([]), .int(symptoms)])
                } else if t.kind == .category {
                    try db.query("INSERT INTO category_samples (data_id, value) VALUES (?, ?)", [.int(id), .int(Int64(s.value))])
                } else {
                    try db.query("INSERT INTO quantity_samples (data_id, quantity) VALUES (?, ?)", [.int(id), .real(s.storeValue()!)])
                }
                result.seeded[s.type, default: 0] += 1
            }
            return result
        }
    }
}
