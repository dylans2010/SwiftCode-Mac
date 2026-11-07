import Foundation
import SwiftCodePlist

public struct PBXObject: Equatable, Sendable {
    public var id: String
    public var attributes: PlistDictionary

    public init(id: String, attributes: PlistDictionary) {
        self.id = id
        self.attributes = attributes
    }

    public var isa: String { attributes["isa"]?.string ?? "" }

    public subscript(key: String) -> PlistValue? {
        get { attributes[key] }
        set { attributes[key] = newValue }
    }

    public func string(_ key: String) -> String? { attributes[key]?.string }
    public func references(_ key: String) -> [String] { attributes[key]?.array?.compactMap(\.string) ?? [] }
}

public struct PBXProj: Sendable {
    public enum LoadError: LocalizedError, CustomStringConvertible {
        case syntax(OpenStepParser.Error)
        case structure(String)

        public var errorDescription: String? { description }

        public var description: String {
            switch self {
            case .syntax(let e): "The project file is damaged: syntax error at \(e)"
            case .structure(let m): "The project file is damaged: \(m)"
            }
        }
    }

    public var archiveVersion: String
    public var classes: PlistDictionary
    public var objectVersion: String
    public var objects: [String: PBXObject]
    public var rootObject: String
    public var extraTopLevel: PlistDictionary
    public var style: FormatStyle = .current

    public struct FormatStyle: Equatable, Sendable {
        public var qualifiedConfigurationComments: Bool
        public var descriptiveExceptionSetComments: Bool

        public var singleLineSynchronizedGroups: Bool

        public static let current = FormatStyle(
            qualifiedConfigurationComments: true,
            descriptiveExceptionSetComments: true,
            singleLineSynchronizedGroups: false)

        public static func detect(in text: String) -> FormatStyle {
            FormatStyle(
                qualifiedConfigurationComments: text.contains(" configuration for PBX")
                    || !text.contains("isa = XCBuildConfiguration"),
                descriptiveExceptionSetComments: !text.contains("/* PBXFileSystemSynchronizedBuildFileExceptionSet */"),
                singleLineSynchronizedGroups: text.contains("{isa = PBXFileSystemSynchronizedRootGroup;"))
        }
    }

    public init(parsing text: String) throws(LoadError) {
        let root: PlistValue
        do { root = try OpenStepParser.parse(text) } catch { throw .syntax(error) }
        guard case .dictionary(var top) = root else { throw .structure("top level is not a dictionary") }
        guard case .dictionary(let objs)? = top["objects"] else { throw .structure("missing objects table") }
        guard let rootID = top["rootObject"]?.string else { throw .structure("missing rootObject") }
        archiveVersion = top["archiveVersion"]?.string ?? "1"
        classes = top["classes"]?.dictionary ?? PlistDictionary()
        objectVersion = top["objectVersion"]?.string ?? "46"
        rootObject = rootID
        var table: [String: PBXObject] = [:]
        for (id, value) in objs {
            guard case .dictionary(let attrs) = value else { throw .structure("object \(id) is not a dictionary") }
            table[id] = PBXObject(id: id, attributes: attrs)
        }
        objects = table
        for k in ["archiveVersion", "classes", "objectVersion", "objects", "rootObject"] { top[k] = nil }
        extraTopLevel = top
        style = .detect(in: text)
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url.pathExtension == "xcodeproj" ? url.appendingPathComponent("project.pbxproj") : url)
        try self.init(parsing: String(decoding: data, as: UTF8.self))
    }

    public subscript(id: String) -> PBXObject? {
        get { objects[id] }
        set { objects[id] = newValue }
    }

    public var project: PBXObject? { objects[rootObject] }

    public func objects(isa: String) -> [PBXObject] {
        objects.values.filter { $0.isa == isa }.sorted { $0.id < $1.id }
    }

    public var targets: [PBXObject] {
        (project?.references("targets") ?? []).compactMap { objects[$0] }
    }

    public func buildConfigurations(listID: String?) -> [PBXObject] {
        guard let listID, let list = objects[listID] else { return [] }
        return list.references("buildConfigurations").compactMap { objects[$0] }
    }

    public func makeObjectID<G: RandomNumberGenerator>(using rng: inout G) -> String {
        while true {
            var s = ""
            for _ in 0..<12 { s += String(format: "%02X", UInt8.random(in: 0...255, using: &rng)) }
            if objects[s] == nil { return s }
        }
    }

    public func makeObjectID() -> String {
        if let idSequence {
            while true {
                let s = idSequence.next()
                if objects[s] == nil { return s }
            }
        }
        var g = SystemRandomNumberGenerator()
        return makeObjectID(using: &g)
    }

    public var idSequence: ObjectIDSequence?
}

public final class ObjectIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let prefix: String
    private var counter: UInt64

    public init(prefix: String = "AA", start: UInt64 = 1) {
        self.prefix = String((prefix.uppercased() + String(repeating: "0", count: 8)).prefix(8))
        counter = start
    }

    public func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let n = counter
        counter += 1
        let hex = String(n, radix: 16, uppercase: true)
        return prefix + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}
