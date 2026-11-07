import Foundation
import YcodeDarwinABI

protocol HostSocketEndpoint: AnyObject {
    func received(_ bytes: ArraySlice<UInt8>, rights: [DarwinOpenFile]?)
    func disconnected()
}

enum DNSServiceIPC {
    static let version: UInt32 = 1
    static let headerSize = 28

    enum Op {
        static let connection: UInt32 = 1, regRecord: UInt32 = 2, removeRecord: UInt32 = 3, enumeration: UInt32 = 4,
                   regService: UInt32 = 5, browse: UInt32 = 6, resolve: UInt32 = 7, query: UInt32 = 8,
                   reconfirm: UInt32 = 9, addRecord: UInt32 = 10, updateRecord: UInt32 = 11, setDomain: UInt32 = 12,
                   getProperty: UInt32 = 13, portMapping: UInt32 = 14, addrInfo: UInt32 = 15, sendBPF: UInt32 = 16,
                   getPID: UInt32 = 17, release: UInt32 = 18, connectionDelegate: UInt32 = 19, cancel: UInt32 = 63
        static let queryReply: UInt32 = 68, addrInfoReply: UInt32 = 72
    }

    enum Flags {
        static let noReply: UInt32 = 1, trailingTLVs: UInt32 = 2, noErrSD: UInt32 = 4
    }

    static let moreComing: UInt32 = 0x1, add: UInt32 = 0x2, returnIntermediates: UInt32 = 0x1000,
               suppressUnusable: UInt32 = 0x8000

    static func usable(_ address: [UInt8]) -> Bool {
        if address.count == 4 { return address[0] == 127 || NetworkInterfaces.hasRoutableIPv4 }
        return address == [UInt8](repeating: 0, count: 15) + [1] || NetworkInterfaces.hasRoutableIPv6
    }
    static let noError: Int32 = 0, unsupported: Int32 = -65544, badParam: Int32 = -65540,
               noSuchRecord: Int32 = -65554, noSuchName: Int32 = -65538
    static let protocolIPv4: UInt32 = 1, protocolIPv6: UInt32 = 2
    static let daemonVersion: UInt32 = 26_000_000

    struct Header: Equatable {
        var version: UInt32
        var datalen: UInt32
        var ipcFlags: UInt32
        var op: UInt32
        var context: [UInt8]
        var regIndex: UInt32

        init(version: UInt32 = DNSServiceIPC.version, datalen: UInt32, ipcFlags: UInt32 = 0, op: UInt32,
             context: [UInt8], regIndex: UInt32 = 0) {
            self.version = version
            self.datalen = datalen
            self.ipcFlags = ipcFlags
            self.op = op
            self.context = context
            self.regIndex = regIndex
        }

        init(_ b: ArraySlice<UInt8>) {
            let a = Array(b.prefix(28))
            version = a.readBE32(at: 0)
            datalen = a.readBE32(at: 4)
            ipcFlags = a.readBE32(at: 8)
            op = a.readBE32(at: 12)
            context = Array(a[16..<24])
            regIndex = a.readBE32(at: 24)
        }

        var bytes: [UInt8] {
            var b: [UInt8] = []
            b.appendBE32(version)
            b.appendBE32(datalen)
            b.appendBE32(ipcFlags)
            b.appendBE32(op)
            b += context.prefix(8) + [UInt8](repeating: 0, count: max(0, 8 - context.count))
            b.appendBE32(regIndex)
            return b
        }
    }

    struct Reader {
        var data: [UInt8]
        var offset = 0
        var failed = false

        init(_ data: [UInt8]) { self.data = data }

        mutating func u32() -> UInt32 {
            guard offset + 4 <= data.count else { failed = true; return 0 }
            defer { offset += 4 }
            return data.readBE32(at: offset)
        }

        mutating func u16() -> UInt16 {
            guard offset + 2 <= data.count else { failed = true; return 0 }
            defer { offset += 2 }
            return data.readBE16(at: offset)
        }

        mutating func string() -> String {
            guard let end = data[offset...].firstIndex(of: 0) else { failed = true; return "" }
            defer { offset = end + 1 }
            return String(decoding: data[offset..<end], as: UTF8.self)
        }
    }

    static func reply(op: UInt32, context: [UInt8], flags: UInt32, interface: UInt32, error: Int32, body: [UInt8]) -> [UInt8] {
        var b = Header(datalen: UInt32(12 + body.count), op: op, context: context).bytes
        b.appendBE32(flags)
        b.appendBE32(interface)
        b.appendBE32(UInt32(bitPattern: error))
        return b + body
    }

    static func answer(name: String, type: UInt16, rrclass: UInt16 = 1, rdata: [UInt8], ttl: UInt32) -> [UInt8] {
        var b = Array(name.utf8) + [0]
        b.appendBE16(type)
        b.appendBE16(rrclass)
        b.appendBE16(UInt16(rdata.count))
        b += rdata
        b.appendBE32(ttl)
        return b
    }

    static func status(_ e: Int32) -> [UInt8] {
        var b: [UInt8] = []
        b.appendBE32(UInt32(bitPattern: e))
        return b
    }
}

final class DNSServiceConnection: HostSocketEndpoint, @unchecked Sendable {
    private weak var host: UnixSocket?
    private let lock: KernelLock
    private let pid: Int32
    private var buffer: [UInt8] = []
    private var pendingRights: [DarwinOpenFile] = []
    private var shared = false
    private var closed = false
    private var active: [[UInt8]: Int] = [:]
    private var nextRequest = 1
    static let debug = getenv("SWIFTCODE_DEBUG_DNSSD").map { String(cString: $0) == "1" } ?? false
    nonisolated(unsafe) static var requests = 0

    init(host: UnixSocket, lock: KernelLock, pid: Int32) {
        self.host = host
        self.lock = lock
        self.pid = pid
    }

    private func log(_ text: @autoclosure () -> String) {
        guard Self.debug else { return }
        FileHandle.standardError.write(Data("swiftcode-simd: dnssd: pid \(pid): \(text())\n".utf8))
    }

    func disconnected() {
        closed = true
        active = [:]
        pendingRights = []
        log("connection closed")
    }

    func received(_ bytes: ArraySlice<UInt8>, rights: [DarwinOpenFile]?) {
        guard !closed else { return }
        buffer += bytes
        if let rights { pendingRights += rights }
        while buffer.count >= DNSServiceIPC.headerSize {
            let h = DNSServiceIPC.Header(buffer[0..<DNSServiceIPC.headerSize])
            guard h.version == DNSServiceIPC.version, h.datalen <= 70_000 else {
                log("bad header (version \(h.version), datalen \(h.datalen)): closing")
                buffer = []
                closeFromServer()
                return
            }
            let total = DNSServiceIPC.headerSize + Int(h.datalen)
            guard buffer.count >= total else { return }
            let data = Array(buffer[DNSServiceIPC.headerSize..<total])
            buffer.removeFirst(total)
            handle(h, data)
        }
    }

    private func send(_ bytes: [UInt8]) {
        guard !closed, let host, let peer = host.peer, !peer.closed else { return }
        peer.appendStream(bytes[...], rights: nil)
        host.changedWithPeer()
    }

    private func send(_ bytes: [UInt8], toReturnSocket file: DarwinOpenFile) {
        guard case let .object(o) = file.node, let s = o as? UnixSocket, let peer = s.peer else { return }
        peer.appendStream(bytes[...], rights: nil)
        s.changedWithPeer()
    }

    private func closeFromServer() {
        closed = true
        host?.disconnectStream()
    }

    private func handle(_ h: DNSServiceIPC.Header, _ data: [UInt8]) {
        DNSServiceConnection.requests += 1
        var reader = DNSServiceIPC.Reader(data)
        var returnSocket: DarwinOpenFile?
        let subordinate = shared && h.op != DNSServiceIPC.Op.cancel && h.ipcFlags & DNSServiceIPC.Flags.noErrSD == 0
        if subordinate { _ = reader.string() }
        if !pendingRights.isEmpty {
            returnSocket = pendingRights.first
            pendingRights = []
        }
        func status(_ e: Int32) {
            guard h.ipcFlags & DNSServiceIPC.Flags.noErrSD == 0 else { return }
            if let returnSocket { send(DNSServiceIPC.status(e), toReturnSocket: returnSocket) } else { send(DNSServiceIPC.status(e)) }
        }

        switch h.op {
        case DNSServiceIPC.Op.connection, DNSServiceIPC.Op.connectionDelegate:
            shared = true
            log("connection request\(h.op == DNSServiceIPC.Op.connectionDelegate ? " (delegate)" : "")")
            status(DNSServiceIPC.noError)

        case DNSServiceIPC.Op.cancel:
            log("cancel \(h.context)")
            active[h.context] = nil

        case DNSServiceIPC.Op.addrInfo:
            let flags = reader.u32(), interface = reader.u32(), proto = reader.u32()
            let name = reader.string()
            guard !reader.failed, !name.isEmpty else {
                status(DNSServiceIPC.badParam)
                return
            }
            log("getaddrinfo \"\(name)\" flags \(hx(flags)) if \(interface) protocol \(proto)")
            status(DNSServiceIPC.noError)
            let id = begin(h.context)
            let wantV4 = proto == 0 || proto & DNSServiceIPC.protocolIPv4 != 0
            let wantV6 = proto == 0 || proto & DNSServiceIPC.protocolIPv6 != 0
            let suppress = flags & DNSServiceIPC.suppressUnusable != 0
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var v4 = wantV4 ? HostResolver.addresses(name, ipv6: false) : nil
                var v6 = wantV6 ? HostResolver.addresses(name, ipv6: true) : nil
                if suppress {
                    v4 = v4?.filter(DNSServiceIPC.usable)
                    v6 = v6?.filter(DNSServiceIPC.usable)
                }
                var answers: [(error: Int32, body: [UInt8])] = []
                func add(_ type: UInt16, _ list: [[UInt8]]?) {
                    if let list, !list.isEmpty {
                        for a in list {
                            answers.append((0, DNSServiceIPC.answer(name: name, type: type, rdata: a, ttl: HostResolver.addressTTL)))
                        }
                    } else {
                        answers.append((DNSServiceIPC.noSuchRecord, DNSServiceIPC.answer(name: name, type: type, rdata: [], ttl: 0)))
                    }
                }
                if wantV4 { add(HostResolver.typeA, v4) }
                if wantV6 { add(HostResolver.typeAAAA, v6) }
                deliver(id, h.context, op: DNSServiceIPC.Op.addrInfoReply, answers,
                        summary: "\"\(name)\": v4 \(v4?.count ?? -1), v6 \(v6?.count ?? -1)")
            }

        case DNSServiceIPC.Op.query:
            let flags = reader.u32(), interface = reader.u32()
            let name = reader.string()
            let type = reader.u16(), rrclass = reader.u16()
            guard !reader.failed, !name.isEmpty else {
                status(DNSServiceIPC.badParam)
                return
            }
            log("query \"\(name)\" type \(type) class \(rrclass) flags \(hx(flags)) if \(interface)")
            status(DNSServiceIPC.noError)
            let id = begin(h.context)
            let intermediates = flags & DNSServiceIPC.returnIntermediates != 0
            let suppress = flags & DNSServiceIPC.suppressUnusable != 0
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var outcome: HostResolver.Outcome
                if type == HostResolver.typeA || type == HostResolver.typeAAAA {
                    let v6 = type == HostResolver.typeAAAA
                    let list = HostResolver.addresses(name.hasSuffix(".") ? String(name.dropLast()) : name, ipv6: v6)
                    let fqdn = name.hasSuffix(".") ? name : name + "."
                    if let list {
                        let kept = suppress ? list.filter(DNSServiceIPC.usable) : list
                        outcome = kept.isEmpty ? .noRecords : .records(kept.map {
                            HostResolver.Record(name: fqdn, type: type, rrclass: rrclass, ttl: HostResolver.addressTTL, rdata: $0)
                        })
                    } else {
                        outcome = .noSuchName
                    }
                } else {
                    outcome = HostResolver.query(name, type: type, rrclass: rrclass)
                }
                var answers: [(error: Int32, body: [UInt8])] = []
                switch outcome {
                case let .records(records):
                    for r in records where r.type == type || (intermediates && r.type == HostResolver.typeCNAME) {
                        answers.append((0, DNSServiceIPC.answer(name: r.name, type: r.type, rrclass: r.rrclass,
                                                                rdata: r.rdata, ttl: r.ttl)))
                    }
                    if answers.isEmpty {
                        answers.append((DNSServiceIPC.noSuchRecord,
                                        DNSServiceIPC.answer(name: name, type: type, rrclass: rrclass, rdata: [], ttl: 0)))
                    }
                case .noSuchName, .noRecords, .failure:
                    answers.append((DNSServiceIPC.noSuchRecord,
                                    DNSServiceIPC.answer(name: name, type: type, rrclass: rrclass, rdata: [], ttl: 0)))
                }
                deliver(id, h.context, op: DNSServiceIPC.Op.queryReply, answers, summary: "\"\(name)\" type \(type): \(outcome)")
            }

        case DNSServiceIPC.Op.getProperty:
            let property = reader.string()
            log("get property \"\(property)\"")
            var b = DNSServiceIPC.status(property == "DaemonVersion" ? DNSServiceIPC.noError : DNSServiceIPC.badParam)
            if property == "DaemonVersion" {
                b.appendBE32(4)
                b.appendBE32(DNSServiceIPC.daemonVersion)
            }
            send(b)

        case DNSServiceIPC.Op.getPID:
            log("get pid")
            var b = DNSServiceIPC.status(DNSServiceIPC.unsupported)
            b.appendBE32(0)
            send(b)

        case DNSServiceIPC.Op.enumeration, DNSServiceIPC.Op.regService, DNSServiceIPC.Op.browse, DNSServiceIPC.Op.resolve,
             DNSServiceIPC.Op.reconfirm, DNSServiceIPC.Op.setDomain, DNSServiceIPC.Op.portMapping,
             DNSServiceIPC.Op.regRecord, DNSServiceIPC.Op.removeRecord, DNSServiceIPC.Op.addRecord,
             DNSServiceIPC.Op.updateRecord:
            log("op \(h.op) accepted without results")
            status(DNSServiceIPC.noError)

        default:
            log("op \(h.op) unsupported")
            status(DNSServiceIPC.unsupported)
        }
    }

    private func begin(_ context: [UInt8]) -> Int {
        let id = nextRequest
        nextRequest += 1
        active[context] = id
        return id
    }

    private func deliver(_ id: Int, _ context: [UInt8], op: UInt32, _ answers: [(error: Int32, body: [UInt8])], summary: String) {
        let interface = NetworkInterfaces.interface(index: NetworkInterfaces.primaryIndex) != nil ? NetworkInterfaces.primaryIndex : 0
        lock.withLock {
            guard !closed, active[context] == id else { return }
            log("answer \(summary)")
            var out: [UInt8] = []
            for (i, a) in answers.enumerated() {
                let flags = DNSServiceIPC.add | (i + 1 < answers.count ? DNSServiceIPC.moreComing : 0)
                out += DNSServiceIPC.reply(op: op, context: context, flags: flags, interface: interface, error: a.error, body: a.body)
            }
            send(out)
        }
    }
}
