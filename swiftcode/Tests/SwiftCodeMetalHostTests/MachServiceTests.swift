import Foundation
import Testing
import SwiftCodeDarwinKernel
@testable import SwiftCodeMetalHost
import SwiftCodeXPC

@Suite(.serialized) struct MachServiceTests {
    final class Client {
        let host: MachHostTask
        let service: MetalHostService
        init(host: MachHostTask, service: MetalHostService) { self.host = host; self.service = service }

        func open() throws -> (connection: UInt32, events: UInt32) {
            let connection = try host.makePort(sendRight: true)
            let events = try host.makePort(qlimit: 64)
            try host.send(MachHostOutgoingMessage(remotePort: service.servicePort, remoteDisposition: MachMsgType.copySend,
                                                  id: 0x7730_3074,
                                                  descriptors: [.port(name: connection, disposition: MachMsgType.moveReceive),
                                                                .port(name: events, disposition: MachMsgType.makeSend)]))
            return (connection, events)
        }

        func request(_ connection: UInt32, _ d: XPCDict) throws -> XPCDict {
            let reply = try host.makePort()
            defer { try? host.destroyPort(reply) }
            let body = try XPCWire.encodePayload(.dictionary(d), magic: XPCWire.sim2hostMagic)
            try host.send(MachHostOutgoingMessage(remotePort: connection, remoteDisposition: MachMsgType.copySend, localPort: reply,
                                                  localDisposition: MachMsgType.makeSendOnce, id: 0x1000_0000, body: body))
            let m = try host.receive(on: reply, timeout: 5_000_000_000)
            #expect(m.id == 0x2000_0000)
            #expect(Array(m.body.prefix(4)) == [0x21, 0x43, 0x50, 0x58])
            guard case let .dictionary(r) = try XPCWire.decode(body: m.body, descriptors: []) else { throw XPCWireError.rootNotDictionary }
            return r
        }

        func oneWay(_ connection: UInt32, _ d: XPCDict) throws {
            let body = try XPCWire.encodePayload(.dictionary(d), magic: XPCWire.sim2hostMagic)
            try host.send(MachHostOutgoingMessage(remotePort: connection, remoteDisposition: MachMsgType.copySend, id: 0x1000_0000,
                                                  body: body))
        }

        func event(_ port: UInt32) throws -> XPCDict {
            let m = try host.receive(on: port, timeout: 5_000_000_000)
            #expect(m.id == 0x1000_0000 && !MachPortName.isValid(m.replyPort))
            guard case let .dictionary(r) = try XPCWire.decode(body: m.body, descriptors: []) else { throw XPCWireError.rootNotDictionary }
            return r
        }
    }

    @Test func handshakeRequestsEventsAndConnectionEnd() throws {
        let host = DarwinSystem().hostTask
        let backend = NullBackend()
        let service = try MetalHostService(host: host, backend: backend, memory: nil, surfaces: nil, log: { _ in })
        service.start()
        defer { service.stop() }
        let c = Client(host: host, service: service)

        var processRef: UInt64 = 0
        var connections: [(UInt32, UInt32)] = []
        for type in 0..<3 as Range<UInt64> {
            let (conn, events) = try c.open()
            connections.append((conn, events))
            let r = try c.request(conn, ["messageType": .uint64(0), "version": .uint64(1), "connectionType": .uint64(type),
                                         "processRef": .uint64(processRef)])
            #expect(r.keys == ["version", "processRef", "registryID", "hostFeatureProfile"])
            #expect(r["version"]?.uint64Value == 10 && r["hostFeatureProfile"]?.uint64Value == 10)
            if type == 0 { processRef = r["processRef"]?.uint64Value ?? 0 } else { #expect(r["processRef"]?.uint64Value == processRef) }
        }
        #expect(processRef != 0)
        let (c0, events0) = connections[0], c1 = connections[1].0

        let limits = try c.request(c0, Build.message(12, Build.record(37) { $0.u32(0) }))
        #expect(limits["replyData"]?.dataValue.map { Build.u64($0, 3) } == 32768)
        let q = try c.request(c1, ["messageType": .uint64(7), "maxCommandBufferCount": .uint64(64)])
        #expect(q["commandQueueRef"]?.uint64Value == 1)

        let segment = Build.segment(kind: 2, [Build.record(307) { $0.u32(1) }], size: 1024)
        try c.oneWay(c0, ["messageType": .uint64(6), "commandQueue": .uint64(1), "commandBufferRef": .uint64(5),
                          "segments": .array([.data(segment)])])
        let e1 = try c.event(events0), e2 = try c.event(events0)
        #expect(e1["messageType"]?.uint64Value == 100 && e1["commandBufferRef"]?.uint64Value == 5 && e1["status"]?.uint64Value == 3)
        #expect(e2["messageType"]?.uint64Value == 101 && e2["status"]?.uint64Value == 4)

        for (conn, _) in connections { try host.modRefs(conn, right: MachPortRight.send, delta: -1) }
        var waited = 0
        while service.statistics.processes != 0 && waited < 500 {
            usleep(10_000)
            waited += 1
        }
        #expect(service.statistics.processes == 0)
        #expect(backend.calls.contains(.submit(commandBufferRef: 5, passes: 1)))
    }

    @Test func sharedEventHandleTravelsAsARight() throws {
        let host = DarwinSystem().hostTask
        let backend = NullBackend()
        let service = try MetalHostService(host: host, backend: backend, memory: nil, surfaces: nil, log: { _ in })
        service.start()
        defer { service.stop() }
        let c = Client(host: host, service: service)
        var processRef: UInt64 = 0
        var conns: [UInt32] = []
        for type in 0..<3 as Range<UInt64> {
            let (conn, _) = try c.open()
            conns.append(conn)
            let r = try c.request(conn, ["messageType": .uint64(0), "version": .uint64(1), "connectionType": .uint64(type),
                                         "processRef": .uint64(processRef)])
            if type == 0 { processRef = r["processRef"]?.uint64Value ?? 0 }
        }
        let c1 = conns[1]
        _ = try c.request(c1, Build.message(12, Build.record(28) { $0.u32(0) }))

        let reply = try host.makePort()
        defer { try? host.destroyPort(reply) }
        let body = try XPCWire.encodePayload(.dictionary(["messageType": .uint64(17), "eventRef": .uint64(1)]), magic: XPCWire.sim2hostMagic)
        try host.send(MachHostOutgoingMessage(remotePort: c1, remoteDisposition: MachMsgType.copySend, localPort: reply,
                                              localDisposition: MachMsgType.makeSendOnce, id: 0x1000_0000, body: body))
        let m = try host.receive(on: reply, timeout: 5_000_000_000)
        guard m.descriptors.count == 1, case let .port(eventPort, type) = m.descriptors[0] else {
            Issue.record("descriptors \(m.descriptors)")
            return
        }
        #expect(type == MachMsgType.portSend && MachPortName.isValid(eventPort))
        guard case let .dictionary(r) = try XPCWire.decode(body: m.body, descriptors: [.port(name: eventPort, disposition: type)]) else {
            Issue.record("undecodable")
            return
        }
        #expect(r["eventPort"]?.port?.name == eventPort && r["labelTraceID"]?.uint64Value == 0)

        let open = Build.message(18, Build.record(40) { $0.u32(0) },
                                 [("eventPort", .sendRight(XPCPort(name: eventPort, disposition: MachMsgType.copySend)))])
        let enc = try XPCWire.encode(.dictionary(open), magic: XPCWire.sim2hostMagic)
        let reply2 = try host.makePort()
        defer { try? host.destroyPort(reply2) }
        try host.send(MachHostOutgoingMessage(remotePort: c1, remoteDisposition: MachMsgType.copySend, localPort: reply2,
                                              localDisposition: MachMsgType.makeSendOnce, id: 0x1000_0000,
                                              descriptors: enc.descriptors.compactMap {
                                                  if case let .port(name, d) = $0 { return .port(name: name, disposition: d) }
                                                  return nil
                                              }, body: enc.body))
        let m2 = try host.receive(on: reply2, timeout: 5_000_000_000)
        guard case let .dictionary(r2) = try XPCWire.decode(body: m2.body, descriptors: []) else {
            Issue.record("undecodable")
            return
        }
        #expect(r2["replyData"]?.dataValue == [2, 0, 0, 0, 0, 0, 0, 0])
        #expect(backend.calls.contains { if case .createEventAlias = $0 { true } else { false } })
        for conn in conns { try host.modRefs(conn, right: MachPortRight.send, delta: -1) }
    }

    @Test func shutdownStopsTheServiceBeforeTheBackend() throws {
        let host = DarwinSystem().hostTask
        let backend = NullBackend()
        let service = try MetalHostService(host: host, backend: backend, memory: nil, surfaces: nil, log: { _ in })
        final class Seen: @unchecked Sendable { var receivingAtBackendShutdown: Bool? }
        let seen = Seen()
        backend.onShutdown = { [unowned service] in
            seen.receivingAtBackendShutdown = service.receiving
        }
        service.start()
        let c = Client(host: host, service: service)
        let (conn, _) = try c.open()
        let r = try c.request(conn, ["messageType": .uint64(0), "version": .uint64(1), "connectionType": .uint64(0),
                                     "processRef": .uint64(0)])
        #expect(r["processRef"]?.uint64Value != 0)
        var waited = 0
        while !service.receiving && waited < 100 { usleep(1000); waited += 1 }
        #expect(service.receiving)

        let t0 = DispatchTime.now().uptimeNanoseconds
        #expect(service.shutdown(drainTimeout: 5))
        #expect(DispatchTime.now().uptimeNanoseconds - t0 < 2_000_000_000, "the receive thread stops within its 200 ms receive timeout")
        #expect(backend.shutdownCount == 1)
        #expect(seen.receivingAtBackendShutdown == false)
        #expect(!service.receiving)
        #expect(service.shutdown())
        #expect(backend.shutdownCount == 1, "idempotent")
    }
}
