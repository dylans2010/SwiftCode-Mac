import Foundation

public indirect enum EntitlementValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case date(Date)
    case data(Data)
    case array([EntitlementValue])
    case dictionary([String: EntitlementValue])

    public init?(propertyList value: Any) {
        switch value {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            let type = String(cString: n.objCType)
            if type == "c" || type == "B" { self = .bool(n.boolValue) }
            else if type == "d" || type == "f" { self = .real(n.doubleValue) }
            else { self = .integer(n.intValue) }
        case let d as Date: self = .date(d)
        case let d as Data: self = .data(d)
        case let a as [Any]:
            var out: [EntitlementValue] = []
            for e in a {
                guard let v = EntitlementValue(propertyList: e) else { return nil }
                out.append(v)
            }
            self = .array(out)
        case let d as [String: Any]:
            var out: [String: EntitlementValue] = [:]
            for (k, e) in d {
                guard let v = EntitlementValue(propertyList: e) else { return nil }
                out[k] = v
            }
            self = .dictionary(out)
        default: return nil
        }
    }

    public var propertyList: Any {
        switch self {
        case .string(let s): s
        case .bool(let b): NSNumber(value: b)
        case .integer(let i): NSNumber(value: i)
        case .real(let d): NSNumber(value: d)
        case .date(let d): d
        case .data(let d): d
        case .array(let a): a.map(\.propertyList)
        case .dictionary(let d): d.mapValues(\.propertyList)
        }
    }

    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var arrayValue: [EntitlementValue]? { if case .array(let a) = self { a } else { nil } }
    public var dictionaryValue: [String: EntitlementValue]? { if case .dictionary(let d) = self { d } else { nil } }
    public var dateValue: Date? { if case .date(let d) = self { d } else { nil } }
    public var dataValue: Data? { if case .data(let d) = self { d } else { nil } }
    public var strings: [String] {
        switch self {
        case .string(let s): [s]
        case .array(let a): a.compactMap(\.stringValue)
        default: []
        }
    }
}

public typealias Entitlements = [String: EntitlementValue]

public enum PropertyListError: Error, Equatable, CustomStringConvertible {
    case notADictionary
    case unreadable(String)

    public var description: String {
        switch self {
        case .notADictionary: "the property list is not a dictionary"
        case .unreadable(let why): "the property list cannot be read: \(why)"
        }
    }
}

public extension Dictionary where Key == String, Value == EntitlementValue {
    static func fromPropertyList(_ data: Data) throws -> Entitlements {
        let object: Any
        do { object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) } catch {
            throw PropertyListError.unreadable("\(error)")
        }
        guard case .dictionary(let d)? = EntitlementValue(propertyList: object) else { throw PropertyListError.notADictionary }
        return d
    }

    func xmlPropertyList() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: mapValues(\.propertyList), format: .xml, options: 0)
    }

    func overlaid(with other: Entitlements) -> Entitlements {
        merging(other) { _, new in new }
    }
}
