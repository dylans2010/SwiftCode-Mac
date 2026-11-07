import YcodeDarwinABI

struct MachMemoryEntry {
    let object: SharedMemoryObject
    let offset: UInt64
    let size: UInt64
    let protection: VMProtection
}

extension MachIPC {
    enum MapMem {
        static let only: UInt32 = 0x01_0000
        static let namedCreate: UInt32 = 0x02_0000
        static let useDataAddr: UInt32 = 0x10_0000
        static let vmCopy: UInt32 = 0x20_0000
        static let vmShare: UInt32 = 0x40_0000
    }
    static let vmProtIsMask: UInt32 = 0x40
    static let vmFlagsAnywhere: UInt32 = 0x1
    static let vmFlagsOverwrite: UInt32 = 0x4000
    static let kernInvalidObject: UInt32 = 29

    private static var page: UInt64 { VMLayout.pageSize }
    private static func truncPage(_ v: UInt64) -> UInt64 { v & ~(page - 1) }
    private static func roundPage(_ v: UInt64) -> UInt64? { v > UInt64.max - (page - 1) ? nil : (v + page - 1) & ~(page - 1) }

    func memoryEntry(named name: UInt32) -> MachMemoryEntry? {
        guard let (p, object) = kernelObject(named: name), case .memoryEntry = object, p.active else { return nil }
        return p.memoryEntry
    }

    func makeMemoryEntry(_ a: [UInt64], memory: any GuestVirtualMemory) -> (UInt32, String) {
        let task = UInt32(truncatingIfNeeded: a[0])
        guard isTaskSelf(task) else {
            return (MachPortName.isValid(task) && lookup(task) != nil ? MachKern.invalidArgument : MachMsgReturn.sendInvalidDest, "")
        }
        guard let sizeBytes = try? memory.read(va: a[1], count: 8) else { return (MachKern.invalidAddress, "") }
        let requestedSize = sizeBytes.readLE(UInt64.self, at: 0)
        let offset = a[2]
        let permission = UInt32(truncatingIfNeeded: a[3])
        let protection = VMProtection(rawValue: permission & 7)
        let parentName = UInt32(truncatingIfNeeded: a[5])
        var parent: MachMemoryEntry?
        if MachPortName.isValid(parentName) {
            guard let p = memoryEntry(named: parentName) else { return (MachKern.invalidArgument, "") }
            parent = p
        }
        if permission & MapMem.only != 0 {
            return parent == nil ? (MachKern.invalidArgument, "") : (MachKern.success, " [MAP_MEM_ONLY]")
        }
        let made: Result<(MachMemoryEntry, String), KernError2> = lock.withoutFineLock {
            let entry: MachMemoryEntry
            let start = Self.truncPage(offset)
            guard offset <= UInt64.max - requestedSize, let end = Self.roundPage(offset + requestedSize) else {
                return .failure(KernError2(MachKern.invalidArgument, ""))
            }
            var how: String
            if permission & MapMem.namedCreate != 0 {
                guard let size = Self.roundPage(requestedSize), size > 0,
                      let object = try? SharedMemoryObject(size: size) else { return .failure(KernError2(MachKern.invalidArgument, "")) }
                entry = MachMemoryEntry(object: object, offset: 0, size: size, protection: protection)
                how = "new object"
            } else if permission & MapMem.vmCopy != 0 {
                guard end > start, let bytes = try? memory.read(va: start, count: Int(end - start)),
                      let object = try? SharedMemoryObject(size: end - start) else { return .failure(KernError2(MachKern.invalidArgument, "")) }
                object.write(offset: 0, bytes: bytes)
                entry = MachMemoryEntry(object: object, offset: 0, size: end - start, protection: protection)
                how = "copy of \(hx(start))-\(hx(end))"
            } else if permission & MapMem.vmShare != 0 || parent == nil {
                guard end > start else { return .failure(KernError2(MachKern.invalidArgument, "")) }
                var cursor = start
                for r in memory.regions(overlapping: start..<end) {
                    guard r.va <= cursor else { return .failure(KernError2(MachKern.invalidArgument, "")) }
                    guard r.protection.isSuperset(of: protection) else { return .failure(KernError2(MachKern.protectionFailure, "")) }
                    cursor = max(cursor, r.end)
                }
                guard cursor >= end else { return .failure(KernError2(MachKern.invalidArgument, "")) }
                guard let (object, objectOffset) = try? memory.share(va: start, size: end - start) else {
                    return .failure(KernError2(MachKern.invalidArgument, ""))
                }
                entry = MachMemoryEntry(object: object, offset: objectOffset, size: end - start, protection: protection)
                how = "share of \(hx(start))-\(hx(end))"
            } else {
                let parent = parent!
                guard end > start, end <= parent.size else { return .failure(KernError2(MachKern.invalidArgument, "")) }
                guard parent.protection.isSuperset(of: protection) else { return .failure(KernError2(MachKern.protectionFailure, "")) }
                entry = MachMemoryEntry(object: parent.object, offset: parent.offset + start, size: end - start,
                                        protection: protection)
                how = "sub-entry \(hx(start))-\(hx(end)) of the parent"
            }
            return .success((entry, how))
        }
        let entry: MachMemoryEntry, how: String
        switch made {
        case let .failure(e): return (e.code, e.note)
        case let .success(v): (entry, how) = v
        }
        guard let (p, name) = makeKernelObjectName(.memoryEntry(serial: nextSerial())) else { return (MachKern.noSpace, "") }
        p.memoryEntry = entry
        own(p)
        let outSize = permission & MapMem.useDataAddr != 0 ? requestedSize : entry.size
        guard (try? memory.write(va: a[1], bytes: le64(outSize))) != nil,
              (try? memory.write(va: a[4], bytes: le32(name))) != nil else {
            _ = portDeallocate(name)
            return (MachKern.invalidAddress, "")
        }
        return (MachKern.success, " [\(how): object #\(entry.object.serial) @\(hx(entry.offset)) size \(hx(entry.size)) "
            + "prot \(entry.protection) -> \(hx(name))]")
    }

    func vmMapObject(_ a: [UInt64], memory: any GuestVirtualMemory) -> (UInt32, String) {
        let task = UInt32(truncatingIfNeeded: a[0])
        guard isTaskSelf(task) else {
            return (MachPortName.isValid(task) && lookup(task) != nil ? MachKern.invalidArgument : MachMsgReturn.sendInvalidDest, "")
        }
        guard let block = try? memory.read(va: a[5], count: 48),
              let requested = (try? memory.read(va: a[1], count: 8))?.readLE(UInt64.self, at: 0) else {
            return (MachKern.invalidAddress, "")
        }
        let objectName = block.readLE(UInt32.self, at: 0)
        let offset = block.readLE(UInt64.self, at: 8)
        let copy = block.readLE(UInt64.self, at: 16) & 0xFFFF_FFFF != 0
        let curBits = block.readLE(UInt32.self, at: 24), maxBits = block.readLE(UInt32.self, at: 32)
        let flags = UInt32(truncatingIfNeeded: a[4])
        guard let entry = memoryEntry(named: objectName) else { return (Self.kernInvalidObject, "") }
        return lock.withoutFineLock { () -> (UInt32, String) in
            var cur = VMProtection(rawValue: curBits & 7), max = VMProtection(rawValue: maxBits & 7)
            if curBits & Self.vmProtIsMask != 0 { cur.formIntersection(entry.protection) }
            if maxBits & Self.vmProtIsMask != 0 { max.formIntersection(entry.protection) }
            guard entry.protection.isSuperset(of: max), entry.protection.isSuperset(of: cur) else {
                return (MachKern.invalidRight, "")
            }
            guard offset & (Self.page - 1) == 0, offset < entry.size else { return (MachKern.invalidArgument, "") }
            guard let size = a[2] == 0 ? entry.size - offset : Self.roundPage(a[2]), size > 0, size <= entry.size - offset else {
                return (MachKern.invalidArgument, "")
            }
            let alignment = (a[3] | (Self.page - 1)) &+ 1
            var at: UInt64?
            var hint: UInt64?
            if flags & Self.vmFlagsAnywhere != 0 {
                hint = requested == 0 ? nil : Self.truncPage(requested)
                if alignment > Self.page {
                    guard let raw = try? memory.mapAnonymous(at: nil, size: size + alignment, protection: [], hint: hint) else {
                        return (MachKern.noSpace, "")
                    }
                    try? memory.unmap(va: raw, size: size + alignment)
                    at = (raw + alignment - 1) & ~(alignment - 1)
                }
            } else {
                guard requested & (Self.page - 1) == 0 else { return (MachKern.invalidArgument, "") }
                if flags & Self.vmFlagsOverwrite == 0,
                   !memory.regions(overlapping: requested..<Swift.max(requested, requested &+ size)).isEmpty {
                    return (MachKern.noSpace, "")
                }
                at = requested
            }
            let va: UInt64
            do {
                if copy {
                    va = try memory.mapAnonymous(at: at, size: size, protection: .readWrite, hint: hint)
                    try memory.write(va: va, bytes: entry.object.read(offset: entry.offset + offset, count: Int(size)))
                    if cur != .readWrite { try memory.protect(va: va, size: size, protection: cur) }
                } else {
                    va = try memory.mapShared(entry.object, offset: entry.offset + offset, at: at, size: size,
                                              protection: cur, hint: hint)
                }
            } catch {
                return (MachKern.noSpace, "")
            }
            guard (try? memory.write(va: a[1], bytes: le64(va))) != nil else { return (MachKern.invalidAddress, "") }
            return (MachKern.success, " [object \(hx(objectName)) #\(entry.object.serial) @\(hx(entry.offset + offset)) "
                + "\(copy ? "copied" : "shared") at \(hx(va)) size \(hx(size)) prot \(cur)]")
        }
    }
}

struct KernError2: Error {
    var code: UInt32
    var note: String
    init(_ code: UInt32, _ note: String) {
        self.code = code
        self.note = note
    }
}

extension MachIPC {
    func vmRemap(_ a: [UInt64], memory: any GuestVirtualMemory) -> (UInt32, String) {
        let task = UInt32(truncatingIfNeeded: a[0])
        guard isTaskSelf(task) else { return (MachKern.invalidArgument, " [only the caller's task]") }
        guard let block = try? memory.read(va: a[5], count: 56),
              let requested = (try? memory.read(va: a[1], count: 8))?.readLE(UInt64.self, at: 0) else {
            return (MachKern.invalidAddress, "")
        }
        let srcTask = block.readLE(UInt32.self, at: 0)
        let srcAddress = block.readLE(UInt64.self, at: 8)
        let copy = block.readLE(UInt32.self, at: 16) != 0
        let curPointer = block.readLE(UInt64.self, at: 24), maxPointer = block.readLE(UInt64.self, at: 32)
        let isNew = block.readLE(UInt32.self, at: 48) != 0
        guard isTaskSelf(srcTask) else { return (MachKern.invalidArgument, " [only the caller's task as source]") }
        return lock.withoutFineLock { () -> (UInt32, String) in
            let page = VMLayout.pageSize
            let flags = UInt32(truncatingIfNeeded: a[4])
            guard a[2] > 0, srcAddress <= UInt64.max - a[2] else { return (MachKern.invalidArgument, "") }
            let start = srcAddress & ~(page - 1)
            let end = (srcAddress + a[2] + page - 1) & ~(page - 1)
            let size = end - start
            var cursor = start
            var protection: VMProtection = .all
            for r in memory.regions(overlapping: start..<end) {
                guard r.va <= cursor else { return (MachKern.invalidAddress, "") }
                protection.formIntersection(r.protection)
                cursor = max(cursor, r.end)
            }
            guard cursor >= end else { return (MachKern.invalidAddress, "") }
            if isNew {
                guard let cur = try? memory.read(va: curPointer, count: 4).readLE(UInt32.self, at: 0) else {
                    return (MachKern.invalidAddress, "")
                }
                let wanted = VMProtection(rawValue: cur & 7)
                guard protection.isSuperset(of: wanted) || copy else { return (MachKern.protectionFailure, "") }
                if !copy { protection = wanted }
            }
            let alignment = (a[3] | (page - 1)) &+ 1
            var at: UInt64?, hint: UInt64?
            if flags & Self.vmFlagsAnywhere != 0 {
                hint = requested == 0 ? nil : requested & ~(page - 1)
                if alignment > page {
                    guard let raw = try? memory.mapAnonymous(at: nil, size: size + alignment, protection: [], hint: hint) else {
                        return (MachKern.noSpace, "")
                    }
                    try? memory.unmap(va: raw, size: size + alignment)
                    at = (raw + alignment - 1) & ~(alignment - 1)
                }
            } else {
                guard requested & (page - 1) == 0 else { return (MachKern.invalidArgument, "") }
                if flags & Self.vmFlagsOverwrite == 0,
                   !memory.regions(overlapping: requested..<Swift.max(requested, requested &+ size)).isEmpty {
                    return (MachKern.noSpace, "")
                }
                at = requested
            }
            let va: UInt64
            do {
                if copy {
                    let bytes = try memory.read(va: start, count: Int(size))
                    va = try memory.mapAnonymous(at: at, size: size, protection: .readWrite, hint: hint)
                    try memory.write(va: va, bytes: bytes)
                    if protection != .readWrite { try memory.protect(va: va, size: size, protection: protection) }
                } else {
                    let (object, offset) = try memory.share(va: start, size: size)
                    va = try memory.mapShared(object, offset: offset, at: at, size: size, protection: protection, hint: hint)
                }
            } catch {
                return (MachKern.noSpace, " [\(error)]")
            }
            let maxProtection: VMProtection = .all
            guard (try? memory.write(va: a[1], bytes: le64(va))) != nil,
                  (try? memory.write(va: curPointer, bytes: le32(protection.rawValue))) != nil,
                  (try? memory.write(va: maxPointer, bytes: le32(maxProtection.rawValue))) != nil else {
                return (MachKern.invalidAddress, "")
            }
            return (MachKern.success, " [\(hx(start))-\(hx(end)) \(copy ? "copied" : "shared") at \(hx(va)) prot \(protection)]")
        }
    }
}

extension DarwinKernel {
    func taskThreads(_ a: [UInt64], memory: any GuestVirtualMemory) -> (UInt32, String) {
        guard let ipc = machIPC as? MachIPC else { return (MachKern.failure, "") }
        guard ipc.isTaskSelf(UInt32(truncatingIfNeeded: a[0])) else { return (MachKern.invalidArgument, " [only the caller's task]") }
        let threads = threadsByPort.values.filter(\.isAlive).sorted { $0.threadID < $1.threadID }
        var names: [UInt32] = []
        for t in threads {
            if let (p, _) = ipc.kernelObject(named: t.portName) { names.append(ipc.copyoutNewSend(p)) }
        }
        var list: UInt64 = 0
        if !names.isEmpty {
            let bytes = names.flatMap { le32($0) }
            guard let va = try? memory.mapAnonymous(at: nil, size: UInt64(bytes.count), protection: .readWrite, hint: nil),
                  (try? memory.write(va: va, bytes: bytes)) != nil else {
                names.forEach { _ = ipc.portDeallocate($0) }
                return (MachKern.resourceShortage, "")
            }
            list = va
        }
        guard (try? memory.write(va: a[1], bytes: le64(list))) != nil,
              (try? memory.write(va: a[2], bytes: le32(UInt32(names.count)))) != nil else {
            return (MachKern.invalidAddress, "")
        }
        return (MachKern.success, " [\(names.count) threads at \(hx(list))]")
    }
}
