import Foundation
import SwiftCodeDarwinABI

final class KernelPipe {
    static let capacity = 65536
    static let smallSize = 16384
    static let atomicLimit = 512

    let lock: KernelLock
    let signals = ObjectSignals()
    var buffer = ByteQueue()
    var readerOpen = true
    var writerOpen = true
    let inode = DescriptorInodes.make()
    var accessTime = descriptorNow()
    var modifyTime = descriptorNow()
    weak var readEnd: PipeEnd?
    weak var writeEnd: PipeEnd?

    init(lock: KernelLock) { self.lock = lock }

    var space: Int { readerOpen ? Self.capacity - buffer.count : 0 }

    func changed() {
        signals.fire()
        readEnd?.signals.fire()
        writeEnd?.signals.fire()
    }

    var blockSize: Int { buffer.count > Self.smallSize ? Self.capacity : Self.smallSize }
}

final class PipeEnd: KernelDescriptorObject {
    let pipe: KernelPipe
    let isReadEnd: Bool
    let signals = ObjectSignals()

    init(pipe: KernelPipe, isReadEnd: Bool) {
        self.pipe = pipe
        self.isReadEnd = isReadEnd
    }

    var fileType: UInt16 { DarwinStat.S_IFIFO }

    func lastReferenceClosed() {
        pipe.lock.withLock {
            if isReadEnd {
                pipe.readerOpen = false
                pipe.buffer.removeAll()
            } else {
                pipe.writerOpen = false
            }
            pipe.changed()
        }
    }

    func descriptorStat() -> DarwinStat {
        let size = Int64(pipe.buffer.count)
        let blk = Int64(pipe.blockSize)
        return DarwinStat(mode: DarwinStat.S_IFIFO | 0o660, nlink: 0, ino: pipe.inode, uid: DarwinFileSystem.guestUID,
                          gid: DarwinFileSystem.guestGID, atime: pipe.accessTime, mtime: pipe.modifyTime,
                          ctime: pipe.modifyTime, size: size, blocks: (size + blk - 1) / blk, blksize: Int32(blk))
    }

    func readReadiness() -> (ready: Bool, data: Int64, eof: Bool) {
        guard isReadEnd else { return (false, 0, !pipe.readerOpen) }
        let n = pipe.buffer.count
        return (n > 0 || !pipe.writerOpen, Int64(n), !pipe.writerOpen)
    }

    func writeReadiness() -> (ready: Bool, data: Int64, eof: Bool) {
        guard !isReadEnd else { return (false, 0, !pipe.writerOpen) }
        if !pipe.readerOpen { return (true, 0, true) }
        let space = pipe.space
        return (space >= KernelPipe.atomicLimit, Int64(space), false)
    }

    func addReadinessObserver(_ observer: @escaping () -> Void) -> Int { signals.addObserver(observer) }
    func removeReadinessObserver(_ token: Int) { signals.removeObserver(token) }
}

extension DarwinKernel {
    func makePipe() throws -> (Int32, Int32) {
        guard fileSystem.freeDescriptorCount >= 2 else { throw fail(Code.EMFILE) }
        let p = KernelPipe(lock: lock)
        let r = PipeEnd(pipe: p, isReadEnd: true)
        let w = PipeEnd(pipe: p, isReadEnd: false)
        p.readEnd = r
        p.writeEnd = w
        let rfd = try fileSystem.installObject(r, statusFlags: DarwinOpen.O_RDONLY, closeOnExec: false)
        let wfd = try fileSystem.installObject(w, statusFlags: DarwinOpen.O_WRONLY, closeOnExec: false)
        return (rfd, wfd)
    }

    func pipeRead(_ end: PipeEnd, _ file: DarwinOpenFile, count: Int) throws -> [UInt8] {
        let p = end.pipe
        guard count > 0 else { return [] }
        while true {
            if !p.buffer.isEmpty {
                let bytes = p.buffer.take(min(count, DarwinFileSystem.maxTransfer))
                p.accessTime = descriptorNow()
                p.changed()
                return bytes
            }
            if !p.writerOpen { return [] }
            if file.isNonBlocking { throw fail(Code.EAGAIN) }
            _ = try waitOnObject(p.signals, deadline: nil)
        }
    }

    func pipeWrite(_ end: PipeEnd, _ file: DarwinOpenFile, _ bytes: [UInt8]) throws -> Int {
        let p = end.pipe
        let atomic = bytes.count <= KernelPipe.atomicLimit
        var written = 0
        while true {
            guard p.readerOpen else {
                if written > 0 { return written }
                if !file.noSigPipe { postSignal(descriptorSIGPIPE, thread: current) }
                throw fail(Code.EPIPE)
            }
            if written == bytes.count && (written > 0 || bytes.isEmpty) { return written }
            let remaining = bytes.count - written
            let space = p.space
            if space > 0 && (!atomic || space >= remaining) {
                let n = min(space, remaining)
                p.buffer.append(contentsOf: bytes[written..<(written + n)])
                written += n
                p.modifyTime = descriptorNow()
                p.changed()
                continue
            }
            if file.isNonBlocking {
                if written > 0 { return written }
                throw fail(Code.EAGAIN)
            }
            do {
                _ = try waitOnObject(p.signals, deadline: nil)
            } catch {
                if written > 0 { return written }
                throw error
            }
        }
    }
}
