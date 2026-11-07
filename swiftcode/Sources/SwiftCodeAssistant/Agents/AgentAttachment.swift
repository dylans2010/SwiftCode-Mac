import Foundation

public struct AgentAttachment: Sendable {
    public struct MCPEndpoint: Sendable, Equatable {
        public var name: String
        public var url: String
        public var token: String
        public init(name: String = "swiftcode", url: String, token: String) {
            self.name = name
            self.url = url
            self.token = token
        }
    }

    public struct PermissionOption: Sendable, Equatable {
        public var id: String
        public var name: String
        public var kind: String
        public init(id: String, name: String, kind: String) {
            self.id = id
            self.name = name
            self.kind = kind
        }
        public var allows: Bool { kind.hasPrefix("allow") }
    }

    public var mcp: MCPEndpoint?
    public var proposeChange: @Sendable (_ path: String, _ original: String?, _ proposed: String, _ summary: String) async -> Bool
    public var requestPermission: @Sendable (_ title: String, _ options: [PermissionOption]) async -> String?
    public var readFile: @Sendable (_ path: String) async -> String?

    public init(mcp: MCPEndpoint? = nil,
                proposeChange: @escaping @Sendable (String, String?, String, String) async -> Bool = { _, _, _, _ in false },
                requestPermission: @escaping @Sendable (String, [PermissionOption]) async -> String? = { _, _ in nil },
                readFile: @escaping @Sendable (String) async -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }) {
        self.mcp = mcp
        self.proposeChange = proposeChange
        self.requestPermission = requestPermission
        self.readFile = readFile
    }
}

public protocol AgentAttachable: AssistantProvider {
    func attaching(_ attachment: AgentAttachment) -> AssistantProvider
    var isAttached: Bool { get }
}
