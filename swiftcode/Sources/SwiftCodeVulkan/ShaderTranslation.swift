import CVulkan
import Foundation

public enum SwiftCodeMetalABI {
    public static let version = 1
    public static let tableEntries = 192
    public static let tableSize = 192 * 8
    public static let bufferEntry0 = 0
    public static let bufferSlots = 31
    public static let constantDataEntry = 31
    public static let textureEntry0 = 32
    public static let textureSlots = 128
    public static let samplerEntry0 = 160
    public static let samplerSlots = 16
    public static let constexprSamplerEntry0 = 176
    public static let constexprSamplerSlots = 16
    public static let pushVertexTable = 0
    public static let pushFragmentTable = 8
    public static let pushGrid = 16
    public static let pushConstantBytes = 32
    public static let specWorkgroup: [UInt32] = [0, 1, 2]
    public static let specThreadgroupBytes: UInt32 = 3
    public static let specThreadgroupSlot0: UInt32 = 100
}

public enum ShaderStage: String, Codable, Sendable {
    case vertex
    case fragment
    case kernel
}

public struct ShaderReflection: Codable, Sendable, Equatable {
    public var stage: ShaderStage
    public var entryPoint: String?
    public var hash: String?
    public var abi: ABIInfo?
    public var buffers: [Binding]?
    public var textures: [Binding]?
    public var samplers: [Binding]?
    public var constexprSamplers: [ConstexprSampler]?
    public var constantData: ConstantData?
    public var compute: Compute?
    public var vertexInputs: [VertexInput]?
    public var builtins: [String]?
    public var uses: [String]?

    public struct ABIInfo: Codable, Sendable, Equatable {
        public var version: Int?
        public var pushConstantSize: Int?
        public var tablePushOffset: Int?
        public var tableEntries: Int?
    }

    public struct Binding: Codable, Sendable, Equatable {
        public var index: Int
        public var tableEntry: Int?
        public var used: Bool?
        public var access: String?
        public init(index: Int) { self.index = index }
    }

    public struct ConstexprSampler: Codable, Sendable, Equatable {
        public var tableEntry: Int
        public var sAddress: String?, tAddress: String?, rAddress: String?
        public var magFilter: String?, minFilter: String?, mipFilter: String?
        public var normalizedCoordinates: Bool?
        public var compareFunction: String?
        public var maxAnisotropy: Int?
        public var lodMin: Double?, lodMax: Double?
        public var borderColor: String?
        public init(tableEntry: Int) { self.tableEntry = tableEntry }
    }

    public struct ConstantData: Codable, Sendable, Equatable {
        public var tableEntry: Int?
        public var size: Int?
        public var base64: String
        public var bytes: [UInt8] { Data(base64Encoded: base64).map { [UInt8]($0) } ?? [] }
    }

    public struct Compute: Codable, Sendable, Equatable {
        public var workgroupSizeSpecIds: [UInt32]?
        public var gridPushOffset: Int?
        public var gridGuard: Bool?
        public var threadgroupMemory: ThreadgroupMemory?
        public init() {}
    }

    public struct ThreadgroupMemory: Codable, Sendable, Equatable {
        public var staticBytes: Int?
        public var dynamic: Bool?
        public var sizeSpecId: UInt32?
        public var slotsBase: Int?
        public var slots: [ThreadgroupSlot]?
    }

    public struct ThreadgroupSlot: Codable, Sendable, Equatable {
        public var index: Int
        public var offsetSpecId: UInt32?
        public var used: Bool?
    }

    public struct VertexInput: Codable, Sendable, Equatable {
        public var location: Int
        public var name: String?
        public var type: String?
        public var used: Bool?
    }

    public init(stage: ShaderStage, entryPoint: String? = "main") {
        self.stage = stage
        self.entryPoint = entryPoint
    }

    public static func decode(_ json: Data) throws -> ShaderReflection {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(ShaderReflection.self, from: json)
    }
}

public struct TranslatedShader: Sendable {
    public var spirv: [UInt32]
    public var reflection: ShaderReflection
    public init(spirv: [UInt32], reflection: ShaderReflection) {
        self.spirv = spirv
        self.reflection = reflection
    }
}

public struct TranslationRequest: Sendable {
    public var metallib: [UInt8]
    public var linkVertexHash: String?
    public var functionName: String?
    public var affinity: UInt64?
    public init(metallib: [UInt8], linkVertexHash: String? = nil, functionName: String? = nil, affinity: UInt64? = nil) {
        self.metallib = metallib
        self.linkVertexHash = linkVertexHash
        self.functionName = functionName
        self.affinity = affinity
    }
}

public struct ShaderTranslationError: Error, CustomStringConvertible, Sendable {
    public var description: String
    public init(_ d: String) { description = d }
}

public protocol ShaderTranslator: AnyObject, Sendable {
    func translate(_ request: TranslationRequest) throws -> TranslatedShader
}

func fnv1a64(_ bytes: [UInt8], seed: UInt64 = 0xcbf2_9ce4_8422_2325) -> UInt64 {
    var h = seed
    for b in bytes {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01B3
    }
    return h
}

public final class PrebuiltShaderTranslator: ShaderTranslator, @unchecked Sendable {
    private let lock = NSLock()
    private var shaders: [[UInt8]: TranslatedShader] = [:]

    public init() {}

    public func add(_ metallib: [UInt8], _ shader: TranslatedShader) {
        lock.lock(); defer { lock.unlock() }
        shaders[metallib] = shader
    }

    public func translate(_ request: TranslationRequest) throws -> TranslatedShader {
        lock.lock(); defer { lock.unlock() }
        guard let s = shaders[request.metallib] else {
            throw ShaderTranslationError("no prebuilt shader for this function (\(request.metallib.count) bytes)")
        }
        return s
    }
}

public final class AircProcessTranslator: ShaderTranslator, @unchecked Sendable {
    public let executable: URL
    public let arguments: [String]
    public let loopLimit: UInt32
    private let lock = NSLock()
    private var pid: Int32 = 0
    private var toChild: Int32 = -1
    private var fromChild: Int32 = -1
    private var nextID = 1

    public static var defaultArguments: [String] {
        if let dir = ProcessInfo.processInfo.environment["SWIFTCODE_AIRC_CACHE"], !dir.isEmpty { return ["serve", "--cache", dir] }
        return ["serve"]
    }

    public static var defaultLoopLimit: UInt32 {
        if let v = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_LOOP_LIMIT"], let n = UInt32(v) { return n }
        return 1 << 20
    }

    public init(executable: URL, arguments: [String] = AircProcessTranslator.defaultArguments,
                loopLimit: UInt32 = AircProcessTranslator.defaultLoopLimit) {
        self.executable = executable
        self.arguments = arguments
        self.loopLimit = loopLimit
    }

    public static func locate() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["SWIFTCODE_AIRC"], FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        let own = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        let sibling = own.appendingPathComponent("swiftcode-airc")
        if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let p = URL(fileURLWithPath: String(dir)).appendingPathComponent("swiftcode-airc")
            if FileManager.default.isExecutableFile(atPath: p.path) { return p }
        }
        return nil
    }

    deinit {
        stop()
    }

    public func prestart() {
        lock.lock(); defer { lock.unlock() }
        if pid == 0 { try? start() }
    }

    private func start() throws {
        let argv = [executable.path] + arguments
        var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cargs.append(nil)
        defer { for a in cargs { free(a) } }
        var child: Int32 = 0, input: Int32 = -1, output: Int32 = -1
        let r = Self.spawnLock.withLock { yvk_spawn_piped(executable.path, &cargs, &child, &input, &output) }
        guard r == 0 else { throw ShaderTranslationError("swiftcode-airc: cannot start \(executable.path): errno \(r)") }
        pid = child
        toChild = input
        fromChild = output
    }

    private static let spawnLock = NSLock()

    private func stop() {
        if toChild >= 0 { close(toChild) }
        if fromChild >= 0 { close(fromChild) }
        toChild = -1
        fromChild = -1
        if pid > 0 { yvk_end_child(pid) }
        pid = 0
    }

    private func readExactly(_ n: Int) throws -> [UInt8] {
        guard fromChild >= 0 else { throw ShaderTranslationError("swiftcode-airc is not running") }
        var data = [UInt8](repeating: 0, count: n)
        let r = data.withUnsafeMutableBytes { yvk_read_exactly(fromChild, $0.baseAddress, n) }
        if r == -1 { throw ShaderTranslationError("swiftcode-airc closed its output") }
        if r != 0 { throw ShaderTranslationError("swiftcode-airc: read failed: errno \(r)") }
        return data
    }

    public func translate(_ request: TranslationRequest) throws -> TranslatedShader {
        lock.lock(); defer { lock.unlock() }
        if pid == 0 { try start() }
        let id = nextID
        nextID += 1
        var header: [String: Any] = ["id": id, "op": "translate"]
        if let h = request.linkVertexHash { header["link_vertex"] = h }
        if let f = request.functionName { header["function"] = f }
        if loopLimit != 0 { header["loop_limit"] = Int(loopLimit) }
        let headerBytes = [UInt8](try JSONSerialization.data(withJSONObject: header))
        var frame = [UInt8]()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { frame.append(contentsOf: $0) } }
        u32(UInt32(4 + headerBytes.count + request.metallib.count))
        u32(UInt32(headerBytes.count))
        frame.append(contentsOf: headerBytes)
        frame.append(contentsOf: request.metallib)
        let reply: (json: [UInt8], payload: [UInt8])
        do {
            let w = frame.withUnsafeBytes { yvk_write_all(toChild, $0.baseAddress, $0.count) }
            if w != 0 { throw ShaderTranslationError("swiftcode-airc: write failed: errno \(w)") }
            let lengths = try readExactly(8)
            let total = lengths.withUnsafeBytes { Int($0.load(as: UInt32.self).littleEndian) }
            let hl = lengths.withUnsafeBytes { Int($0.load(fromByteOffset: 4, as: UInt32.self).littleEndian) }
            guard total >= 4 + hl else { throw ShaderTranslationError("swiftcode-airc: bad reply frame") }
            let json = try readExactly(hl)
            let payload = try readExactly(total - 4 - hl)
            reply = (json, payload)
        } catch {
            stop()
            throw error as? ShaderTranslationError ?? ShaderTranslationError("swiftcode-airc: \(error)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: Data(reply.json)) as? [String: Any] else {
            throw ShaderTranslationError("swiftcode-airc: reply header is not an object")
        }
        guard obj["status"] as? String == "ok", let refl = obj["reflection"] else {
            let e = obj["error"] as? [String: Any]
            throw ShaderTranslationError("swiftcode-airc: \(e?["code"] ?? "error"): \(e?["detail"] ?? "")")
        }
        let reflection = try ShaderReflection.decode(try JSONSerialization.data(withJSONObject: refl))
        let spirv = reply.payload.withUnsafeBytes { raw in
            (0..<(reply.payload.count / 4)).map { raw.load(fromByteOffset: $0 * 4, as: UInt32.self).littleEndian }
        }
        return TranslatedShader(spirv: spirv, reflection: reflection)
    }
}

public final class AircTranslatorPool: ShaderTranslator, @unchecked Sendable {
    public let processes: [AircProcessTranslator]

    public init(executable: URL, count: Int, arguments: [String] = AircProcessTranslator.defaultArguments,
                dumpDirectory: String? = ProcessInfo.processInfo.environment["SWIFTCODE_AIRC_DUMP_DIR"],
                loopLimit: UInt32 = AircProcessTranslator.defaultLoopLimit) {
        processes = (0..<max(count, 1)).map { i in
            var args = arguments
            if let dir = dumpDirectory, !dir.isEmpty {
                let sub = URL(fileURLWithPath: dir).appendingPathComponent("p\(i)").path
                try? FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
                args += ["--dump-dir", sub]
            }
            return AircProcessTranslator(executable: executable, arguments: args, loopLimit: loopLimit)
        }
    }

    public func prestart() {
        let ps = processes
        Thread.detachNewThread { for p in ps { p.prestart() } }
    }

    public func translate(_ request: TranslationRequest) throws -> TranslatedShader {
        let key = request.affinity ?? fnv1a64(request.metallib)
        return try processes[Int(key % UInt64(processes.count))].translate(request)
    }
}
