import YcodeDarwinABI

public enum TaskSpecialPort {
    public static let kernel: Int32 = 1
    public static let host: Int32 = 2
    public static let name: Int32 = 3
    public static let bootstrap: Int32 = 4
    public static let inspect: Int32 = 5
    public static let read: Int32 = 6
    public static let access: Int32 = 9
    public static let debugControl: Int32 = 10
    public static let resourceNotify: Int32 = 11
}

public enum MachException {
    public static let validMask: UInt32 = 0x3FFE
    public static let slotCount = 14
    public static let behaviorFlags: UInt32 = 0x8000_0000 | 0x4000_0000 | 0x2000_0000
    public static let behaviors: ClosedRange<UInt32> = 1...5

    public static func isValidBehavior(_ b: UInt32) -> Bool { behaviors.contains(b & ~behaviorFlags) }
}

struct ExceptionSlot {
    var port: CarriedRight = .null
    var behavior: UInt32 = 0
    var flavor: UInt32 = 0
}

struct TaskPortSlots {
    var host: CarriedRight = .null
    var bootstrap: CarriedRight = .null
    var access: CarriedRight = .null
    var debugControl: CarriedRight = .null
    var resourceNotify: CarriedRight = .null
    var registered: [CarriedRight] = [.null, .null, .null]
    var exceptions = [ExceptionSlot](repeating: ExceptionSlot(), count: MachException.slotCount)
}

enum TaskLookup {
    case task(MachIPC)
    case invalidDest
    case notTask
}

extension MachIPC {

    func taskControl(named name: UInt32) -> TaskLookup {
        guard MachPortName.isValid(name), let i = lookup(name), entries[i].bits & T.send != 0,
              let p = entries[i].port else { return .invalidDest }
        guard p.kernelObject == .task else { return .notTask }
        guard p.active, let task = p.task, !task.isTerminated else { return .invalidDest }
        return .task(task)
    }

    func space(forPID pid: Int32) -> MachIPC? {
        if pid == (kernel?.pid ?? self.pid), !isTerminated { return self }
        guard let k = kernel?.system.kernel(forPID: pid), let ipc = k.machIPC as? MachIPC,
              !ipc.isTerminated else { return nil }
        return ipc
    }

    var currentPID: Int32 { kernel?.pid ?? pid }

    func copySend(_ r: CarriedRight) -> CarriedRight {
        if case let .send(p) = r {
            p.srights += 1
            return .send(p)
        }
        return r
    }

    func flavorPort(_ object: MachKernelObject) -> IPCPort {
        switch object {
        case .taskName: return taskNamePort
        case .taskRead:
            if let p = taskReadPort { return p }
            let p = newPort()
            p.kernelObject = .taskRead
            p.task = self
            taskReadPort = p
            return p
        case .taskInspect:
            if let p = taskInspectPort { return p }
            let p = newPort()
            p.kernelObject = .taskInspect
            p.task = self
            taskInspectPort = p
            return p
        default: return taskPort
        }
    }

    func getSpecialPort(_ which: Int32) -> Result<CarriedRight, KernError> {
        if isTerminated { return .failure(KernError(MachKern.failure)) }
        switch which {
        case TaskSpecialPort.kernel: return .success(copySend(.send(taskPort)))
        case TaskSpecialPort.name: return .success(copySend(.send(taskNamePort)))
        case TaskSpecialPort.inspect: return .success(copySend(.send(flavorPort(.taskInspect))))
        case TaskSpecialPort.read: return .success(copySend(.send(flavorPort(.taskRead))))
        case TaskSpecialPort.host: return .success(copySend(slots.host))
        case TaskSpecialPort.bootstrap: return .success(copySend(slots.bootstrap))
        case TaskSpecialPort.access: return .success(copySend(slots.access))
        case TaskSpecialPort.debugControl: return .success(copySend(slots.debugControl))
        case TaskSpecialPort.resourceNotify: return .success(copySend(slots.resourceNotify))
        default: return .failure(KernError(MachKern.invalidArgument))
        }
    }

    func checkSetSpecialPort(_ which: Int32) -> UInt32 {
        if isTerminated { return MachKern.failure }
        switch which {
        case TaskSpecialPort.kernel, TaskSpecialPort.host: return MachKern.noAccess
        case TaskSpecialPort.bootstrap, TaskSpecialPort.debugControl, TaskSpecialPort.resourceNotify:
            return MachKern.success
        case TaskSpecialPort.access:
            if case let .send(p) = slots.access, p.active { return MachKern.noAccess }
            return MachKern.success
        default: return MachKern.invalidArgument
        }
    }

    func setSpecialPort(_ which: Int32, _ right: CarriedRight) -> UInt32 {
        let kr = checkSetSpecialPort(which)
        guard kr == MachKern.success else { return kr }
        let old: CarriedRight
        switch which {
        case TaskSpecialPort.bootstrap: old = slots.bootstrap; slots.bootstrap = right
        case TaskSpecialPort.debugControl: old = slots.debugControl; slots.debugControl = right
        case TaskSpecialPort.resourceNotify: old = slots.resourceNotify; slots.resourceNotify = right
        default: old = slots.access; slots.access = right
        }
        release(old)
        return MachKern.success
    }

    func setRegisteredPorts(_ rights: [CarriedRight]) {
        let old = slots.registered
        slots.registered = (0..<3).map { $0 < rights.count ? rights[$0] : .null }
        old.forEach(release)
    }

    func setExceptionPorts(mask: UInt32, _ right: CarriedRight, behavior: UInt32, flavor: UInt32) -> UInt32 {
        guard mask & ~MachException.validMask == 0 else { return MachKern.invalidArgument }
        if right.port != nil, !MachException.isValidBehavior(behavior) { return MachKern.invalidArgument }
        for type in 1..<MachException.slotCount where mask & (1 << UInt32(type)) != 0 {
            let old = slots.exceptions[type].port
            slots.exceptions[type] = ExceptionSlot(port: copySend(right), behavior: behavior, flavor: flavor)
            release(old)
        }
        release(right)
        return MachKern.success
    }

    public func exceptionPort(type: Int) -> (name: UInt32, behavior: UInt32, flavor: UInt32)? {
        lock.withLock {
            guard (1..<MachException.slotCount).contains(type) else { return nil }
            let slot = slots.exceptions[type]
            guard let p = slot.port.port else { return nil }
            return (reverse[ObjectIdentifier(p)] ?? 0, slot.behavior, slot.flavor)
        }
    }

    func syncWellKnownNames() {
        sync(index: 3, stored: slots.host)
        sync(index: 5, stored: slots.bootstrap)
    }

    private func sync(index: Int, stored: CarriedRight) {
        let target: IPCPort?
        if case let .send(p) = stored, p.active { target = p } else { target = nil }
        if index < entries.count, entries[index].inUse {
            if let target, entries[index].port === target, entries[index].bits & T.send != 0 { return }
            let e = entries[index]
            if e.bits == T.send, let p = e.port {
                freeName(index)
                releaseSend(p)
            } else {
                return
            }
        }
        guard let target else { return }
        if let existing = reverse[ObjectIdentifier(target)], slot(of: existing) != nil { return }
        seed(target, index: index)
        if index >= nextFresh { nextFresh = index + 1 }
    }

    public func inheritTaskPorts(from parent: MachIPC) {
        lock.withLock {
            let old = slots
            var new = TaskPortSlots()
            new.host = copySend(parent.slots.host)
            new.bootstrap = copySend(parent.slots.bootstrap)
            new.access = copySend(parent.slots.access)
            new.registered = parent.slots.registered.map(copySend)
            for type in 1..<MachException.slotCount {
                let s = parent.slots.exceptions[type]
                new.exceptions[type] = ExceptionSlot(port: copySend(s.port), behavior: s.behavior, flavor: s.flavor)
            }
            slots = new
            for r in [old.host, old.bootstrap, old.access, old.debugControl, old.resourceNotify] + old.registered {
                release(r)
            }
            old.exceptions.forEach { release($0.port) }
            let threadSlots = threadExceptions
            threadExceptions = [:]
            threadSlots.values.forEach { $0.forEach { release($0.port) } }
            syncWellKnownNames()
            log("mach inherit task ports from pid \(parent.currentPID)")
        }
    }

    public func applySpawnPortActions(_ actions: [SpawnPortAction], from caller: MachIPC) throws {
        try lock.withLock {
            var exceptions = 0, watches = 0, registered = 0, ptrauth = 0
            for a in actions {
                switch a.kind {
                case .exception: exceptions += 1
                case .importanceWatch: watches += 1
                case .registered: registered += 1
                case .ptrauthTask: ptrauth += 1
                case .special, .auditSession: break
                case nil: throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
                }
            }
            guard exceptions <= 14, watches <= 128, registered <= 3, ptrauth <= 1 else {
                throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
            }
            var rights: [CarriedRight] = []
            for a in actions {
                if !MachPortName.isValid(a.port) {
                    rights.append(a.port == MachPortName.dead ? .dead : .null)
                    continue
                }
                guard case let .success(r) = caller.copyin(a.port, MachMsgType.copySend, slot: .body, apply: true) else {
                    rights.forEach(release)
                    throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
                }
                rights.append(r)
            }
            for a in actions {
                switch a.kind {
                case .special:
                    guard checkSetSpecialPort(a.which) == MachKern.success else {
                        rights.forEach(release)
                        throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
                    }
                case .exception:
                    guard a.mask & ~MachException.validMask == 0,
                          a.port == 0 || MachException.isValidBehavior(a.behavior) else {
                        rights.forEach(release)
                        throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
                    }
                default: break
                }
            }
            var registeredRights: [CarriedRight] = []
            for (a, r) in zip(actions, rights) {
                switch a.kind {
                case .special:
                    if setSpecialPort(a.which, r) != MachKern.success { release(r) }
                case .exception:
                    _ = setExceptionPorts(mask: a.mask, r, behavior: a.behavior, flavor: a.flavor)
                case .registered:
                    registeredRights.append(r)
                case .importanceWatch:
                    if let p = r.port { pendingWatchPorts.append(p) }
                    release(r)
                default:
                    release(r)
                }
            }
            if registered > 0 { setRegisteredPorts(registeredRights) }
            syncWellKnownNames()
            log("mach spawn port actions: \(actions.count) applied from pid \(caller.currentPID)")
        }
    }

    public func terminateTask() {
        lock.withLock {
            guard !isTerminated else { return }
            isTerminated = true
            messageQueuedHandler = nil
            receiveRightGoneHandler = nil
            if let k = kernel {
                pid = k.pid
                pidVersion = k.pidVersion
            }
            for i in entries.indices where entries[i].inUse && entries[i].bits & T.receive != 0 {
                guard let p = entries[i].port else { continue }
                let hadSend = entries[i].bits & T.send != 0
                freeName(i)
                p.receiver = nil
                removeFromAllSets(p)
                p.changeStamp = nextStamp()
                p.receiveWaiters.wakeAll()
                if hadSend { p.srights -= 1 }
                destroyReceive(p)
            }
            for i in entries.indices where entries[i].inUse {
                let e = entries[i]
                freeName(i)
                if let s = e.set {
                    destroySet(s)
                } else if let p = e.port {
                    if e.bits & T.send != 0 {
                        releaseSend(p)
                    } else if e.bits & T.sendOnce != 0 {
                        if p.active { destroySendOnce(p) } else { p.sorights -= 1 }
                    }
                }
            }
            reverse = [:]
            specialReplyPorts = [:]
            let old = slots
            slots = TaskPortSlots()
            for r in [old.host, old.bootstrap, old.access, old.debugControl, old.resourceNotify] + old.registered {
                release(r)
            }
            old.exceptions.forEach { release($0.port) }
            let threadSlots = threadExceptions
            threadExceptions = [:]
            threadSlots.values.forEach { $0.forEach { release($0.port) } }
            for p in [taskPort, taskNamePort, mainThreadPort] + [taskReadPort, taskInspectPort].compactMap({ $0 })
                + ownedKernelPorts {
                portDeath(p)
            }
            ownedKernelPorts = []
            log("mach task terminated (pid \(currentPID))")
        }
    }
}
