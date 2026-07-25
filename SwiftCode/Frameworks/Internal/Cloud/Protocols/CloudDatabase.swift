import Foundation

public protocol CloudDatabase: AnyObject, Sendable {
    func executeRawQuery(_ query: String) async throws -> [[String: AnySendable]]
    func fetchRecords(table: String, filters: [String: AnySendable]) async throws -> [[String: AnySendable]]
    func upsertRecord(table: String, data: [String: AnySendable]) async throws
    func deleteRecord(table: String, primaryKey: String, value: AnySendable) async throws
}

// Custom wrapper to allow Any in protocol with Sendable compliance
public struct AnySendable: @unchecked Sendable, Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            self.value = boolVal
        } else if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            self.value = stringVal
        } else if let dataVal = try? container.decode(Data.self) {
            self.value = dataVal
        } else {
            self.value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let dataVal = value as? Data {
            try container.encode(dataVal)
        }
    }
}
