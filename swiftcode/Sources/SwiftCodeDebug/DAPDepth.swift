import Foundation

public struct EvaluateResult: Equatable, Sendable {
    public var result: String
    public var type: String?
    public var variablesReference: Int
    public var memoryReference: String?
}

public struct Instruction: Equatable, Sendable {
    public var address: String
    public var instruction: String
    public var bytes: String?
    public var symbol: String?
    public var file: String?
    public var line: Int?
    init(_ j: JSON) {
        address = j["address"]?.string ?? ""
        instruction = j["instruction"]?.string ?? ""
        bytes = j["instructionBytes"]?.string
        symbol = j["symbol"]?.string
        file = j["location"]?["path"]?.string
        line = j["line"]?.int
    }
}

public struct DataBreakpointInfo: Equatable, Sendable {
    public var dataID: String?
    public var description: String
    public var accessTypes: [String]
}

extension DAPClient {
    public func evaluateFull(_ expression: String, frameID: Int? = nil, context: String = "repl") async throws -> EvaluateResult {
        var args: [String: JSON] = ["expression": .string(expression), "context": .string(context)]
        if let frameID { args["frameId"] = .number(Double(frameID)) }
        let b = try await request("evaluate", .object(args))
        return EvaluateResult(result: b["result"]?.string ?? "", type: b["type"]?.string, variablesReference: b["variablesReference"]?.int ?? 0,
                              memoryReference: b["memoryReference"]?.string)
    }

    @discardableResult
    public func setVariable(reference: Int, name: String, value: String) async throws -> String {
        let b = try await request("setVariable", ["variablesReference": .number(Double(reference)), "name": .string(name), "value": .string(value)])
        return b["value"]?.string ?? value
    }

    public func dataBreakpointInfo(reference: Int, name: String) async throws -> DataBreakpointInfo {
        let b = try await request("dataBreakpointInfo", ["variablesReference": .number(Double(reference)), "name": .string(name)])
        return DataBreakpointInfo(dataID: b["dataId"]?.string, description: b["description"]?.string ?? "",
                                  accessTypes: (b["accessTypes"]?.array ?? []).compactMap(\.string))
    }

    @discardableResult
    public func setDataBreakpoints(_ list: [(dataID: String, accessType: String)]) async throws -> [Breakpoint] {
        let b = try await request("setDataBreakpoints", ["breakpoints": .array(list.map {
            ["dataId": .string($0.dataID), "accessType": .string($0.accessType)]
        })])
        return (b["breakpoints"]?.array ?? []).map(Breakpoint.init)
    }

    public func disassemble(memoryReference: String, instructionOffset: Int, count: Int) async throws -> [Instruction] {
        let b = try await request("disassemble", ["memoryReference": .string(memoryReference), "instructionOffset": .number(Double(instructionOffset)),
                                                  "instructionCount": .number(Double(count)), "resolveSymbols": true])
        return (b["instructions"]?.array ?? []).map(Instruction.init)
    }

    public func stepInstruction(threadID: Int, into: Bool) async throws {
        try await request(into ? "stepIn" : "next", ["threadId": .number(Double(threadID)), "granularity": "instruction"])
    }

    public func step(_ command: String, threadID: Int, granularity: String? = nil, singleThread: Bool = false) async throws {
        var args: [String: JSON] = ["threadId": .number(Double(threadID))]
        if let granularity { args["granularity"] = .string(granularity) }
        if singleThread { args["singleThread"] = true }
        try await request(command, .object(args))
    }

    public func attach(pid: Int?, program: String?, waitFor: Bool, threadFormat: String?) async throws {
        var args: [String: JSON] = ["waitFor": .bool(waitFor)]
        if let pid { args["pid"] = .number(Double(pid)) }
        if let program { args["program"] = .string(program) }
        if let threadFormat { args["threadFormat"] = .string(threadFormat); args["customThreadFormat"] = .string(threadFormat) }
        try await request("attach", .object(args))
    }

    public func attachRemote(port: Int, hostname: String = "127.0.0.1", program: String?, threadFormat: String?,
                             preRunCommands: [String] = []) async throws {
        var args: [String: JSON] = ["gdb-remote-port": .number(Double(port)), "gdb-remote-hostname": .string(hostname)]
        if let program { args["program"] = .string(program) }
        if let threadFormat { args["threadFormat"] = .string(threadFormat); args["customThreadFormat"] = .string(threadFormat) }
        if !preRunCommands.isEmpty { args["preRunCommands"] = .array(preRunCommands.map { .string($0) }) }
        try await request("attach", .object(args))
    }

    public func launch(program: String, cwd: String?, threadFormat: String, arguments: [String] = [], environment: [String: String] = [:]) async throws {
        var args: [String: JSON] = ["program": .string(program), "args": .array(arguments.map { .string($0) }),
                                    "env": .array(environment.keys.sorted().map { .string("\($0)=\(environment[$0]!)") }),
                                    "stopOnEntry": false, "threadFormat": .string(threadFormat),
                                    "customThreadFormat": .string(threadFormat)]
        if let cwd { args["cwd"] = .string(cwd) }
        try await request("launch", .object(args))
    }
}

extension DebugThread {
    public static let format = "Thread ${thread.index}{ name = ${thread.name}}{ queue = ${thread.queue}}"

    public var queue: String? {
        guard let r = name.range(of: " queue = ") else { return nil }
        return String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
