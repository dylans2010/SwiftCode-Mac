import SwiftCodeDarwinABI

final class MachTimer {
    weak var port: IPCPort?
    var deadline: UInt64?
    var armedTicks: UInt64 = 0

    init(port: IPCPort) { self.port = port }
}

extension MachIPC {
    func mkTimerCreate() -> UInt32 {
        let p = newPort()
        guard let name = newEntry(bits: MachPortType.receive, urefs: 0, port: p) else { return 0 }
        p.receiver = self
        p.mkTimer = MachTimer(port: p)
        p.srights += 1
        return name
    }

    func mkTimer(named name: UInt32) -> Result<MachTimer, KernError> {
        guard MachPortName.isValid(name), let i = lookup(name) else { return .failure(KernError(MachKern.invalidName)) }
        guard entries[i].bits & MachPortType.receive != 0, let p = entries[i].port else {
            return .failure(KernError(MachKern.invalidRight))
        }
        guard let t = p.mkTimer else { return .failure(KernError(MachKern.invalidArgument)) }
        return .success(t)
    }

    func mkTimerExpire(_ t: MachTimer) {
        guard let p = t.port, p.active else { return }
        if p.messages.all.contains(where: { $0.isTimerExpiry }) { return }
        p.srights += 1
        var m = KMessage(complex: false, destination: .send(p), destinationType: MachMsgType.portSend,
                         reply: .null, replyType: 0, id: 0)
        m.inline = [UInt8](repeating: 0, count: 24)
        m.fromKernel = true
        m.isTimerExpiry = true
        sendKernelMessage(m)
    }
}

extension DarwinKernel {
    static let mkTimerCreate = -91, mkTimerDestroy = -92, mkTimerArm = -93, mkTimerCancel = -94, mkTimerArmLeeway = -95

    func mkTimerTrap(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) -> UInt64? {
        guard n <= Self.mkTimerCreate, n >= Self.mkTimerArmLeeway else { return nil }
        return withEvents { withPorts { mkTimerTrapLocked(n, a, &call, mem) } }
    }

    private func mkTimerTrapLocked(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) -> UInt64? {
        guard let ipc = machIPC as? MachIPC else { return nil }
        let name = UInt32(truncatingIfNeeded: a[0])
        switch n {
        case Self.mkTimerCreate:
            call.set("mk_timer_create()")
            return UInt64(ipc.mkTimerCreate())
        case Self.mkTimerDestroy:
            call.set("mk_timer_destroy(\(hx(name)))")
            switch ipc.mkTimer(named: name) {
            case let .failure(e): return UInt64(e.code)
            case .success: return UInt64(ipc.portDestroy(name))
            }
        case Self.mkTimerArm, Self.mkTimerArmLeeway:
            let ticks = n == Self.mkTimerArm ? a[1] : a[2]
            call.set(n == Self.mkTimerArm ? "mk_timer_arm(\(hx(name)), \(hx(ticks)))"
                : "mk_timer_arm_leeway(\(hx(name)), flags=\(hx(a[1])), \(hx(ticks)), leeway=\(hx(a[3])))")
            switch ipc.mkTimer(named: name) {
            case let .failure(e): return UInt64(e.code)
            case let .success(t):
                t.armedTicks = ticks
                t.deadline = hostDeadline(machTicks: ticks)
                kevents.mkTimers[ObjectIdentifier(t)] = t
                if ticks <= counter() {
                    _ = fireDueTimers()
                } else {
                    startTimerThreadIfNeeded()
                    kevents.timerWake.wakeAll()
                }
                return 0
            }
        case Self.mkTimerCancel:
            call.set("mk_timer_cancel(\(hx(name)), \(hx(a[1])))")
            switch ipc.mkTimer(named: name) {
            case let .failure(e): return UInt64(e.code)
            case let .success(t):
                let armed = t.deadline != nil ? t.armedTicks : 0
                t.deadline = nil
                kevents.mkTimers[ObjectIdentifier(t)] = nil
                if a[1] != 0, (try? mem.write(va: a[1], bytes: le64(armed))) == nil { return UInt64(MachKern.failure) }
                return 0
            }
        default:
            return nil
        }
    }

    func fireDueMachTimers(now: UInt64) -> UInt64? {
        withPorts { fireDueMachTimersLocked(now: now) }
    }

    private func fireDueMachTimersLocked(now: UInt64) -> UInt64? {
        var next: UInt64?
        for (key, t) in kevents.mkTimers {
            guard let p = t.port, p.active, let d = t.deadline else {
                kevents.mkTimers[key] = nil
                continue
            }
            if d <= now {
                if let hook = KernelTrace.timerFired { hook(pid, now &- d, 0) }
                t.deadline = nil
                kevents.mkTimers[key] = nil
                (machIPC as? MachIPC)?.mkTimerExpire(t)
            } else {
                next = min(next ?? d, d)
            }
        }
        return next
    }
}
