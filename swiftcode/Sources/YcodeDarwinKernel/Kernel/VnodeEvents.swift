import Foundation
import Synchronization
import YcodeDarwinABI

final class VnodeKnoteWatch: VnodeWatcher, @unchecked Sendable {
    weak var knote: Knote?
    weak var kernel: DarwinKernel?
    let key: HostFileKey
    let interest: Atomic<UInt32>

    init(knote: Knote, kernel: DarwinKernel, key: HostFileKey, interest: UInt32) {
        self.knote = knote
        self.kernel = kernel
        self.key = key
        self.interest = Atomic(interest)
    }

    func vnodeNotesPosted(_ notes: UInt32) {
        guard notes & (interest.load(ordering: .relaxed) | VnodeNote.revoke) != 0, let kernel, let knote else { return }
        kernel.vnodeNotesPosted(knote, notes)
    }
}

extension DarwinKernel {
    func attachVnode(_ kn: Knote, _ c: KEventRecord) -> Int32? {
        guard c.ident <= UInt64(Int32.max) else { return Errno.EBADF }
        let fd = Int32(c.ident)
        let open: DarwinOpenFile
        do {
            _ = try fileSystem.closeOnExec(fd)
            open = try fileSystem.openFile(for: fd)
        } catch {
            return errno(of: error, default: Errno.EBADF)
        }
        kn.data = 0
        kn.vnodeFired = 0
        guard let file = open.guestFile, let key = file.hostKey else {
            trace("note: EVFILT_VNODE on descriptor \(fd), which is no file or directory: it never fires")
            return nil
        }
        let watch = VnodeKnoteWatch(knote: kn, kernel: self, key: key, interest: c.fflags)
        kn.vnodeWatch = watch
        VnodeNotes.add(watch, key: key)
        if Self.debugVnode {
            FileHandle.standardError.write(Data(("swiftcode-vnode: pid \(pid) (\(processRecord?.comm ?? "?")) watches \(file.guestPath) "
                + "fflags \(hx(UInt64(c.fflags))) flags \(hx(UInt64(c.flags))); \(VnodeNotes.count) watched\n").utf8))
        }
        return nil
    }

    static let debugVnode = getenv("SWIFTCODE_DEBUG_VNODE").map { String(cString: $0) == "1" } ?? false

    func detachVnode(_ kn: Knote) {
        guard let watch = kn.vnodeWatch else { return }
        kn.vnodeWatch = nil
        VnodeNotes.remove(watch, key: watch.key)
    }

    func reattachVnodeAfterRestore(_ kn: Knote) {
        guard kn.filter == EVFilter.vnode, !kn.dropped, kn.vnodeWatch == nil, kn.ident <= UInt64(Int32.max),
              let open = try? fileSystem.openFile(for: Int32(kn.ident)), let key = open.guestFile?.hostKey else { return }
        let watch = VnodeKnoteWatch(knote: kn, kernel: self, key: key, interest: kn.fflags)
        kn.vnodeWatch = watch
        VnodeNotes.add(watch, key: key)
    }

    func vnodeNotesPosted(_ kn: Knote, _ notes: UInt32) {
        guard !isTerminating else { return }
        let work: () -> Void = { [weak self, weak kn] in
            guard let self, let kn else { return }
            self.withEvents { self.vnodeNotesPostedLocked(kn, notes) }
        }
        if let events = eventLock {
            lock.deferIfFast(.fineLock(events), tag: "vnode note", work)
        } else {
            lock.withLock(work)
        }
    }

    func vnodeNotesPostedLocked(_ kn: Knote, _ notes: UInt32) {
        guard !kn.dropped else { return }
        if notes & VnodeNote.revoke != 0 {
            kn.vnodeRevoked = true
            kn.flags |= EV.eof | EV.oneshot
            kn.vnodeFired |= kn.fflags & VnodeNote.revoke
        } else {
            let wanted = kn.fflags & notes
            guard wanted != 0 else { return }
            kn.vnodeFired |= wanted
        }
        kn.note("vnode notes \(hx(UInt64(notes))) -> fired \(hx(UInt64(kn.vnodeFired)))")
        kn.active = true
        activated(kn)
    }

    func deliverVnode(_ kn: Knote, into e: inout KEventRecord) {
        e.fflags = kn.vnodeFired
        e.data = 0
        if Self.debugVnode {
            FileHandle.standardError.write(Data(("swiftcode-vnode: pid \(pid) (\(processRecord?.comm ?? "?")) gets fd \(kn.ident) "
                + "notes \(hx(UInt64(kn.vnodeFired)))\n").utf8))
        }
        if kn.flags & EV.clear != 0 { kn.vnodeFired = 0 }
    }
}
