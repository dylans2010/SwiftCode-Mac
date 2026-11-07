import Foundation
import YcodeXPC

protocol MetalHostTransport: AnyObject {
    func sendEvent(_ event: XPCDict, to port: UInt32) -> Bool
    func dropRight(_ name: UInt32)
    func makeEventPort() -> UInt32?
    func destroyEventPort(_ name: UInt32)
}

extension MetalHostTransport {
    func makeEventPort() -> UInt32? { nil }
    func destroyEventPort(_ name: UInt32) {}
}

public struct MetalHostStatistics: Sendable {
    public var messages: [UInt64: Int] = [:]
    public var deviceOps: [UInt32: Int] = [:]
    public var submissions = 0
    public var scheduledEvents = 0
    public var completedEvents = 0
    public var unknownRecords: [UInt32: Int] = [:]
    public var refused: [String: Int] = [:]
    public var backendErrors = 0
    public var processes = 0
    public var liveObjects = 0
    public init() {}
}

final class MetalHostCore: @unchecked Sendable {
    static let handshakeVersion: UInt64 = 10
    static let hostFeatureProfile: UInt64 = 10

    let backend: MetalBackend
    let memory: MetalGuestMemoryResolver?
    let surfaces: IOSurfaceResolver?
    let log: (String) -> Void
    let registryID: UInt64
    weak var transport: MetalHostTransport?
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var eventClock: (() -> Double)?
    func eventNow() -> Double { (eventClock ?? clock)() }

    let lock = NSLock()
    var processes: [MetalProcessID: Process] = [:]
    var connections: [UInt32: Connection] = [:]
    var nextProcess: MetalProcessID = 1
    var nextHandle: UInt64 = 1
    var nextGPUAddress: UInt64 = 0x100_0000_0000
    var inFlight = 0
    var exportedEvents: [UInt32: SharedEventGroup] = [:]
    var sharedTextures: [UInt32: Set<MetalHandle>] = [:]
    private var stats = MetalHostStatistics()
    private var loggedUnknown: Set<String> = []

    init(backend: MetalBackend, memory: MetalGuestMemoryResolver?, surfaces: IOSurfaceResolver?,
         registryID: UInt64 = 0x1_0000_0059, log: @escaping (String) -> Void) {
        self.backend = backend
        self.memory = memory
        self.surfaces = surfaces
        self.registryID = registryID
        self.log = log
        backend.setDeviceResetHandler { [weak self] in self?.refreshArgumentMembers() }
    }

    func refreshArgumentMembers() {
        let members = lock.withLock { argumentMembers }
        var changed = 0
        for (target, list) in members {
            for (at, m) in list {
                guard let v = argumentMemberValue(kind: m.kind, object: m.object, offset: m.offset), v != m.written else { continue }
                var w = MetalByteWriter()
                w.u64(v)
                guard backend.writeBuffer(target, offset: at, w.bytes) else { continue }
                changed += 1
                lock.withLock { argumentMembers[target]?[at]?.written = v }
            }
        }
        if changed > 0 { log("metal: after the device reset, \(changed) argument-buffer members written again") }
    }

    struct Connection {
        var clientPort: UInt32
        var type: UInt64?
        var process: MetalProcessID?
    }

    struct RefTable {
        var map: [UInt32: MetalHandle] = [:]
        var next: UInt32 = 1
        var free: [UInt32] = []

        mutating func allocate(_ h: MetalHandle) -> UInt32 {
            let ref: UInt32
            if let i = free.indices.min(by: { free[$0] < free[$1] }) {
                ref = free.remove(at: i)
            } else {
                ref = next
                next += 1
            }
            map[ref] = h
            return ref
        }

        mutating func remove(_ ref: UInt32) -> MetalHandle? {
            guard let h = map.removeValue(forKey: ref) else { return nil }
            free.append(ref)
            return h
        }
    }

    final class Object {
        let kind: MetalRefKind
        let ref: UInt32
        var rights: [UInt32] = []
        var heap: MetalHandle?
        var heapBytes: UInt64 = 0
        var heapSize: UInt64 = 0
        var heapUsed: UInt64 = 0
        var gpuAddress: UInt64 = 0
        var eventValue: UInt64 = 0
        var pendingCreate = false
        var recipe: MetalRecipe?
        var addressQueried = false
        var eventGroup: SharedEventGroup?
        var sharedSurface: UInt32?
        var sharedLabel: String?
        var openedHandle = false
        var argumentLayout: MetalArgumentLayout?
        var argumentTarget: (buffer: MetalHandle, offset: Int)?
        var argumentFallbackLogged = false
        init(kind: MetalRefKind, ref: UInt32) { self.kind = kind; self.ref = ref }
    }

    final class SharedEventGroup {
        let original: MetalHandle
        var port: UInt32 = 0
        var members = 1
        var cpuValue: UInt64 = 0
        init(original: MetalHandle) { self.original = original }
    }

    final class Process: @unchecked Sendable {
        let id: MetalProcessID
        var connections: Set<UInt32> = []
        var eventPort: UInt32 = 0
        var tables: [MetalRefKind: RefTable] = [:]
        var objects: [MetalHandle: Object] = [:]
        var orphans: [MetalHandle: Object] = [:]
        var ended = false
        var ghosts: [MetalHandle: (kind: MetalRefKind, recipe: MetalRecipe)] = [:]
        var dependents: [MetalHandle: Int] = [:]
        var guestPID: Int32 = 0
        var submitted = 0
        var scheduledSent = 0
        var completedSent = 0
        var errorsCompleted = 0
        var lastSubmit: Double = 0
        let events: DispatchQueue
        init(id: MetalProcessID) {
            self.id = id
            events = DispatchQueue(label: "swiftcode.metal.events.\(id)")
        }

        func handle(_ kind: MetalRefKind, _ ref: UInt32) -> MetalHandle? { tables[kind]?.map[ref] }
    }

    var statistics: MetalHostStatistics {
        lock.withLock {
            var s = stats
            s.processes = processes.count
            s.liveObjects = processes.values.reduce(0) { $0 + $1.objects.count }
            return s
        }
    }

    func guestPID(of process: MetalProcessID) -> Int32? {
        lock.withLock { processes[process].map(\.guestPID).flatMap { $0 > 0 ? $0 : nil } }
    }

    func clientPIDs() -> [Int32] {
        lock.withLock { processes.values.map(\.guestPID).filter { $0 > 0 }.sorted() }
    }

    func processSummary() -> [String] {
        lock.withLock {
            let now = clock()
            return processes.values.sorted { $0.id < $1.id }.map { p in
                let idle = p.lastSubmit == 0 ? "never" : String(format: "%.1f s ago", now - p.lastSubmit)
                return "process \(p.id) (guest pid \(p.guestPID)): \(p.objects.count) objects, \(p.submitted) submitted, "
                    + "\(p.scheduledSent) scheduled, \(p.completedSent) completed (\(p.errorsCompleted) with errors), "
                    + "\(p.submitted - p.completedSent) outstanding; last submission \(idle)"
            }
        }
    }

    func connectionOpened(_ id: UInt32, clientPort: UInt32) {
        lock.withLock { connections[id] = Connection(clientPort: clientPort) }
    }

    @discardableResult
    func connectionClosed(_ id: UInt32) -> UInt32? {
        var ended: Process?
        let client: UInt32? = lock.withLock {
            guard let c = connections.removeValue(forKey: id) else { return nil }
            if let pid = c.process, let p = processes[pid] {
                p.connections.remove(id)
                if p.connections.isEmpty {
                    processes[pid] = nil
                    p.ended = true
                    ended = p
                }
            }
            return c.clientPort
        }
        if let p = ended { tearDown(p) }
        return client
    }

    static func isBackendObject(_ kind: MetalRefKind) -> Bool {
        ![.queue, .argumentLayout, .argumentEncoder, .heap].contains(kind)
    }

    private func tearDown(_ p: Process) {
        let objects = lock.withLock { () -> [(key: MetalHandle, value: Object)] in
            var all: [(key: MetalHandle, value: Object)] = []
            for (h, o) in p.objects.sorted(by: { $0.key > $1.key }) {
                if o.pendingCreate { p.orphans[h] = o } else { all.append((h, o)) }
                argumentMembers[h] = nil
            }
            p.objects.removeAll()
            p.ghosts.removeAll()
            p.dependents.removeAll()
            return all
        }
        for (h, o) in objects {
            if let port = leaveEventGroup(o) { transport?.destroyEventPort(port) }
            leaveSharedSurface(h, o)
            if Self.isBackendObject(o.kind) { backend.release(h) }
            for r in o.rights { transport?.dropRight(r) }
        }
        log("metal: process \(p.id) (guest pid \(p.guestPID)) ended; released \(objects.count) objects")
    }

    private func finishCreate(_ h: MetalHandle, _ p: Process) {
        let orphan: Object? = lock.withLock {
            let o = p.objects[h] ?? p.orphans[h]
            o?.pendingCreate = false
            guard p.ended else { return nil }
            p.objects[h] = nil
            return p.orphans.removeValue(forKey: h) ?? o
        }
        guard let o = orphan else { return }
        log("metal: \(h) was created after process \(p.id) ended; released")
        leaveSharedSurface(h, o)
        if Self.isBackendObject(o.kind) { backend.release(h) }
        for r in o.rights { transport?.dropRight(r) }
    }

    struct Outcome {
        var reply: XPCDict?
        var retained: [UInt32] = []
    }

    private func refuse(_ key: String, _ why: String) {
        let first = lock.withLock { () -> Bool in
            stats.refused[key, default: 0] += 1
            return loggedUnknown.insert("refuse " + key).inserted
        }
        if first { log("metal: refused \(key): \(why) (further ones counted, not logged)") }
    }

    private func noteUnknownKeys(_ kind: String, _ keys: [UInt8: UInt64]) {
        guard !keys.isEmpty else { return }
        let fresh: [(UInt8, UInt64)] = lock.withLock {
            keys.sorted { $0.key < $1.key }.filter { loggedUnknown.insert("\(kind) key \($0.key)").inserted }
        }
        for (k, v) in fresh { log("metal: \(kind) descriptor key \(k) is not modelled (first value \(v)); ignored") }
    }

    private func backendFailed(_ what: String, _ error: Error) {
        lock.withLock { stats.backendErrors += 1 }
        log("metal: backend \(what) failed: \(error)")
    }

    func handle(_ d: XPCDict, connection: UInt32, senderPID: Int32 = 0) -> Outcome {
        let mt = d["messageType"]?.integerValue ?? .max
        lock.withLock { stats.messages[mt, default: 0] += 1 }
        if mt == 0 { return handshake(d, connection: connection, senderPID: senderPID) }
        guard let process = lock.withLock({ () -> Process? in
            guard let c = connections[connection], let pid = c.process else { return nil }
            return processes[pid]
        }) else {
            refuse("\(mt)", "message before the hand-shake")
            return Outcome(reply: mt == 6 || mt == 14 ? nil : [:])
        }
        switch mt {
        case 1: return newBuffer(d, process)
        case 6: submit(d, process); return Outcome(reply: nil)
        case 7: return newQueue(d, process)
        case 8: return newStateObject(d, process)
        case 9: return replaceRegion(d, process)
        case 10: return getBytes(d, process)
        case 12: return deviceOp(d, process)
        case 13: return newIOSurfaceTexture(d, process)
        case 14: release(d, process); return Outcome(reply: nil)
        case 15: return newFunction(d, process)
        case 17: return newSharedEventHandle(d, process)
        case 18: return openSharedEventHandle(d, process)
        case 19: return newSharedTexture(d, process)
        case 20: return openSharedTexture(d, process)
        default:
            refuse("\(mt)", "unknown message type; keys: \(Self.describeKeys(d))")
            return Outcome(reply: [:])
        }
    }

    static func describeKeys(_ d: XPCDict) -> String {
        d.keys.sorted().map { key -> String in
            guard let v = d[key] else { return key }
            switch v {
            case let .data(b): return "\(key)=data(\(b.count): \(b.prefix(48).map { String(format: "%02x", $0) }.joined()))"
            case let .uint64(x): return "\(key)=\(x)"
            case let .int64(x): return "\(key)=\(x)"
            case let .bool(x): return "\(key)=\(x)"
            case let .string(x): return "\(key)=\"\(x)\""
            case .sendRight: return "\(key)=send right"
            case .receiveRight: return "\(key)=receive right"
            case let .dictionary(sub): return "\(key)={\(describeKeys(sub))}"
            case let .array(a): return "\(key)=array(\(a.count))"
            default: return "\(key)=\(v)"
            }
        }.joined(separator: ", ")
    }

    private func handshake(_ d: XPCDict, connection: UInt32, senderPID: Int32) -> Outcome {
        let type = d["connectionType"]?.integerValue ?? 0
        let requested = d["processRef"]?.integerValue ?? 0
        let pid: MetalProcessID = lock.withLock {
            var p: Process
            if requested != 0, let existing = processes[requested] {
                p = existing
            } else {
                p = Process(id: nextProcess)
                nextProcess += 1
                processes[p.id] = p
            }
            if var c = connections[connection] {
                c.type = type
                c.process = p.id
                connections[connection] = c
                if type == 0 { p.eventPort = c.clientPort }
            }
            p.connections.insert(connection)
            if p.guestPID == 0 { p.guestPID = senderPID }
            return p.id
        }
        if requested != 0 && requested != pid { log("metal: hand-shake named unknown process \(requested); new process \(pid)") }
        return Outcome(reply: ["version": .uint64(Self.handshakeVersion), "processRef": .uint64(pid),
                               "registryID": .uint64(registryID), "hostFeatureProfile": .uint64(Self.hostFeatureProfile)])
    }

    private func add(_ kind: MetalRefKind, _ p: Process, configure: (Object) -> Void = { _ in }) -> (MetalHandle, UInt32) {
        lock.withLock {
            let h = MetalHandle(nextHandle)
            nextHandle += 1
            var t = p.tables[kind] ?? RefTable()
            let ref = t.allocate(h)
            p.tables[kind] = t
            let o = Object(kind: kind, ref: ref)
            o.pendingCreate = Self.isBackendObject(kind)
            configure(o)
            p.objects[h] = o
            return (h, ref)
        }
    }

    private func lookUp(_ kind: MetalRefKind, _ ref: UInt32, _ p: Process) -> MetalHandle? {
        lock.withLock { p.handle(kind, ref) }
    }

    static func refReply(_ ref: UInt32, words: Int = 2) -> XPCDict {
        var w = MetalByteWriter()
        w.u32(ref)
        for _ in 1..<max(words, 1) { w.u32(0) }
        return ["replyData": .data(w.bytes)]
    }

    private func bytes(of value: XPCObject?) -> [UInt8]? {
        switch value {
        case let .data(b)?: return b
        case let .largeData(length, port)?:
            guard let region = memory?.region(forMemoryEntry: port.name), region.length >= Int(length) else {
                log("metal: cannot map \(length) bytes of data by memory entry \(port)")
                return nil
            }
            return region.bytes(count: Int(length))
        default: return nil
        }
    }

    private func command(_ d: XPCDict) -> MetalRecord? {
        guard let data = bytes(of: d["command"]) else { return nil }
        return try? MetalRecord.parse(data)
    }

    private func newBuffer(_ d: XPCDict, _ p: Process) -> Outcome {
        let length = Int(d["length"]?.integerValue ?? 0)
        let options = d["options"]?.integerValue ?? 0
        var storage = MetalStorageMode(resourceOptions: options)
        var region: GuestSharedRegion?
        var retained: [UInt32] = []
        if case let .sharedMemory(size, port)? = d["sharedMem"] {
            if let r = memory?.region(forMemoryEntry: port.name) {
                region = r.slice(at: 0, count: max(length, min(Int(size), r.length)))
                retained.append(port.name)
            } else {
                log("metal: buffer of \(length) bytes: shared memory \(port) not resolvable; host memory instead")
            }
        }
        if region == nil, storage == .shared || storage == .managed { storage = .private }
        var recipe = MetalRecipe(mt: 1)
        recipe.length = length
        recipe.options = options
        if case let .sharedMemory(size, port)? = d["sharedMem"] { (recipe.right, recipe.rightSize) = (port.name, UInt64(size)) }
        return makeBuffer(p, length: length, storage: storage, region: region, retained: retained, heap: nil, recipe: recipe,
                          reply: { ref in ["bufferRef": .uint64(UInt64(ref))] })
    }

    private func makeBuffer(_ p: Process, length: Int, storage: MetalStorageMode, region: GuestSharedRegion?, retained: [UInt32],
                            heap: MetalHandle?, recipe: MetalRecipe, reply: (UInt32) -> XPCDict) -> Outcome {
        let span = (UInt64(max(length, 1)) + 0xFFFF) & ~0xFFFF
        let (h, ref) = add(.resource, p) { o in
            o.recipe = recipe
            o.rights = retained
            o.heap = heap
            o.heapBytes = heap == nil ? 0 : (UInt64(length) + 255) & ~255
            o.gpuAddress = self.nextGPUAddress
            self.nextGPUAddress += span + 0x1_0000
        }
        if let heap {
            lock.withLock { if let ho = p.objects[heap] { ho.heapUsed += (UInt64(length) + 255) & ~255 } }
        }
        do { try backend.createBuffer(h, length: length, storage: storage, guestMemory: region) } catch {
            backendFailed("createBuffer \(h)", error)
        }
        finishCreate(h, p)
        return Outcome(reply: reply(ref), retained: retained)
    }

    private func newQueue(_ d: XPCDict, _ p: Process) -> Outcome {
        let (_, ref) = add(.queue, p) { $0.recipe = MetalRecipe(mt: 7) }
        return Outcome(reply: ["commandQueueRef": .uint64(UInt64(ref))])
    }

    private func newStateObject(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d) else {
            refuse("8", "no command record")
            return Outcome(reply: [:])
        }
        do {
            switch rec.op {
            case 1:
                var r = ByteReader(rec.body)
                let desc = try MetalDescriptorCodec.texture(&r)
                let (h, ref) = add(.resource, p) { $0.recipe = MetalRecipe(mt: 8, op: 1, body: rec.body) }
                do { try backend.createTexture(h, desc, iosurface: nil) } catch { backendFailed("createTexture \(h)", error) }
                finishCreate(h, p)
                return Outcome(reply: Self.refReply(ref, words: 1))
            case 3:
                let desc = try MetalDescriptorCodec.sampler(rec.body)
                let (h, ref) = add(.sampler, p) { $0.recipe = MetalRecipe(mt: 8, op: 3, body: rec.body) }
                do { try backend.createSampler(h, desc) } catch { backendFailed("createSampler \(h)", error) }
                finishCreate(h, p)
                return Outcome(reply: Self.refReply(ref, words: 1))
            case 4:
                let desc = try MetalDescriptorCodec.depthStencil(rec.body)
                let (h, ref) = add(.depthStencil, p) { $0.recipe = MetalRecipe(mt: 8, op: 4, body: rec.body) }
                do { try backend.createDepthStencilState(h, desc) } catch { backendFailed("createDepthStencilState \(h)", error) }
                finishCreate(h, p)
                return Outcome(reply: Self.refReply(ref, words: 1))
            default:
                refuse("8:\(rec.op)", "unknown object op")
                return Outcome(reply: [:])
            }
        } catch {
            refuse("8:\(rec.op)", "malformed: \(error)")
            return Outcome(reply: [:])
        }
    }

    private func newIOSurfaceTexture(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d), rec.op == 47 else {
            refuse("13", "no op-47 record")
            return Outcome(reply: [:])
        }
        var r = ByteReader(rec.body)
        guard let desc = try? MetalDescriptorCodec.texture(&r) else {
            refuse("13:47", "malformed descriptor")
            return Outcome(reply: [:])
        }
        let plane = Int((try? r.u32()) ?? 0)
        var backing: IOSurfaceBacking?
        var retained: [UInt32] = []
        if let port = d["iosurface"]?.port {
            backing = surfaces?.backing(forSurfacePort: port.name, plane: plane)
            retained.append(port.name)
            if backing == nil { log("metal: IOSurface port \(port) unknown; texture gets host memory") }
        } else {
            log("metal: op 47 without an iosurface right")
        }
        var recipe = MetalRecipe(mt: 13, op: 47, body: rec.body)
        recipe.right = retained.first ?? 0
        recipe.plane = plane
        let (h, ref) = add(.resource, p) { $0.rights = retained; $0.recipe = recipe }
        do { try backend.createTexture(h, desc, iosurface: backing) } catch { backendFailed("createTexture(IOSurface) \(h)", error) }
        finishCreate(h, p)
        return Outcome(reply: Self.refReply(ref), retained: retained)
    }

    private func newSharedTexture(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d), rec.op == 42 else {
            refuse("19", "no op-42 record")
            return Outcome(reply: [:])
        }
        var r = ByteReader(rec.body)
        guard let desc = try? MetalDescriptorCodec.texture(&r, leadingWord: rec.body.count >= 36) else {
            refuse("19:42", "malformed descriptor")
            return Outcome(reply: [:])
        }
        let allocation = Int(Self.heapTextureSizeAndAlign(desc).size) + 16
        guard let surfaces,
              let port = surfaces.makeSharedTextureSurface(allocationSize: allocation, name: "Metal",
                                                           properties: Self.sharedTextureProperties(desc, allocation: allocation,
                                                                                                     registryID: registryID)) else {
            refuse("19:surface", "no IOSurface for a shared texture")
            return Outcome(reply: [:])
        }
        let surfaceID = surfaces.surfaceDescription(forSurfacePort: port)?.id
        var recipe = MetalRecipe(mt: 19, op: 42, body: rec.body)
        recipe.right = port
        let (h, ref) = add(.resource, p) {
            $0.recipe = recipe
            $0.sharedSurface = surfaceID
        }
        if let surfaceID { lock.withLock { sharedTextures[surfaceID, default: []].insert(h) } }
        do { try backend.createTexture(h, desc, iosurface: nil) } catch { backendFailed("createTexture(shared) \(h)", error) }
        finishCreate(h, p)
        var reply = Self.refReply(ref)
        reply["iosurfaceXPCObject"] = .sendRight(XPCPort(name: port, disposition: XPCDisposition.makeSend))
        return Outcome(reply: reply)
    }

    static func sharedTextureProperties(_ d: MetalTextureDescriptor, allocation: Int,
                                        registryID: UInt64) -> [(key: String, value: UInt64)] {
        [
            ("IOSurfaceAllocSize", UInt64(allocation)),
            ("IOSurfacePixelSizeCastingAllowed", 1),
            ("IOSurfaceProtectionOptions", 0),
            ("kAGXCompressionMode", 0),
            ("kMetalRegistryID", registryID),
            ("kMetalTextureType", UInt64(d.textureType)),
            ("kMetalTexturePixelFormat", UInt64(d.pixelFormat)),
            ("kMetalTextureWidth", UInt64(max(d.width, 0))),
            ("kMetalTextureHeight", UInt64(max(d.height, 0))),
            ("kMetalTextureDepth", UInt64(max(d.depth, 0))),
            ("kMetalTextureArrayLength", UInt64(max(d.arrayLength, 0))),
            ("kMetalTextureMipmapLevelCount", UInt64(max(d.mipmapLevelCount, 0))),
            ("kMetalTextureSampleCount", UInt64(max(d.sampleCount, 0))),
            ("kMetalTextureUsage", UInt64(d.usage)),
            ("kMetalTextureResourceOptions", UInt64(d.resourceOptions)),
            ("kMetalTextureGPUOptimization", d.allowGPUOptimizedContents ? 1 : 0),
            ("kMetalTextureSwizzleKey", 0x0504_0302),
            ("kMetalTextureRotation", 0),
            ("kMetalTextureCSCMatrix", 0),
            ("kMetalTextureFootprint", 0),
            ("kMetalTextureSparseValue", 0),
            ("kMetalTextureResourceIndex", 0),
            ("kMetalTextureWriteAccessPattern", 0),
        ]
    }

    static func sharedTextureDescriptor(_ n: [String: UInt64]) -> MetalTextureDescriptor? {
        guard let type = n["kMetalTextureType"], let format = n["kMetalTexturePixelFormat"],
              let width = n["kMetalTextureWidth"], let height = n["kMetalTextureHeight"] else { return nil }
        func v(_ key: String, _ fallback: Int) -> Int { n[key].map { Int(truncatingIfNeeded: $0) } ?? fallback }
        return MetalTextureDescriptor(textureType: UInt8(truncatingIfNeeded: type), pixelFormat: UInt32(truncatingIfNeeded: format),
                                      width: Int(truncatingIfNeeded: width), height: Int(truncatingIfNeeded: height),
                                      depth: v("kMetalTextureDepth", 1), mipmapLevelCount: v("kMetalTextureMipmapLevelCount", 1),
                                      sampleCount: v("kMetalTextureSampleCount", 1), arrayLength: v("kMetalTextureArrayLength", 1),
                                      usage: UInt16(truncatingIfNeeded: n["kMetalTextureUsage"] ?? 0),
                                      resourceOptions: UInt16(truncatingIfNeeded: n["kMetalTextureResourceOptions"] ?? 0),
                                      allowGPUOptimizedContents: (n["kMetalTextureGPUOptimization"] ?? 0) != 0)
    }

    private var labelsLogged = 0

    private func openSharedTexture(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d), rec.op == 43 else {
            refuse("20", "no op-43 record")
            return Outcome(reply: [:])
        }
        guard let port = d["iosurface"]?.port else {
            refuse("20", "no iosurface right")
            return Outcome(reply: [:])
        }
        let label: String? = { if case let .string(s)? = d["label"] { return s }; return nil }()
        guard let surface = surfaces?.surfaceDescription(forSurfacePort: port.name) else {
            refuse("20:surface", "IOSurface port unknown")
            return Outcome(reply: [:])
        }
        guard var desc = Self.sharedTextureDescriptor(surface.numbers) else {
            refuse("20:properties", "surface \(surface.id) has no kMetal texture properties")
            return Outcome(reply: [:])
        }
        if desc.resourceOptions & 0x300 == 0 { desc.resourceOptions |= 0x200 }
        let logIt: Bool = lock.withLock {
            labelsLogged += 1
            return labelsLogged <= 64
        }
        if logIt {
            log("metal: shared texture opened by process \(p.id) (guest pid \(p.guestPID)): surface \(surface.id) " +
                "\(desc.width)x\(desc.height) format \(desc.pixelFormat) type \(desc.textureType)" +
                (label.map { "; label \"\($0)\"" } ?? ""))
        }
        let parent: MetalHandle? = lock.withLock { sharedTextures[surface.id]?.min() }
        var recipe = MetalRecipe(mt: 20, op: 43)
        var w = MetalByteWriter()
        MetalDescriptorCodec.encodeTexture(desc, into: &w)
        recipe.body = w.bytes
        recipe.right = port.name
        let (h, ref) = add(.resource, p) {
            $0.rights = [port.name]
            $0.recipe = recipe
            $0.sharedSurface = surface.id
            $0.sharedLabel = label
            $0.openedHandle = true
        }
        lock.withLock { sharedTextures[surface.id, default: []].insert(h) }
        do {
            if let parent {
                try backend.createTextureView(h, parent: parent, MetalTextureViewDescriptor(pixelFormat: 0))
            } else {
                try backend.createTexture(h, desc, iosurface: surfaces?.backing(forSurfacePort: port.name, plane: 0))
            }
        } catch {
            backendFailed("openSharedTexture \(h)", error)
        }
        finishCreate(h, p)
        var reply = MetalByteWriter()
        reply.u32(ref)
        var words = MetalByteWriter()
        MetalDescriptorCodec.encodeTexture(desc, into: &words)
        reply.append(Array(words.bytes.dropFirst(4)))
        return Outcome(reply: ["replyData": .data(reply.bytes)], retained: [port.name])
    }

    static let sharedContentStats = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_SHARED_CONTENT"] == "1"

    func sharedTextureContent() -> [String] {
        guard Self.sharedContentStats else { return [] }
        let entries: [(UInt32, MetalHandle, MetalTextureDescriptor, String)] = lock.withLock {
            var out: [(UInt32, MetalHandle, MetalTextureDescriptor, String)] = []
            for (id, handles) in sharedTextures.sorted(by: { $0.key < $1.key }) {
                for h in handles.sorted() {
                    for p in processes.values {
                        guard let o = p.objects[h], let r = o.recipe else { continue }
                        var br = ByteReader(r.body)
                        if let d = try? MetalDescriptorCodec.texture(&br, leadingWord: r.body.count >= 36),
                           MetalPixelFormat.bytesPerPixel(d.pixelFormat) == 4, d.pixelFormat != 252 {
                            let what = (o.openedHandle ? "opened (20)" : "made (19)") + " by pid \(p.guestPID)"
                                + (o.sharedLabel.map { " \"\($0.prefix(48))\"" } ?? "")
                            out.append((id, h, d, what))
                        }
                    }
                }
            }
            return out
        }
        let events: [(UInt32, MetalHandle, Int, UInt64)] = lock.withLock {
            exportedEvents.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value.original, $0.value.members, $0.value.cpuValue) }
        }
        var lines: [String] = []
        for (port, h, members, cpu) in events {
            lines.append("metal:   shared event port 0x\(String(port, radix: 16)) (\(h), \(members) refs): value \(backend.eventValue(h).map(String.init) ?? "?") (CPU \(cpu))")
        }
        for (id, h, d, what) in entries {
            let w = max(d.width, 1), hh = max(d.height, 1), row = w * 4, count = row * hh
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 64)
            defer { buffer.deallocate() }
            buffer.initializeMemory(as: UInt8.self, repeating: 0, count: count)
            let region = GuestSharedRegion(pointer: buffer, length: count, objectID: UInt64.max - UInt64(id), owner: nil)
            do {
                try backend.getBytes(texture: h, MetalRegion(width: w, height: hh), level: 0, slice: 0, into: region,
                                     bytesPerRow: row, bytesPerImage: count)
            } catch {
                lines.append("metal:   shared surface \(id) (\(h), \(what)): read failed: \(error)")
                continue
            }
            let px = buffer.assumingMemoryBound(to: UInt8.self)
            var nonBlack = 0, nonZero = 0
            var sums: [Int] = [0, 0, 0, 0]
            var i = 0
            while i < count {
                if px[i] | px[i + 1] | px[i + 2] != 0 { nonBlack += 1 }
                if px[i] | px[i + 1] | px[i + 2] | px[i + 3] != 0 { nonZero += 1 }
                for c in 0..<4 { sums[c] += Int(px[i + c]) }
                i += 4 * 16
            }
            let n = max(count / 64, 1)
            lines.append("metal:   shared surface \(id) (\(h), \(what)) \(w)x\(hh) fmt \(d.pixelFormat): \(nonBlack) of \(n) sampled pixels not black, "
                         + "\(nonZero) not zero; mean bytes \(sums.map { $0 / n })")
        }
        return lines
    }

    private func leaveSharedSurface(_ h: MetalHandle, _ o: Object) {
        guard let id = o.sharedSurface else { return }
        lock.withLock {
            sharedTextures[id]?.remove(h)
            if sharedTextures[id]?.isEmpty == true { sharedTextures[id] = nil }
        }
    }

    static func ioSurfaceFourCC(_ pixelFormat: UInt32) -> UInt32 {
        func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
        switch pixelFormat {
        case 80, 81: return fourCC("BGRA")
        case 70, 71: return fourCC("RGBA")
        case 115: return fourCC("RGhA")
        case 90: return fourCC("l10r")
        case 10: return fourCC("L008")
        default: return 0
        }
    }

    private func newFunction(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let ir = bytes(of: d["functionIR"]) else {
            refuse("15", "no functionIR")
            return Outcome(reply: [:])
        }
        let (h, ref) = add(.function, p) { $0.recipe = MetalRecipe(mt: 15, body: ir) }
        do { try backend.createFunction(h, metallib: ir) } catch { backendFailed("createFunction \(h)", error) }
        finishCreate(h, p)
        return Outcome(reply: Self.refReply(ref))
    }

    static let argumentEncoderWrites = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_ARGUMENT_ENCODER"] != "0"
    private static let argumentLogLimit = 24
    private var argumentWritesLogged = 0
    private var argumentLayoutsLogged = 0
    private var argumentFailuresLogged = 0

    struct ArgumentMember: Equatable {
        var kind: UInt8
        var object: MetalHandle
        var offset: Int64
        var written: UInt64
    }
    var argumentMembers: [MetalHandle: [Int: ArgumentMember]] = [:]

    func argumentMemberValue(kind: UInt8, object h: MetalHandle, offset: Int64) -> UInt64? {
        switch kind {
        case 1:
            let base = backend.gpuAddress(ofBuffer: h)
                ?? lock.withLock { processes.values.lazy.compactMap { $0.objects[h]?.gpuAddress }.first } ?? 0
            return base == 0 ? 0 : base &+ UInt64(bitPattern: offset)
        case 2:
            return backend.gpuResourceID(ofTexture: h)
        case 3:
            return backend.gpuResourceID(ofSampler: h) ?? h.raw
        default:
            return nil
        }
    }

    private func newArgumentLayout(_ body: [UInt8], _ p: Process) -> XPCDict {
        var layout: MetalArgumentLayout?
        var failure: Error?
        do { layout = try MetalArgumentLayout.parse(recordBody: body) } catch { failure = error }
        let (_, ref) = add(.argumentLayout, p) {
            $0.recipe = MetalRecipe(mt: 12, op: 16, body: body)
            $0.argumentLayout = layout
        }
        if let failure {
            refuse("12:16", "argument-buffer layout description did not parse; its encoders place member n at 8 × n")
            let logIt = lock.withLock { () -> Bool in
                argumentFailuresLogged += 1
                return argumentFailuresLogged <= Self.argumentLogLimit
            }
            if logIt { log("metal: argument layout \(ref) of process \(p.id) (\(body.count) bytes) did not parse: \(failure)") }
        } else if let layout {
            let logIt = lock.withLock { () -> Bool in
                guard argumentLayoutsLogged < Self.argumentLogLimit || !layout.isDense || layout.skippedPointees > 0 else { return false }
                argumentLayoutsLogged += 1
                return argumentLayoutsLogged < 4 * Self.argumentLogLimit
            }
            if logIt { log("metal: argument layout \(ref) of process \(p.id): \(Self.describe(layout))") }
        }
        var w = MetalByteWriter()
        w.u32(ref); w.u32(0); w.u32(0xFFFF_0001); w.u32(0xFFFF_FFFF)
        return ["replyData": .data(w.bytes)]
    }

    static func describe(_ layout: MetalArgumentLayout) -> String {
        let sorted = layout.members.sorted { $0.key < $1.key }
        let shown = sorted.prefix(16).map { "\($0.key)@\($0.value.offset)" }.joined(separator: " ")
        return "\(layout.members.count) members (\(shown)\(sorted.count > 16 ? " …" : "")), "
            + "length \(layout.encodedLength), alignment \(layout.alignment)" + (layout.isDense ? "" : ", not 8 × index")
            + (layout.skippedPointees > 0 ? ", \(layout.skippedPointees) unreadable pointee structs skipped" : "")
    }

    private func newArgumentEncoder(_ body: [UInt8], _ p: Process) -> XPCDict {
        var r = ByteReader(body)
        _ = try? r.u32()
        let layoutRef = (try? r.u32()) ?? 0
        let source: (MetalArgumentLayout?, [UInt8]) = lock.withLock {
            guard let h = p.handle(.argumentLayout, layoutRef), let o = p.objects[h] else { return (nil, []) }
            return (o.argumentLayout, o.recipe?.body ?? [])
        }
        let (_, ref) = add(.argumentEncoder, p) {
            $0.recipe = MetalRecipe(mt: 12, op: 17, body: source.1)
            $0.argumentLayout = source.0
        }
        let alignment = source.0?.alignment ?? 8, length = source.0?.encodedLength ?? 24
        if source.0 == nil { log("metal: argument encoder \(ref) of process \(p.id) from layout \(layoutRef) without a description") }
        var w = MetalByteWriter()
        w.u32(ref); w.u32(0)
        w.u16(UInt16(clamping: alignment)); w.u16(UInt16(clamping: length))
        w.u32(0)
        return ["replyData": .data(w.bytes)]
    }

    private func memberOffset(_ encoder: Object, _ index: UInt32) -> Int? {
        guard let layout = encoder.argumentLayout else { return 8 * Int(index) }
        return layout.member(index)?.offset
    }

    private func argumentConstantOffset(_ body: [UInt8], _ p: Process) -> XPCDict {
        var r = ByteReader(body)
        guard let encoderRef = try? r.u32(), (try? r.u32()) != nil, let index = try? r.u32() else {
            refuse("12:35", "malformed constantDataAtIndex: request")
            return Self.u64Reply([0])
        }
        let answer: (base: Int, member: Int?)? = lock.withLock {
            guard let h = p.handle(.argumentEncoder, encoderRef), let o = p.objects[h] else { return nil }
            return (o.argumentTarget?.offset ?? 0, memberOffset(o, index))
        }
        guard let answer else {
            refuse("12:35", "constantDataAtIndex: of an unknown encoder")
            return Self.u64Reply([0])
        }
        guard let member = answer.member else {
            log("metal: constantDataAtIndex: \(index) of encoder \(encoderRef) (process \(p.id)): not in its layout; answered its argument-buffer offset")
            return Self.u64Reply([UInt64(answer.base)])
        }
        return Self.u64Reply([UInt64(answer.base + member)])
    }

    private func argumentEncoderSet(_ body: [UInt8], _ p: Process) {
        var r = ByteReader(body)
        guard body.count >= 28, let encoderRef = try? r.u32(), let kindIndex = try? r.u32(), (try? r.u32()) != nil,
              let countWord = try? r.u32(), (try? r.u64()) != nil else {
            refuse("12:19", "malformed argument-encoder set call")
            return
        }
        let kind = UInt8(truncatingIfNeeded: kindIndex), first = kindIndex >> 8
        let count = Int(min(countWord >> 8, 1 << 16))
        var entries: [(ref: UInt32, offset: Int)] = []
        switch kind {
        case 0, 1:
            for _ in 0..<max(count, 1) {
                guard let ref = try? r.u32(), let offset = try? r.int64() else { break }
                entries.append((ref, offset))
            }
        case 2, 3:
            for _ in 0..<max(count, 1) {
                guard let ref = try? r.u32() else { break }
                entries.append((ref, 0))
            }
        default:
            refuse("12:19", "argument-encoder set call of kind \(kind)")
            return
        }
        guard !entries.isEmpty else {
            refuse("12:19", "malformed argument-encoder set call")
            return
        }
        guard let encoder = lock.withLock({ p.handle(.argumentEncoder, encoderRef).flatMap { p.objects[$0] } }) else {
            refuse("12:19", "argument-encoder set call of an unknown encoder")
            return
        }
        if kind == 0 {
            let (ref, offset) = entries[0]
            if let h = lookUp(.resource, ref, p) { lock.withLock { encoder.argumentTarget = (h, offset) } }
            return
        }
        guard let (target, base) = lock.withLock({ encoder.argumentTarget }) else {
            refuse("12:19", "argument-encoder set call without an argument buffer")
            return
        }
        let fallback: Bool = lock.withLock {
            guard encoder.argumentLayout == nil, !encoder.argumentFallbackLogged else { return false }
            encoder.argumentFallbackLogged = true
            return true
        }
        if fallback {
            log("metal: argument encoder \(encoderRef) of process \(p.id) has no layout description: member n at 8 × n")
        }
        for (k, entry) in entries.enumerated() {
            let index = first &+ UInt32(k)
            guard let memberAt = lock.withLock({ memberOffset(encoder, index) }) else {
                log("metal: argument encoder \(encoderRef) of process \(p.id): index \(index) is not in its layout; not written")
                continue
            }
            var value: UInt64?
            var member: MetalHandle?
            if entry.ref == 0 {
                value = 0
            } else if let h = lookUp(kind == 3 ? .sampler : .resource, entry.ref, p) {
                member = h
                value = argumentMemberValue(kind: kind, object: h, offset: Int64(entry.offset))
            }
            guard let v = value else {
                refuse("12:19", "argument-encoder set call naming an unknown object")
                continue
            }
            var w = MetalByteWriter()
            w.u64(v)
            let at = base + memberAt
            let ok = backend.writeBuffer(target, offset: at, w.bytes)
            let logIt: Bool = lock.withLock {
                if ok {
                    if let member {
                        argumentMembers[target, default: [:]][at] = ArgumentMember(kind: kind, object: member, offset: Int64(entry.offset), written: v)
                    } else {
                        argumentMembers[target]?[at] = nil
                    }
                }
                guard argumentWritesLogged < Self.argumentLogLimit || !ok else { return false }
                argumentWritesLogged += 1
                return true
            }
            if logIt {
                log("metal: argument encoder \(encoderRef) of process \(p.id): kind \(kind) index \(index) object \(entry.ref) -> "
                    + "\(target) +\(at) = 0x\(String(v, radix: 16))" + (ok ? "" : " (not written: no CPU-visible memory)"))
            }
        }
    }

    static func releaseKinds(_ op: UInt32) -> [MetalRefKind]? {
        switch op {
        case 1000, 1001: [.resource]
        case 1002: [.depthStencil]
        case 1003: [.sampler]
        case 1005: [.function]
        case 1006: [.computePipeline]
        case 1007: [.renderPipeline]
        case 1008: [.queue]
        case 1009: [.fence]
        case 1010: [.argumentLayout, .argumentEncoder]
        case 1011: [.argumentEncoder, .argumentLayout]
        case 1012: [.heap]
        case 1013: [.event]
        default: nil
        }
    }

    private func release(_ d: XPCDict, _ p: Process) {
        guard let rec = command(d), let kinds = Self.releaseKinds(rec.op) else {
            refuse("14", "unknown release record")
            return
        }
        var r = ByteReader(rec.body)
        guard let ref = try? r.u32() else { return }
        let found: (MetalHandle, Object)? = lock.withLock {
            for k in kinds {
                guard var t = p.tables[k], let h = t.remove(ref) else { continue }
                p.tables[k] = t
                guard let o = p.objects.removeValue(forKey: h) else { return nil }
                if let heap = o.heap, let ho = p.objects[heap] { ho.heapUsed -= min(ho.heapUsed, o.heapBytes) }
                argumentMembers[h] = nil
                retire(h, o, p)
                return (h, o)
            }
            return nil
        }
        guard let (h, o) = found else {
            log("metal: release op \(rec.op) of unknown ref \(ref) (process \(p.id))")
            return
        }
        if let port = leaveEventGroup(o) { transport?.destroyEventPort(port) }
        leaveSharedSurface(h, o)
        if Self.isBackendObject(o.kind) { backend.release(h) }
        for right in o.rights { transport?.dropRight(right) }
    }

    private func leaveEventGroup(_ o: Object) -> UInt32? {
        lock.withLock {
            guard let g = o.eventGroup else { return nil }
            o.eventGroup = nil
            g.members -= 1
            guard g.members <= 0, g.port != 0 else { return nil }
            exportedEvents[g.port] = nil
            defer { g.port = 0 }
            return g.port
        }
    }

    private func newSharedEventHandle(_ d: XPCDict, _ p: Process) -> Outcome {
        let ref = UInt32(truncatingIfNeeded: d["eventRef"]?.integerValue ?? 0)
        guard let h = lookUp(.event, ref, p) else {
            refuse("17", "unknown event ref")
            return Outcome(reply: ["labelTraceID": .uint64(0)])
        }
        var port: UInt32 = lock.withLock { p.objects[h]?.eventGroup?.port ?? 0 }
        if port == 0 {
            guard let made = transport?.makeEventPort() else {
                refuse("17", "no event port could be made")
                return Outcome(reply: ["labelTraceID": .uint64(0)])
            }
            let (winner, spare): (UInt32, UInt32?) = lock.withLock {
                guard let o = p.objects[h] else { return (0, made) }
                if let g = o.eventGroup, g.port != 0 { return (g.port, made) }
                let g = o.eventGroup ?? SharedEventGroup(original: h)
                if o.eventGroup == nil { g.cpuValue = o.eventValue }
                g.port = made
                o.eventGroup = g
                exportedEvents[made] = g
                return (made, nil)
            }
            if let spare { transport?.destroyEventPort(spare) }
            port = winner
            if port == 0 { return Outcome(reply: ["labelTraceID": .uint64(0)]) }
        }
        noteEventHandle("17: process \(p.id) (guest pid \(p.guestPID)) exports event ref \(ref) as port 0x\(String(port, radix: 16))")
        return Outcome(reply: ["eventPort": .sendRight(XPCPort(name: port, disposition: XPCDisposition.makeSend)),
                               "labelTraceID": .uint64(0)])
    }

    private var eventHandleNotes = 0
    public private(set) var nullEventOpenings = 0
    private func noteEventHandle(_ line: String) {
        let logIt: Bool = lock.withLock {
            eventHandleNotes += 1
            return eventHandleNotes <= 32
        }
        if logIt { log("metal: shared event " + line) }
    }

    private func openSharedEventHandle(_ d: XPCDict, _ p: Process) -> Outcome {
        let portName = d["eventPort"]?.port?.name ?? 0
        if portName == 0 {
            lock.withLock { nullEventOpenings += 1 }
            return Outcome(reply: [:])
        }
        let group: SharedEventGroup? = lock.withLock {
            guard portName != 0, let g = exportedEvents[portName] else { return nil }
            g.members += 1
            return g
        }
        noteEventHandle("18: process \(p.id) (guest pid \(p.guestPID)) opens port 0x\(String(portName, radix: 16))"
                        + (group == nil ? " (no exported event)" : ""))
        let (h, ref) = add(.event, p) { o in
            o.recipe = MetalRecipe(mt: 12, op: 28)
            o.eventGroup = group
        }
        if let g = group {
            do { try backend.createEventAlias(h, of: g.original) } catch { backendFailed("createEventAlias \(h)", error) }
        } else {
            refuse("18", "event port names no exported event; keys: \(Self.describeKeys(d))")
            do { try backend.createEvent(h) } catch { backendFailed("createEvent \(h)", error) }
        }
        finishCreate(h, p)
        return Outcome(reply: Self.refReply(ref))
    }

    private func replaceRegion(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d), rec.op == 2 else {
            refuse("9", "no op-2 record")
            return Outcome(reply: [:])
        }
        var r = ByteReader(rec.body)
        guard let head = try? MetalDescriptorCodec.regionHead(&r) else {
            refuse("9:2", "malformed")
            return Outcome(reply: [:])
        }
        let pixels = r.rest()
        if let h = lookUp(.resource, head.texture, p) {
            do {
                try backend.replaceRegion(texture: h, head.region, level: head.level, slice: head.slice, bytes: pixels,
                                          bytesPerRow: head.bytesPerRow, bytesPerImage: head.bytesPerImage)
            } catch { backendFailed("replaceRegion \(h)", error) }
        } else {
            log("metal: replaceRegion of unknown texture ref \(head.texture)")
        }
        return Outcome(reply: [:])
    }

    private func getBytes(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d), rec.op == 5 else {
            refuse("10", "no op-5 record")
            return Outcome(reply: [:])
        }
        var r = ByteReader(rec.body)
        guard let head = try? MetalDescriptorCodec.regionHead(&r) else {
            refuse("10:5", "malformed")
            return Outcome(reply: [:])
        }
        let size = Int((try? r.u64()) ?? 0)
        guard case let .sharedMemory(_, port)? = d["sharedMem"], let region = memory?.region(forMemoryEntry: port.name) else {
            log("metal: getBytes without resolvable shared memory")
            return Outcome(reply: [:])
        }
        if let h = lookUp(.resource, head.texture, p) {
            do {
                try backend.getBytes(texture: h, head.region, level: head.level, slice: head.slice,
                                     into: region.slice(at: 0, count: size > 0 ? size : region.length),
                                     bytesPerRow: head.bytesPerRow, bytesPerImage: head.bytesPerImage)
            } catch { backendFailed("getBytes \(h)", error) }
        } else {
            log("metal: getBytes of unknown texture ref \(head.texture)")
        }
        return Outcome(reply: [:])
    }

    private func deviceOp(_ d: XPCDict, _ p: Process) -> Outcome {
        guard let rec = command(d) else {
            refuse("12", "no command record")
            return Outcome(reply: [:])
        }
        lock.withLock { stats.deviceOps[rec.op, default: 0] += 1 }
        if let limit = Self.dumpOps[rec.op] { dumpBody(rec, limit: limit) }
        do {
            if let reply = try deviceOp(rec, p) { return Outcome(reply: reply) }
            refuse("12:\(rec.op)", "unknown device op")
        } catch {
            refuse("12:\(rec.op)", "malformed: \(error)")
        }
        return Outcome(reply: [:])
    }

    static let dumpOps: [UInt32: Int] = {
        guard let text = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_DUMP_OPS"] else { return [:] }
        var ops: [UInt32: Int] = [:]
        for item in text.split(separator: ",") {
            let parts = item.split(separator: ":")
            if let op = parts.first.flatMap({ UInt32($0) }) { ops[op] = parts.count > 1 ? Int(parts[1]) ?? 16 : 16 }
        }
        return ops
    }()
    private var dumped: [UInt32: Int] = [:]
    static let limitsOverride: [UInt64]? = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_LIMITS"].flatMap { text in
        let v = text.split(separator: ",").compactMap { UInt64($0) }
        return v.count == 4 ? v : nil
    }

    private func dumpBody(_ rec: MetalRecord, limit: Int) {
        let n = lock.withLock { () -> Int in
            dumped[rec.op, default: 0] += 1
            return dumped[rec.op]!
        }
        guard n <= limit else { return }
        let hex = rec.body.prefix(256).map { String(format: "%02x", $0) }.joined()
        log("metal: dump 12:\(rec.op) #\(n) body \(rec.body.count) bytes: \(hex)")
    }

    private static func u64Reply(_ values: [UInt64]) -> XPCDict {
        var w = MetalByteWriter()
        for v in values { w.u64(v) }
        return ["replyData": .data(w.bytes)]
    }

    static func heapTextureSizeAndAlign(_ t: MetalTextureDescriptor) -> (size: UInt64, align: UInt64) {
        let bppOpt = MetalPixelFormat.bytesPerPixel(t.pixelFormat)
        let tiles: [Int: (Int, Int)] = [1: (128, 128), 2: (128, 64), 4: (64, 64), 8: (64, 32), 16: (32, 32)]
        guard let b = bppOpt, let tile = tiles[b] else {
            return ((legacyHeapTextureSize(t) + 127) & ~127, 128)
        }
        func round(_ v: UInt64, _ m: UInt64) -> UInt64 { (v + m - 1) / m * m }
        func pow2(_ v: Int) -> UInt64 { var p: UInt64 = 1; while p < UInt64(max(v, 1)) { p <<= 1 }; return p }
        func pad(_ v: Int, _ tileDim: Int) -> UInt64 { v < tileDim ? pow2(v) : round(UInt64(v), UInt64(tileDim)) }
        let bytes = UInt64(b)
        if t.textureType == MetalTextureType.typeTextureBuffer {
            return (UInt64(max(t.width, 1)) * bytes, 16)
        }
        let is1D = t.textureType == MetalTextureType.type1D || t.textureType == MetalTextureType.type1DArray
        let metadataUsage = t.usage != 0 && t.usage & MetalTextureUsage.shaderWrite == 0
        var total: UInt64 = 0
        for level in 0..<max(t.mipmapLevelCount, 1) {
            let w = max(t.width >> level, 1), h = is1D ? 1 : max(t.height >> level, 1)
            var size: UInt64
            if is1D {
                size = round(pad(w, tile.0) * bytes, 128)
            } else {
                size = round(pad(w, tile.0) * pad(h, tile.1) * bytes * UInt64(max(t.sampleCount, 1)), 128)
                if metadataUsage && w >= 16 && h >= 16 { size += round(pow2(w) * pow2(h) / 32, 128) }
            }
            if t.textureType == MetalTextureType.type3D { size *= UInt64(max(t.depth >> level, 1)) }
            total += size
        }
        let faces: UInt64 = t.textureType == MetalTextureType.typeCube || t.textureType == MetalTextureType.typeCubeArray ? 6 : 1
        let arrays: UInt64
        switch t.textureType {
        case MetalTextureType.type1DArray, MetalTextureType.type2DArray, MetalTextureType.typeCubeArray,
             MetalTextureType.type2DMultisampleArray: arrays = UInt64(max(t.arrayLength, 1))
        default: arrays = 1
        }
        return (total * faces * arrays, 128)
    }

    static func heapTextureSize(_ t: MetalTextureDescriptor) -> UInt64 { heapTextureSizeAndAlign(t).size }

    static func legacyHeapTextureSize(_ t: MetalTextureDescriptor) -> UInt64 {
        let bpp = UInt64(MetalPixelFormat.bytesPerPixel(t.pixelFormat) ?? 16)
        var total: UInt64 = 0
        for level in 0..<max(t.mipmapLevelCount, 1) {
            let w = UInt64(max(t.width >> level, 1)), h = UInt64(max(t.height >> level, 1)), dd = UInt64(max(t.depth >> level, 1))
            total += (w * h * dd * bpp + 1023) & ~1023
        }
        let faces: UInt64 = t.textureType == MetalTextureType.typeCube || t.textureType == MetalTextureType.typeCubeArray ? 6 : 1
        return total * UInt64(max(t.arrayLength, 1)) * faces * UInt64(max(t.sampleCount, 1))
    }

    static func grantedHeapSize(_ requested: UInt64) -> UInt64 { max((requested + 16383) & ~16383, 16384) }

    private func deviceOp(_ rec: MetalRecord, _ p: Process) throws -> XPCDict? {
        var r = ByteReader(rec.body)
        switch rec.op {
        case 7, 8, 27:
            _ = try r.u32()
            let parentRef = try r.u32()
            var view: MetalTextureViewDescriptor
            if rec.op == 7 {
                view = MetalTextureViewDescriptor(pixelFormat: try r.u32())
            } else {
                let pf = try r.u16(), type = try r.u16()
                let ll = try r.int64(), ln = try r.int64(), sl = try r.int64(), sn = try r.int64()
                view = MetalTextureViewDescriptor(pixelFormat: UInt32(pf), textureType: UInt8(truncatingIfNeeded: type),
                                                  levels: ll..<(ll + ln), slices: sl..<(sl + sn))
                if rec.op == 27 {
                    let s = try r.u32()
                    view.swizzle = [UInt8(s & 0xFF), UInt8((s >> 8) & 0xFF), UInt8((s >> 16) & 0xFF), UInt8(s >> 24)]
                }
            }
            let parentHandle = lookUp(.resource, parentRef, p)
            let (h, ref) = add(.resource, p) { $0.recipe = MetalRecipe(mt: 12, op: rec.op, body: rec.body, deps: parentHandle.map { [$0] } ?? []) }
            noteDependencies(h, p)
            if let parent = parentHandle {
                do { try backend.createTextureView(h, parent: parent, view) } catch { backendFailed("createTextureView \(h)", error) }
            } else {
                log("metal: texture view of unknown parent ref \(parentRef)")
            }
            finishCreate(h, p)
            return Self.refReply(ref)
        case 11:
            let computePayload = try MetalPipelineCodec.payload(rec.body)
            let fref = try MetalPipelineCodec.computeFunctionRef(computePayload)
            noteUnknownKeys("compute pipeline", MetalPipelineCodec.computeUnknownKeys(computePayload))
            let fHandle = lookUp(.function, fref, p)
            let (h, ref) = add(.computePipeline, p) { $0.recipe = MetalRecipe(mt: 12, op: 11, body: rec.body, deps: fHandle.map { [$0] } ?? []) }
            noteDependencies(h, p)
            var info = MetalComputePipelineInfo()
            if let f = fHandle {
                do { info = try backend.createComputePipeline(h, function: f) } catch { backendFailed("createComputePipeline \(h)", error) }
            } else {
                log("metal: compute pipeline with unknown function ref \(fref)")
            }
            finishCreate(h, p)
            var w = MetalByteWriter()
            w.u32(ref); w.u32(0); w.u16(info.maxTotalThreadsPerThreadgroup); w.u16(info.threadExecutionWidth)
            w.pad(to: 24)
            return ["replyData": .data(w.bytes)]
        case 13:
            let (h, ref) = add(.fence, p) { $0.recipe = MetalRecipe(mt: 12, op: 13) }
            do { try backend.createFence(h) } catch { backendFailed("createFence \(h)", error) }
            finishCreate(h, p)
            return Self.refReply(ref)
        case 14:
            let payload = try MetalPipelineCodec.payload(rec.body)
            var refMap: [(UInt32, MetalHandle)] = []
            let desc = try lock.withLock {
                try MetalPipelineCodec.renderPipeline(payload) { ref in
                    let h = p.handle(.function, ref)
                    if let h { refMap.append((ref, h)) }
                    return h
                }
            }
            noteUnknownKeys("render pipeline", desc.unknownKeys)
            var recipe = MetalRecipe(mt: 12, op: 14, body: rec.body, deps: refMap.map(\.1))
            recipe.refMap = refMap
            let (h, ref) = add(.renderPipeline, p) { $0.recipe = recipe }
            noteDependencies(h, p)
            do { try backend.createRenderPipeline(h, desc) } catch { backendFailed("createRenderPipeline \(h)", error) }
            finishCreate(h, p)
            return Self.refReply(ref)
        case 16:
            return newArgumentLayout(rec.body, p)
        case 17:
            return newArgumentEncoder(rec.body, p)
        case 19:
            guard Self.argumentEncoderWrites else {
                refuse("12:19", "argument-encoder set calls are not modelled")
                return [:]
            }
            argumentEncoderSet(rec.body, p)
            return [:]
        case 20:
            _ = try r.u32()
            let size = try r.u64()
            let (_, ref) = add(.heap, p) { $0.heapSize = Self.grantedHeapSize(size); $0.recipe = MetalRecipe(mt: 12, op: 20, body: rec.body) }
            return Self.refReply(ref)
        case 21:
            _ = try r.u32()
            let heapRef = try r.u32()
            var desc = try MetalDescriptorCodec.texture(&r, leadingWord: rec.body.count >= 56)
            desc.resourceOptions = (desc.resourceOptions & ~0xF0) | 0x20
            let heap = lookUp(.heap, heapRef, p)
            let bytes = Self.heapTextureSize(desc)
            let (h, ref) = add(.resource, p) {
                $0.heap = heap
                $0.heapBytes = heap == nil ? 0 : bytes
                $0.recipe = MetalRecipe(mt: 12, op: 21, body: rec.body)
            }
            if let heap { lock.withLock { if let ho = p.objects[heap] { ho.heapUsed += bytes } } }
            do { try backend.createTexture(h, desc, iosurface: nil) } catch { backendFailed("createTexture(heap) \(h)", error) }
            finishCreate(h, p)
            return Self.refReply(ref)
        case 22:
            let desc = try MetalDescriptorCodec.texture(&r, leadingWord: rec.body.count >= 36)
            let answer = Self.heapTextureSizeAndAlign(desc)
            return Self.u64Reply([answer.size, answer.align])
        case 23:
            let length = try r.u64()
            return Self.u64Reply([length, 256])
        case 24:
            _ = try r.u32()
            let heapRef = try r.u32()
            let length = try r.int64()
            let heap = lookUp(.heap, heapRef, p)
            var recipe = MetalRecipe(mt: 12, op: 24, body: rec.body)
            recipe.length = length
            let outcome = makeBuffer(p, length: length, storage: .private, region: nil, retained: [], heap: heap, recipe: recipe,
                                     reply: { Self.refReply($0) })
            return outcome.reply
        case 25:
            return ["replyData": .data([0])]
        case 28:
            let (h, ref) = add(.event, p) { $0.recipe = MetalRecipe(mt: 12, op: 28) }
            do { try backend.createEvent(h) } catch { backendFailed("createEvent \(h)", error) }
            finishCreate(h, p)
            return Self.refReply(ref)
        case 30:
            let ref = try r.u32(), value = try r.u64()
            if let h = lookUp(.event, ref, p) {
                lock.withLock {
                    p.objects[h]?.eventValue = value
                    p.objects[h]?.eventGroup?.cpuValue = value
                }
                backend.signalEvent(h, value: value)
            }
            return [:]
        case 31:
            let ref = try r.u32()
            let (size, used): (UInt64, UInt64) = lock.withLock {
                guard let h = p.handle(.heap, ref), let o = p.objects[h] else { return (0, 0) }
                return (o.heapSize, o.heapUsed)
            }
            return Self.u64Reply([size, size, used])
        case 32:
            let ref = try r.u32()
            let alignment = max(try r.u64(), 1)
            let available: UInt64 = lock.withLock {
                guard let h = p.handle(.heap, ref), let o = p.objects[h] else { return 0 }
                return (o.heapSize - min(o.heapUsed, o.heapSize)) / alignment * alignment
            }
            return Self.u64Reply([available])
        case 33, 34:
            return Self.u64Reply([16])
        case 35:
            return argumentConstantOffset(rec.body, p)
        case 37:
            let l = backend.limits()
            var values = [l.maxThreadsPerThreadgroup.x, l.maxThreadsPerThreadgroup.y, l.maxThreadsPerThreadgroup.z,
                          l.maxThreadgroupMemoryLength]
            values[2] = max(values[2], 512)
            if let o = Self.limitsOverride { values = o }
            return Self.u64Reply(values)
        case 38:
            let ref = try r.u32()
            guard let h = lookUp(.resource, ref, p) else { return Self.u64Reply([0]) }
            lock.withLock { p.objects[h]?.addressQueried = true }
            let address = backend.gpuAddress(ofBuffer: h) ?? lock.withLock { p.objects[h]?.gpuAddress } ?? 0
            return Self.u64Reply([address])
        case 39:
            let ref = try r.u32()
            guard let h = lookUp(.sampler, ref, p) else { return Self.u64Reply([0]) }
            return Self.u64Reply([backend.gpuResourceID(ofSampler: h) ?? h.raw])
        case 41:
            let ref = try r.u32()
            guard let h = lookUp(.event, ref, p) else { return Self.u64Reply([0]) }
            return Self.u64Reply([backend.eventValue(h) ?? lock.withLock {
                p.objects[h].map { $0.eventGroup?.cpuValue ?? $0.eventValue }
            } ?? 0])
        default:
            return nil
        }
    }

    final class InFlight: @unchecked Sendable {
        var sentScheduled = false
        var sentCompleted = false
        let start: Double
        init(start: Double) { self.start = start }
    }

    private func submit(_ d: XPCDict, _ p: Process) {
        let receivedAt = DispatchTime.now().uptimeNanoseconds
        let cbRef = d["commandBufferRef"]?.integerValue ?? 0
        let queueRef = UInt32(truncatingIfNeeded: d["commandQueue"]?.integerValue ?? 0)
        var segments: [[UInt8]] = []
        for (i, s) in (d["segments"]?.arrayValue ?? []).enumerated() {
            guard let b = bytes(of: s) else {
                log("metal: submission \(cbRef): segment \(i) unreadable")
                continue
            }
            segments.append(b)
        }
        var missing = 0
        let (tables, queue) = lock.withLock { (p.tables, p.handle(.queue, queueRef)) }
        var (cb, unknownOps) = MetalCommandDecoder.decode(segments: segments, process: p.id, queue: queue,
                                                          commandBufferRef: cbRef) { kind, ref in
            if let h = tables[kind]?.map[ref] { return h }
            missing += 1
            return nil
        }
        var newUnknown: [UInt32] = []
        lock.withLock {
            stats.submissions += 1
            p.submitted += 1
            p.lastSubmit = clock()
            for (op, n) in unknownOps {
                stats.unknownRecords[op, default: 0] += n
                if loggedUnknown.insert("record \(op)").inserted { newUnknown.append(op) }
            }
        }
        if !newUnknown.isEmpty {
            var bodies: [UInt32: [UInt8]] = [:]
            for pass in cb.passes {
                switch pass {
                case .render(let r):
                    for c in r.commands { if case let .unknown(op, body) = c, bodies[op] == nil { bodies[op] = body } }
                case .compute(let cs):
                    for c in cs { if case let .unknown(op, body) = c, bodies[op] == nil { bodies[op] = body } }
                case .blit(let cs):
                    for c in cs { if case let .unknown(op, body) = c, bodies[op] == nil { bodies[op] = body } }
                default: break
                }
            }
            for op in newUnknown.sorted() {
                let body = bodies[op].map { b in " first body \(b.count) bytes: " + b.prefix(96).map { String(format: "%02x", $0) }.joined() } ?? ""
                log("metal: unknown command record op \(op) from process \(p.id) (guest pid \(p.guestPID)) (kept as .unknown; counted from now on)\(body)")
            }
        }
        if missing > 0 { log("metal: submission \(cbRef) of process \(p.id) names \(missing) unknown refs") }
        for diag in cb.diagnostics { log("metal: submission \(cbRef): \(diag)") }

        cb.receivedAtNs = receivedAt
        let flight = InFlight(start: eventNow())
        lock.withLock { inFlight += 1 }
        backend.submit(cb, scheduled: { [weak self] in
            guard let core = self else { return }
            p.events.async { core.sendScheduled(p, cbRef, flight) }
        }, completed: { [weak self] status in
            guard let core = self else { return }
            p.events.async {
                core.sendCompleted(p, cbRef, flight, status: status)
                core.lock.withLock { core.inFlight -= 1 }
            }
        })
    }

    private func event(_ type: UInt64, _ cbRef: UInt64, status: Int, start: Double, end: Double) -> XPCDict {
        ["messageType": .uint64(type), "commandBufferRef": .uint64(cbRef), "status": .uint64(UInt64(status)),
         "error": .uint64(1), "startTime": .double(start), "endTime": .double(end)]
    }

    private func eventPort(_ p: Process) -> UInt32? {
        lock.withLock { p.ended ? nil : p.eventPort }
    }

    private func sendScheduled(_ p: Process, _ cbRef: UInt64, _ f: InFlight) {
        guard !f.sentScheduled, !f.sentCompleted, let port = eventPort(p) else { return }
        f.sentScheduled = true
        _ = transport?.sendEvent(event(100, cbRef, status: MetalCommandBufferStatus.scheduled, start: f.start, end: eventNow()),
                                 to: port)
        lock.withLock { stats.scheduledEvents += 1; p.scheduledSent += 1 }
    }

    private func sendCompleted(_ p: Process, _ cbRef: UInt64, _ f: InFlight, status: Int) {
        guard !f.sentCompleted, eventPort(p) != nil else { return }
        let end = eventNow()
        if !f.sentScheduled { sendScheduled(p, cbRef, f) }
        guard let port = eventPort(p) else { return }
        f.sentCompleted = true
        _ = transport?.sendEvent(event(101, cbRef, status: status, start: f.start, end: end), to: port)
        lock.withLock {
            stats.completedEvents += 1
            p.completedSent += 1
            if status != MetalCommandBufferStatus.completed { p.errorsCompleted += 1 }
        }
    }

    func drainEvents() {
        let ps = lock.withLock { Array(processes.values) }
        for p in ps { p.events.sync {} }
    }
}
