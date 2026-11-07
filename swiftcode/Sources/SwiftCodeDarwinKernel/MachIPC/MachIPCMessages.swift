import SwiftCodeDarwinABI

struct MachSendRequest {
    var bits: UInt32
    var size: Int
    var remote: UInt32
    var local: UInt32
    var voucher: UInt32
    var id: Int32
    var descriptorCount: UInt32
    var body: [UInt8]
    var aux: [UInt8]?
}

struct MachReceiveRequest {
    var name: UInt32
    var options: UInt64
    var buffer: UInt64
    var size: UInt64
    var timeout: UInt32
    var auxBuffer: UInt64?
    var auxSize: UInt64 = 0
    var syncDestination: UInt32 = 0
    var mayBlock = true
}

struct MachReceiveResult {
    var code: UInt32
    var size: UInt64 = 0
    var identity: UInt32 = 0
    var auxSize: UInt64 = 0
    var note = ""
}

enum DescriptorSpec {
    case port(name: UInt32, disposition: UInt32)
    case ool(address: UInt64, size: UInt32, deallocate: Bool, copy: UInt8, volatile: Bool)
    case oolPorts(address: UInt64, count: UInt32, deallocate: Bool, copy: UInt8, disposition: UInt32)
    case guarded(context: UInt64, flags: UInt16, disposition: UInt32, name: UInt32)
}

extension MachIPC {

    func send(_ s: MachSendRequest, options: UInt64, timeout: UInt32, msg2: Bool,
              memory: any GuestVirtualMemory) -> (code: UInt32, pseudo: KMessage?, note: String) {
        let complex = s.bits & MachMsgBits.complex != 0
        if s.size < 24 || s.size % 4 != 0 { return (MachMsgReturn.sendMsgTooSmall, nil, "") }
        if s.size > Int(MachIPCLimits.maxSendSize) { return (MachMsgReturn.sendTooLarge, nil, "") }
        if complex {
            if s.size < 28 { return (MachMsgReturn.sendMsgTooSmall, nil, "") }
            if Int(s.descriptorCount) > (s.size - 28) / 12 { return (MachMsgReturn.sendMsgTooSmall, nil, "") }
        } else if s.descriptorCount != 0 {
            return (MachMsgReturn.sendTooLarge, nil, "")
        }
        if msg2 {
            let calls = [MachMsgOption.sendKobjectCall, MachMsgOption.sendMQCall, MachMsgOption.sendDKCall,
                         MachMsgOption.sendAny].filter { options & $0 != 0 }.count
            if calls != 1 { return (MachMsgReturn.sendInvalidOptions, nil, "") }
            if options & MachMsgOption.msgVector != 0,
               options & (MachMsgOption.sendMQCall | MachMsgOption.sendAny) == 0 {
                return (MachMsgReturn.sendInvalidOptions, nil, "")
            }
        }
        var specs: [DescriptorSpec] = []
        var offset = 0
        if complex {
            var rights = 0
            for _ in 0..<Int(s.descriptorCount) {
                guard offset + 12 <= s.body.count else { return (MachMsgReturn.sendMsgTooSmall, nil, "") }
                let type = s.body[offset + 11]
                let size = type == MachMsgDescriptor.port ? 12 : 16
                guard offset + size <= s.body.count else { return (MachMsgReturn.sendMsgTooSmall, nil, "") }
                let d = Array(s.body[offset..<(offset + size)])
                offset += size
                switch type {
                case MachMsgDescriptor.port:
                    let disposition = UInt32(d[10])
                    guard MachMsgType.isPortDisposition(disposition) else { return (MachMsgReturn.sendInvalidType, nil, "") }
                    specs.append(.port(name: d.readLE(UInt32.self, at: 0), disposition: disposition))
                    rights += 1
                case MachMsgDescriptor.ool, MachMsgDescriptor.oolVolatile:
                    let copy = d[9]
                    guard copy <= MachMsgDescriptor.virtualCopy else { return (MachMsgReturn.sendInvalidType, nil, "") }
                    specs.append(.ool(address: d.readLE(UInt64.self, at: 0), size: d.readLE(UInt32.self, at: 12),
                                      deallocate: d[8] != 0, copy: copy, volatile: type == MachMsgDescriptor.oolVolatile))
                case MachMsgDescriptor.oolPorts:
                    let copy = d[9], disposition = UInt32(d[10])
                    guard copy <= MachMsgDescriptor.virtualCopy, MachMsgType.isPortDisposition(disposition) else {
                        return (MachMsgReturn.sendInvalidType, nil, "")
                    }
                    let count = d.readLE(UInt32.self, at: 12)
                    rights += Int(count)
                    specs.append(.oolPorts(address: d.readLE(UInt64.self, at: 0), count: count, deallocate: d[8] != 0,
                                           copy: copy, disposition: disposition))
                case MachMsgDescriptor.guardedPort:
                    let context = d.readLE(UInt64.self, at: 0)
                    let flags = d.readLE(UInt16.self, at: 8)
                    let disposition = UInt32(d[10])
                    guard disposition == MachMsgType.moveReceive, flags != 0,
                          flags & ~MachMsgDescriptor.guardMask == 0,
                          flags & MachMsgDescriptor.guardUnguardedOnSend == 0 || context == 0 else {
                        return (MachMsgReturn.sendInvalidType, nil, "")
                    }
                    specs.append(.guarded(context: context, flags: flags, disposition: disposition,
                                          name: d.readLE(UInt32.self, at: 12)))
                    rights += 1
                default:
                    return (MachMsgReturn.sendInvalidType, nil, "")
                }
                if rights > MachIPCLimits.maxRightsPerMessage { return (MachMsgReturn.sendTooLarge, nil, "") }
            }
        }
        let inline = Array(s.body[min(offset, s.body.count)...])

        var m: KMessage
        switch copyinHeader(s) {
        case let .failure(e): return (e.code, nil, "")
        case let .success(header): m = header
        }
        m.complex = complex
        m.inline = inline
        m.aux = s.aux
        m.sender = senderIdentity
        if SchedPolicy.importanceEnabled || SchedPolicy.qosEnabled { annotateForScheduling(&m, options: options) }
        if options & MachMsgOption.sendNotify != 0, case let .send(p) = m.destination {
            armSendPossible(p, name: s.remote)
        }

        var oolBytes: UInt64 = 0
        for spec in specs {
            switch copyinItem(spec, memory: memory, oolBytes: &oolBytes) {
            case let .success(item): m.items.append(item)
            case let .failure(e):
                destroyMessage(m)
                return (e.code, nil, "")
            }
        }

        if isCircular(m) {
            destroyMessage(m)
            return (MachMsgReturn.success, nil, " [circular: destroyed]")
        }

        return deliver(m, options: options, timeout: timeout, msg2: msg2)
    }

    func copyinHeader(_ s: MachSendRequest) -> Result<KMessage, KernError> {
        let dd = MachMsgBits.remote(s.bits), rd = MachMsgBits.local(s.bits), vd = MachMsgBits.voucher(s.bits)
        let d = s.remote, r = s.local, v = s.voucher
        if rd == 0 {
            if r != 0 { return .failure(KernError(MachMsgReturn.sendInvalidHeader)) }
        } else if !(MachMsgType.moveSend...MachMsgType.makeSendOnce).contains(rd) {
            return .failure(KernError(MachMsgReturn.sendInvalidHeader))
        }
        if vd != 0 {
            if vd != MachMsgType.moveSend && vd != MachMsgType.copySend || v == MachPortName.dead {
                return .failure(KernError(MachMsgReturn.sendInvalidVoucher))
            }
        }
        guard (MachMsgType.moveSend...MachMsgType.makeSendOnce).contains(dd) else {
            return .failure(KernError(MachMsgReturn.sendInvalidHeader))
        }
        guard MachPortName.isValid(d) else { return .failure(KernError(MachMsgReturn.sendInvalidDest)) }
        let voucherName = vd != 0 ? v : 0
        if voucherName != 0, d == voucherName, dd != MachMsgType.moveSend, dd != MachMsgType.copySend {
            return .failure(KernError(MachMsgReturn.sendInvalidDest))
        }
        let replyNamed = rd != 0 && MachPortName.isValid(r)
        if replyNamed, d == r, dd == MachMsgType.moveSendOnce || rd == MachMsgType.moveSendOnce {
            return .failure(KernError(MachMsgReturn.sendInvalidDest))
        }
        if replyNamed, voucherName != 0, r == voucherName {
            return .failure(KernError(MachMsgReturn.sendInvalidReply))
        }
        if replyNamed, d == r, dd == MachMsgType.moveSend, rd == MachMsgType.moveSend,
           let i = slot(of: d), entries[i].bits & T.send != 0, entries[i].urefs < 2 {
            return .failure(KernError(MachMsgReturn.sendInvalidDest))
        }
        if voucherName != 0 { return .failure(KernError(MachMsgReturn.sendInvalidVoucher)) }
        if let i = slot(of: d), entries[i].port === bootstrapPort {
            return .failure(KernError(MachMsgReturn.sendInvalidDest))
        }
        switch copyin(d, dd, slot: .destination, apply: false) {
        case .failure, .success(.dead), .success(.null): return .failure(KernError(MachMsgReturn.sendInvalidDest))
        case .success: break
        }
        let reserved: UInt32 = d == r && dd == MachMsgType.moveSend ? 1 : 0
        if replyNamed {
            if case .failure = copyin(r, rd, slot: .reply, apply: false, reserved: reserved) {
                return .failure(KernError(MachMsgReturn.sendInvalidReply))
            }
        }
        guard case let .success(dest) = copyin(d, dd, slot: .destination, apply: true) else {
            return .failure(KernError(MachMsgReturn.sendInvalidDest))
        }
        var reply: CarriedRight = r == MachPortName.dead ? .dead : .null
        if replyNamed {
            guard case let .success(rr) = copyin(r, rd, slot: .reply, apply: true) else {
                release(dest)
                return .failure(KernError(MachMsgReturn.sendInvalidReply))
            }
            reply = rr
        }
        var m = KMessage(complex: false, destination: dest, destinationType: MachMsgType.received(dd),
                         reply: reply, replyType: MachMsgType.received(rd), id: s.id)
        m.voucherRaw = vd == 0 ? v : 0
        return .success(m)
    }

    func copyinItem(_ spec: DescriptorSpec, memory: any GuestVirtualMemory,
                    oolBytes: inout UInt64) -> Result<KItem, KernError> {
        switch spec {
        case let .port(name, disposition):
            let type = MachMsgType.received(disposition)
            guard MachPortName.isValid(name) else { return .success(.port(name == 0 ? .null : .dead, type: type)) }
            guard case let .success(r) = copyin(name, disposition, slot: .body, apply: true) else {
                return .failure(KernError(MachMsgReturn.sendInvalidRight))
            }
            return .success(.port(r, type: type))

        case let .ool(address, size, deallocate, copy, volatile):
            guard size > 0 else { return .success(.ool(data: [], copy: copy, volatile: volatile)) }
            oolBytes += UInt64(size)
            guard oolBytes <= MachIPCLimits.maxOOLBytes else { return .failure(KernError(MachMsgReturn.vmKernel)) }
            guard let data = try? memory.read(va: address, count: Int(size)) else {
                return .failure(KernError(MachMsgReturn.sendInvalidMemory))
            }
            if deallocate { unmapRange(address, UInt64(size), memory) }
            return .success(.ool(data: data, copy: copy, volatile: volatile))

        case let .oolPorts(address, count, deallocate, copy, disposition):
            let type = MachMsgType.received(disposition)
            guard count > 0 else { return .success(.oolPorts([], type: type, copy: copy)) }
            guard let raw = try? memory.read(va: address, count: Int(count) * 4) else {
                return .failure(KernError(MachMsgReturn.sendInvalidMemory))
            }
            var rights: [CarriedRight] = []
            for k in 0..<Int(count) {
                let name = raw.readLE(UInt32.self, at: 4 * k)
                if !MachPortName.isValid(name) {
                    rights.append(name == 0 ? .null : .dead)
                    continue
                }
                guard case let .success(r) = copyin(name, disposition, slot: .body, apply: true) else {
                    rights.forEach(release)
                    return .failure(KernError(MachMsgReturn.sendInvalidRight))
                }
                rights.append(r)
            }
            if deallocate { unmapRange(address, UInt64(count) * 4, memory) }
            return .success(.oolPorts(rights, type: type, copy: copy))

        case let .guarded(context, flags, disposition, name):
            let type = MachMsgType.received(disposition)
            guard MachPortName.isValid(name) else {
                return .success(.guarded(name == 0 ? .null : .dead, flags: flags, type: type))
            }
            guard let i = lookup(name), entries[i].bits & T.receive != 0, let p = entries[i].port else {
                return .failure(KernError(MachMsgReturn.sendInvalidRight))
            }
            let guardOK = flags & MachMsgDescriptor.guardUnguardedOnSend != 0 ? !p.guarded
                : p.guarded && p.context == context
            guard guardOK, case let .success(r) = copyin(name, disposition, slot: .body, apply: true) else {
                return .failure(KernError(MachMsgReturn.sendInvalidRight))
            }
            return .success(.guarded(r, flags: flags, type: type))
        }
    }

    func unmapRange(_ address: UInt64, _ size: UInt64, _ memory: any GuestVirtualMemory) {
        guard size > 0 else { return }
        let start = address & ~(DarwinKernel.pageSize - 1)
        let end = roundUp(address &+ size, to: DarwinKernel.pageSize)
        guard end > start else { return }
        try? memory.unmap(va: start, size: end - start)
    }

    func isCircular(_ m: KMessage) -> Bool {
        let carried = Set(m.receiveRights.map(ObjectIdentifier.init))
        guard !carried.isEmpty, var current = m.destination.port else { return false }
        var steps = 0
        while steps < 1_000_000 {
            if carried.contains(ObjectIdentifier(current)) { return true }
            guard current.active, !current.inSpace, !current.isKernelObject, let holder = current.transitHolder else {
                return false
            }
            current = holder
            steps += 1
        }
        return true
    }

    func deliver(_ m: KMessage, options: UInt64, timeout: UInt32,
                 msg2: Bool) -> (code: UInt32, pseudo: KMessage?, note: String) {
        guard let p = m.destination.port else {
            destroyMessage(m)
            return (MachMsgReturn.success, nil, "")
        }
        if !p.active {
            destroyMessage(m)
            return (MachMsgReturn.success, nil, " [destination dead: destroyed]")
        }
        if msg2 && options & MachMsgOption.sendAny == 0 {
            let ok: Bool
            if p.isKernelObject {
                if options & MachMsgOption.sendKobjectCall != 0 {
                    ok = options & MachMsgOption.rcvMsg != 0 || m.reply.port == nil
                } else {
                    ok = options & MachMsgOption.sendMQCall != 0
                }
            } else {
                ok = options & MachMsgOption.sendMQCall != 0
            }
            if !ok { return (MachMsgReturn.sendInvalidOptions, m, "") }
        }
        if p.isKernelObject {
            let note = serveKernelObject(m, port: p)
            return (MachMsgReturn.success, nil, note)
        }
        let deadline: UInt64? = options & MachMsgOption.sendTimeout != 0
            ? KernelClock.deadline(afterNanoseconds: UInt64(timeout) * 1_000_000) : nil
        while true {
            if !p.active {
                destroyMessage(m)
                return (MachMsgReturn.success, nil, " [destination died: destroyed]")
            }
            if p.messages.count >= MachIPCLimits.qlimitKernel { return (MachMsgReturn.sendNoBuffer, m, "") }
            if canEnqueue(m, on: p) {
                enqueue(m, on: p)
                return (MachMsgReturn.success, nil, "")
            }
            if let deadline, KernelClock.now() >= deadline { return (MachMsgReturn.sendTimedOut, m, "") }
            let caller = lock.callerContext
            let waiter = caller.map(ObjectIdentifier.init)
            if let waiter { p.snapshotPendingSends.append((waiter, m)) }
            var pushed: (DarwinKernel, Int)?
            if SchedPolicy.qosEnabled, SchedPolicy.sendPushEnabled, let ctx = caller,
               let target = p.receiver?.kernel {
                let cls = ctx.schedClass
                target.addSendPush(cls)
                pushed = (target, cls)
                SchedStats.sendPushes.wrappingAdd(1, ordering: .relaxed)
            }
            let result = p.sendWaiters.wait(on: lock, deadline: deadline)
            if let (target, cls) = pushed { target.removeSendPush(cls) }
            if let waiter { p.snapshotPendingSends.removeAll { $0.context == waiter } }
            if result == .woken, p.grantedSlots > 0 {
                p.grantedSlots -= 1
                if p.active {
                    enqueue(m, on: p)
                    return (MachMsgReturn.success, nil, "")
                }
                continue
            }
            if result == .interrupted {
                return (MachMsgReturn.sendInterrupted, m, "")
            }
        }
    }

    func canEnqueue(_ m: KMessage, on p: IPCPort) -> Bool {
        if case .sendOnce = m.destination { return true }
        if p.occupiedSlots < p.qlimit { return true }
        let idle = p.waitingReceivers + p.sets.reduce(0) { $0 + $1.waitingReceivers }
        return idle > p.messages.count
    }

    func receive(_ r: MachReceiveRequest, context: ThreadContext?, memory: any GuestVirtualMemory) -> MachReceiveResult {
        guard let i = lookup(r.name) else { return MachReceiveResult(code: MachMsgReturn.rcvInvalidName) }
        let set = entries[i].set
        let port: IPCPort? = set == nil && entries[i].bits & T.receive != 0 ? entries[i].port : nil
        guard set != nil || port != nil else { return MachReceiveResult(code: MachMsgReturn.rcvInvalidName) }
        if r.options & MachMsgOption.rcvSyncWait != 0 {
            guard let port, let context, specialReplyPorts[context.threadID] === port,
                  MachPortName.isValid(r.syncDestination) else {
                return MachReceiveResult(code: MachMsgReturn.rcvInvalidNotify)
            }
        }
        let trailer = MachMsgOption.trailerSize(r.options)
        if let context, context.carriedImportance != nil || context.ipcPushClass >= 0 { kernel?.endServicing(context) }
        let deadline: UInt64? = r.options & MachMsgOption.rcvTimeout != 0
            ? KernelClock.deadline(afterNanoseconds: UInt64(r.timeout) * 1_000_000) : nil
        switch awaitMessage(name: r.name, slot: i, port: port, set: set, deadline: deadline, mayBlock: r.mayBlock) {
        case let .failure(e): return MachReceiveResult(code: e.code)
        case let .success(source): return take(from: source, request: r, trailer: trailer, memory: memory, context: context)
        }
    }

    func awaitMessage(name: UInt32, slot i: Int, port: IPCPort?, set: IPCPortSet?, deadline: UInt64?,
                      mayBlock: Bool) -> Result<IPCPort, KernError> {
        let stamp = port?.changeStamp ?? set!.changeStamp

        func stillValid() -> Bool {
            guard slot(of: name) == i else { return false }
            if let port {
                return entries[i].port === port && entries[i].bits & T.receive != 0 && port.active
                    && port.changeStamp == stamp
            }
            return entries[i].set === set && set!.active && set!.changeStamp == stamp
        }

        while true {
            if let source = port.flatMap({ $0.messages.isEmpty ? nil : $0 }) ?? set.flatMap(readyMember) {
                return .success(source)
            }
            if !mayBlock { return .failure(KernError(MachMsgReturn.rcvTimedOut)) }
            if let deadline, KernelClock.now() >= deadline { return .failure(KernError(MachMsgReturn.rcvTimedOut)) }
            let result: WaitResult
            if let port {
                port.waitingReceivers += 1
                result = port.receiveWaiters.wait(on: lock, deadline: deadline)
                port.waitingReceivers -= 1
            } else {
                set!.waitingReceivers += 1
                result = set!.waiters.wait(on: lock, deadline: deadline)
                set!.waitingReceivers -= 1
            }
            guard stillValid() else { return .failure(KernError(MachMsgReturn.rcvPortChanged)) }
            if result == .interrupted { return .failure(KernError(MachMsgReturn.rcvInterrupted)) }
        }
    }

    func readyMember(_ s: IPCPortSet) -> IPCPort? {
        s.members.filter { !$0.messages.isEmpty }.min { $0.readyStamp < $1.readyStamp }
    }

    func take(from source: IPCPort, request r: MachReceiveRequest, trailer: Int,
              memory: any GuestVirtualMemory, context: ThreadContext? = nil) -> MachReceiveResult {
        let first = source.messages.first!
        let size = first.size
        let sourceName = reverse[ObjectIdentifier(source)] ?? 0
        var auxNeeded = 0
        if r.auxBuffer != nil { auxNeeded = max(8, first.aux?.count ?? 8) }
        let tooLarge = r.size < UInt64(size + trailer) || (r.auxBuffer != nil && r.auxSize < UInt64(auxNeeded))
        if tooLarge {
            if r.options & MachMsgOption.rcvLarge != 0 {
                if r.size >= 8 { try? memory.write(va: r.buffer + 4, bytes: le32(UInt32(size))) }
                var identity: UInt32 = 0
                if r.options & MachMsgOption.rcvLargeIdentity != 0 {
                    identity = sourceName
                    if r.size >= 16 { try? memory.write(va: r.buffer + 12, bytes: le32(sourceName)) }
                }
                return MachReceiveResult(code: MachMsgReturn.rcvTooLarge, size: UInt64(size + trailer),
                                         identity: identity, note: " [too large: \(size)+\(trailer), stays queued]")
            }
            let (m, seqno) = dequeue(source)
            let header = bareHeader(m, local: sourceName)
            let bytes = header + makeTrailer(m, seqno: seqno, port: source, size: trailer)
            guard r.size >= 24 else { return MachReceiveResult(code: MachMsgReturn.rcvInvalidData) }
            do { try memory.write(va: r.buffer, bytes: Array(bytes.prefix(Int(min(r.size, UInt64(bytes.count)))))) } catch {
                return MachReceiveResult(code: MachMsgReturn.rcvInvalidData)
            }
            return MachReceiveResult(code: MachMsgReturn.rcvTooLarge, size: UInt64(size + trailer),
                                     note: " [too large: \(size)+\(trailer), destroyed]")
        }
        let (m, seqno) = dequeue(source)
        if m.importance || m.pushClass >= 0 { receivedForScheduling(m, by: context) }
        let out = copyoutReceived(m, from: source, options: r.options, buffer: r.buffer, memory: memory)
        if out.headerFailed {
            let header = bareHeader(m, local: sourceName, rightsAlreadyHandled: true)
            let bytes = header + makeTrailer(m, seqno: seqno, port: source, size: trailer)
            try? memory.write(va: r.buffer, bytes: Array(bytes.prefix(Int(min(r.size, UInt64(bytes.count))))))
            return MachReceiveResult(code: MachMsgReturn.rcvHeaderError | MachMsgReturn.ipcSpace)
        }
        var bytes = out.bytes
        appendTrailer(m, seqno: seqno, port: source, size: trailer, to: &bytes)
        guard writeReceived(memory, r.buffer, bytes) else {
            return MachReceiveResult(code: MachMsgReturn.rcvInvalidData)
        }
        var auxSize: UInt64 = 0
        if let auxBuffer = r.auxBuffer {
            let aux = m.aux ?? [0, 0, 0, 0, 0, 0, 0, 0]
            auxSize = m.aux == nil ? 0 : UInt64(aux.count)
            try? memory.write(va: auxBuffer, bytes: aux)
        }
        let code = out.resource == 0 ? MachMsgReturn.success : MachMsgReturn.rcvBodyError | out.resource
        return MachReceiveResult(code: code, size: UInt64(out.bytes.count + trailer), auxSize: auxSize,
                                 note: tracesCalls ? " [id \(m.id) size \(out.bytes.count) seqno \(seqno) from \(hx(sourceName))]" : "")
    }

    func bareHeader(_ m: KMessage, local: UInt32, rightsAlreadyHandled: Bool = false) -> [UInt8] {
        var remote: UInt32 = 0
        if case .dead = m.reply { remote = MachPortName.dead }
        if !rightsAlreadyHandled {
            var rest = m
            rest.destination = .null
            destroyMessage(rest)
            consumeDestination(m.destination)
        }
        var h: [UInt8] = []
        h += le32(MachMsgBits.make(remote: 0, local: m.destinationType))
        h += le32(24)
        h += le32(remote)
        h += le32(local)
        h += le32(0)
        h += le32(UInt32(bitPattern: m.id))
        return h
    }

    func makeTrailer(_ m: KMessage, seqno: UInt32, port: IPCPort, size: Int) -> [UInt8] {
        var t: [UInt8] = []
        appendTrailer(m, seqno: seqno, port: port, size: size, to: &t)
        return t
    }

    func appendTrailer(_ m: KMessage, seqno: UInt32, port: IPCPort, size: Int, to t: inout [UInt8]) {
        let base = t.count
        t.reserveCapacity(base + 68)
        t.appendLE(UInt32(0))
        t.appendLE(UInt32(size))
        t.appendLE(seqno)
        if m.fromKernel {
            t.appendLE(UInt32(0))
            t.appendLE(UInt32(1))
            t.append(contentsOf: repeatElement(0, count: 32))
        } else {
            let sender = m.sender ?? senderIdentity
            t.appendLE(sender.uid)
            t.appendLE(sender.gid)
            for v in sender.auditToken { t.appendLE(v) }
        }
        t.appendLE(port.context)
        t.appendLE(UInt64(0))
        t.removeLast(t.count - base - min(size, t.count - base))
    }

    func copyoutReceived(_ m: KMessage, from p: IPCPort, options: UInt64, buffer: UInt64,
                         memory: any GuestVirtualMemory) -> (bytes: [UInt8], resource: UInt32, headerFailed: Bool) {
        let (replyName, replyOK) = copyout(m.reply)
        let local: UInt32 = !p.active ? MachPortName.dead : (p.receiver === self ? reverse[ObjectIdentifier(p)] ?? 0 : 0)
        consumeDestination(m.destination)
        if !replyOK {
            for item in m.items { releaseItem(item) }
            return ([], 0, true)
        }
        let bits = (m.complex ? MachMsgBits.complex : 0) | MachMsgBits.make(remote: m.replyType, local: m.destinationType)
        var out: [UInt8] = []
        out.reserveCapacity(m.size + 68)
        out.appendLE(bits)
        out.appendLE(UInt32(m.size))
        out.appendLE(replyName)
        out.appendLE(local)
        out.appendLE(m.voucherRaw)
        out.appendLE(UInt32(bitPattern: m.id))
        var resource: UInt32 = 0
        if m.complex {
            out.appendLE(UInt32(m.items.count))
            for item in m.items {
                out += copyoutItem(item, options: options, buffer: buffer, memory: memory, resource: &resource)
            }
        }
        out += m.inline
        return (out, resource, false)
    }

    func releaseItem(_ item: KItem) {
        switch item {
        case let .port(r, _), let .guarded(r, _, _): release(r)
        case let .oolPorts(rights, _, _): rights.forEach(release)
        case .ool: break
        }
    }

    func copyoutItem(_ item: KItem, options: UInt64, buffer: UInt64, memory: any GuestVirtualMemory,
                     resource: inout UInt32, pseudo: Bool = false) -> [UInt8] {
        switch item {
        case let .port(r, type):
            let (name, ok) = copyout(r)
            if !ok { resource |= MachMsgReturn.ipcSpace }
            return le32(name) + le32(0) + [0, 0, UInt8(truncatingIfNeeded: type), MachMsgDescriptor.port]

        case let .ool(data, copy, volatile):
            var address: UInt64 = 0
            var size = UInt32(data.count)
            if !data.isEmpty {
                do {
                    address = try memory.mapAnonymous(at: nil, size: roundUp(UInt64(data.count), to: DarwinKernel.pageSize),
                                                      protection: .readWrite, hint: nil)
                    try memory.write(va: address, bytes: data)
                } catch {
                    if address != 0 { unmapRange(address, UInt64(data.count), memory) }
                    address = 0
                    size = 0
                    resource |= MachMsgReturn.vmSpace
                }
            }
            return le64(address) + [copy == MachMsgDescriptor.virtualCopy ? 1 : 0, copy, 0,
                                    volatile ? MachMsgDescriptor.oolVolatile : MachMsgDescriptor.ool] + le32(size)

        case let .oolPorts(rights, type, _):
            var address: UInt64 = 0
            var count = UInt32(rights.count)
            if !rights.isEmpty {
                do {
                    address = try memory.mapAnonymous(at: nil, size: roundUp(UInt64(rights.count) * 4, to: DarwinKernel.pageSize),
                                                      protection: .readWrite, hint: nil)
                    var names: [UInt8] = []
                    for r in rights {
                        let (name, ok) = copyout(r)
                        if !ok { resource |= MachMsgReturn.ipcSpace }
                        names += le32(name)
                    }
                    try memory.write(va: address, bytes: names)
                } catch {
                    rights.forEach(release)
                    address = 0
                    count = 0
                    resource |= MachMsgReturn.vmSpace
                }
            }
            return le64(address) + [1, MachMsgDescriptor.virtualCopy, UInt8(truncatingIfNeeded: type),
                                    MachMsgDescriptor.oolPorts] + le32(count)

        case let .guarded(r, flags, type):
            var name: UInt32 = 0
            var context: UInt64 = 0
            if pseudo || options & MachMsgOption.rcvGuardedDesc != 0 {
                let (n, ok) = copyout(r)
                name = n
                if !ok { resource |= MachMsgReturn.ipcSpace }
                if !pseudo, ok, flags & MachMsgDescriptor.guardImmovableReceive != 0, case let .receive(p) = r {
                    p.guarded = true
                    p.context = buffer
                    p.immovable = true
                    context = buffer
                }
            } else {
                release(r)
            }
            return le64(context) + [UInt8(flags & 0xFF), UInt8(flags >> 8), UInt8(truncatingIfNeeded: type),
                                    MachMsgDescriptor.guardedPort] + le32(name)
        }
    }

    func pseudoReceive(_ m: KMessage, memory: any GuestVirtualMemory) -> (bytes: [UInt8], resource: UInt32) {
        var resource: UInt32 = 0
        let (destName, destOK) = copyout(m.destination)
        let (replyName, replyOK) = copyout(m.reply)
        if !destOK || !replyOK { resource |= MachMsgReturn.ipcSpace }
        let bits = (m.complex ? MachMsgBits.complex : 0) | MachMsgBits.make(remote: m.destinationType, local: m.replyType)
        var out: [UInt8] = []
        out += le32(bits)
        out += le32(UInt32(m.size))
        out += le32(destName)
        out += le32(replyName)
        out += le32(m.voucherRaw)
        out += le32(UInt32(bitPattern: m.id))
        if m.complex {
            out += le32(UInt32(m.items.count))
            for item in m.items {
                out += copyoutItem(item, options: 0, buffer: 0, memory: memory, resource: &resource, pseudo: true)
            }
        }
        out += m.inline
        return (out, resource)
    }
}
