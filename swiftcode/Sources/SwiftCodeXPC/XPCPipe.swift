import Foundation

public enum XPCPipe {
    public static let routineBit: UInt32 = 0x4000_0000
    public static let replyID: UInt32 = 0x2000_0000
    public static let oneWayID: UInt32 = 0x1000_0000
    public static let headerSize = 24

    public static func isRequest(id: UInt32) -> Bool {
        id & routineBit != 0 || id & oneWayID != 0
    }
}

public struct XPCPipeMessage: Equatable, Sendable {
    public var id: UInt32
    public var descriptors: [XPCWireDescriptor]
    public var body: [UInt8]

    public init(id: UInt32, descriptors: [XPCWireDescriptor] = [], body: [UInt8]) {
        self.id = id
        self.descriptors = descriptors
        self.body = body
    }

    public var isComplex: Bool { !descriptors.isEmpty }
    public var msghID: Int32 { Int32(bitPattern: id) }

    public var messageSize: Int {
        XPCPipe.headerSize + (isComplex ? 4 + descriptors.reduce(0) { $0 + $1.wireSize } : 0) + body.count
    }

    public static func encode(id: UInt32, _ dictionary: XPCDict) throws -> XPCPipeMessage {
        let e = try XPCWire.encode(.dictionary(dictionary))
        return XPCPipeMessage(id: id, descriptors: e.descriptors, body: e.body)
    }

    public static func request(routine: UInt32, _ dictionary: XPCDict) throws -> XPCPipeMessage {
        try encode(id: XPCPipe.routineBit | routine, dictionary)
    }

    public static func oneWay(_ dictionary: XPCDict) throws -> XPCPipeMessage {
        try encode(id: XPCPipe.oneWayID, dictionary)
    }

    public func decodeDictionary() throws -> XPCDict {
        guard case let .dictionary(d) = try XPCWire.decode(body: body, descriptors: descriptors) else {
            throw XPCWireError.rootNotDictionary
        }
        return d
    }
}

public struct XPCPipeRequest: Equatable, Sendable, CustomStringConvertible {
    public enum Failure: Error, Equatable, Sendable {
        case notPipeRequest(UInt32)
    }

    public var id: UInt32
    public var routine: UInt32
    public var isOneWay: Bool
    public var hasReplyPort: Bool
    public var dictionary: XPCDict

    public init(id: UInt32, body: [UInt8], descriptors: [XPCWireDescriptor], hasReplyPort: Bool) throws {
        if id & XPCPipe.routineBit != 0 {
            routine = id & ~XPCPipe.routineBit
            isOneWay = false
        } else if id & XPCPipe.oneWayID != 0 {
            routine = id & ~XPCPipe.oneWayID
            isOneWay = true
        } else {
            throw Failure.notPipeRequest(id)
        }
        self.id = id
        self.hasReplyPort = hasReplyPort
        dictionary = try XPCPipeMessage(id: id, descriptors: descriptors, body: body).decodeDictionary()
    }

    public init(msghID: Int32, body: [UInt8], descriptors: [XPCWireDescriptor], hasReplyPort: Bool) throws {
        try self.init(id: UInt32(bitPattern: msghID), body: body, descriptors: descriptors, hasReplyPort: hasReplyPort)
    }

    public var knownRoutine: XPCBootstrapRoutine? { isOneWay ? nil : XPCBootstrapRoutine(rawValue: routine) }

    public var ports: [XPCPort] { XPCObject.dictionary(dictionary).ports }

    public var type: UInt64? { dictionary["type"]?.integerValue }
    public var handle: UInt64? { dictionary["handle"]?.integerValue }
    public var name: String? { dictionary["name"]?.stringValue }
    public var flags: UInt64? { dictionary["flags"]?.integerValue }
    public var targetPID: Int64? { dictionary["targetpid"]?.integerValue.map { Int64(bitPattern: $0) } }
    public var instance: UUID? { dictionary["instance"]?.uuidValue }
    public var lookupHandle: UInt64? { dictionary["lookup-handle"]?.integerValue }
    public var port: XPCPort? { dictionary["port"]?.port }

    public var description: String {
        var s = isOneWay ? "pipe one-way" : "pipe \(routine)"
        if let r = knownRoutine { s += " (\(r.label))" }
        s += hasReplyPort ? "" : " no-reply-port"
        return s + " " + dictionary.description
    }
}

public enum XPCPipeReply {
    public static func dictionary(_ d: XPCDict) throws -> XPCPipeMessage {
        try XPCPipeMessage.encode(id: XPCPipe.replyID, d)
    }

    public static func error(_ code: Int64) -> XPCPipeMessage {
        fixed(["error": .int64(code)])
    }

    public static func sendRight(_ name: UInt32, disposition: UInt32 = XPCDisposition.makeSend,
                                 key: String = "port") -> XPCPipeMessage {
        fixed([key: .send(name, disposition: disposition)])
    }

    public static func receiveRight(_ name: UInt32, disposition: UInt32 = XPCDisposition.moveReceive,
                                    key: String = "port") -> XPCPipeMessage {
        fixed([key: .receive(name, disposition: disposition)])
    }

    public static func empty() -> XPCPipeMessage {
        fixed([:])
    }

    static func fixed(_ d: XPCDict) -> XPCPipeMessage {
        if let m = try? dictionary(d) { return m }
        return XPCPipeMessage(id: XPCPipe.replyID, body: try! XPCWire.encodePayload(["error": .int64(22)]))
    }
}

public enum XPCBootstrapRoutine: UInt32, Sendable, CaseIterable {
    case parent = 203
    case register = 204
    case createService = 205
    case checkIn = 206
    case lookUp = 207
    case printService = 708
    case pidDomainSetup = 802
    case pidDomainSetupFollowUp = 803
    case serviceLookUp = 804
    case listenerCheckIn = 805
    case printDomain = 828

    public var label: String {
        switch self {
        case .parent: "parent"
        case .register: "register"
        case .createService: "create-service"
        case .checkIn: "check-in"
        case .lookUp: "look-up"
        case .printService: "print-service"
        case .pidDomainSetup: "pid-domain-setup"
        case .pidDomainSetupFollowUp: "pid-domain-setup-2"
        case .serviceLookUp: "xpc-look-up"
        case .listenerCheckIn: "xpc-listener-check-in"
        case .printDomain: "print-domain"
        }
    }

    public var isLegacy: Bool { rawValue < 300 }
}

public enum XPCBootstrapDomain {
    public static let system: UInt64 = 1
    public static let user: UInt64 = 2
    public static let pid: UInt64 = 5
    public static let listener: UInt64 = 6
    public static let requester: UInt64 = 7
}

public enum XPCBootstrapError {
    public static let notPrivileged: Int64 = 1100
    public static let nameInUse: Int64 = 1101
    public static let unknownService: Int64 = 1102
    public static let serviceActive: Int64 = 1103
    public static let createServiceFailed: Int64 = 126
    public static let eperm: Int64 = 1
    public static let esrch: Int64 = 3
    public static let ealready: Int64 = 37
    public static let unsupported: Int64 = 45
}

public enum XPCBootstrap {
    public static let launchdSimServiceRequestID: Int32 = 708
    public static let launchdSimServiceReplyID: Int32 = 808
}
