#if os(Linux) && arch(arm64)
import CKVM
import Foundation
import Glibc
import Synchronization

public final class SharedFileArena: @unchecked Sendable {
    public static let shared: SharedFileArena? = SharedFileArena(size: defaultSize)
    public static let defaultSize: UInt64 = 64 << 30
    public static let minimumFileSize: UInt64 = 0
    public static let maximumFiles = getenv("SWIFTCODE_ARENA_MAX_FILES").flatMap { Int(String(cString: $0)) } ?? 32768
    private var reportedFull = false
    static let granule: UInt64 = 1 << 14

    public let base: UnsafeMutableRawPointer
    public let size: UInt64

    private struct Key: Hashable {
        var device: UInt64
        var inode: UInt64
        var size: Int64
        var mtimeSeconds: Int
        var mtimeNanoseconds: Int
    }

    private let lock = HostMutex(name: "shared file window")
    private var spans: [Key: (offset: UInt64, span: UInt64)] = [:]
    private var next: UInt64 = 0

    public static let hugeEnabled = hugeWholeFile || hugeHotChunks
    static let hugeWholeFile = getenv("SWIFTCODE_ARENA_HUGE").map { String(cString: $0) == "1" } ?? false
    static let hugeHotChunks = getenv("SWIFTCODE_ARENA_HUGE").map { String(cString: $0) == "hot" } ?? false
    static let hugeInterval = getenv("SWIFTCODE_ARENA_HUGE_INTERVAL_MS").flatMap { UInt32(String(cString: $0)) }.map { max(50, $0) } ?? 1000
    public static let hugeMadvise: Bool = {
        if let v = getenv("SWIFTCODE_ARENA_HUGE_MADVISE") { return String(cString: v) == "1" }
        let mode = (try? String(contentsOfFile: "/sys/kernel/mm/transparent_hugepage/enabled", encoding: .utf8)) ?? ""
        return !mode.contains("[always]")
    }()
    public static let hugeThreads = getenv("SWIFTCODE_ARENA_HUGE_THREADS").flatMap { Int(String(cString: $0)) }.map { max(1, min(32, $0)) } ?? 8
    public static let hugeMinimum: UInt64 = 256 << 20
    static let zeroTails = getenv("SWIFTCODE_ARENA_ZERO_TAILS").map { String(cString: $0) != "0" } ?? true
    static var reserveProtection: Int32 { zeroTails ? PROT_READ : PROT_NONE }
    static let huge: UInt64 = 2 << 20

    init?(size: UInt64) {
        let slack = Int(Self.huge)
        guard let raw = mmap(nil, Int(size) + slack, Self.reserveProtection, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0),
              raw != MAP_FAILED else {
            return nil
        }
        let aligned = (UInt(bitPattern: raw) + UInt(slack) - 1) & ~(UInt(slack) - 1)
        base = UnsafeMutableRawPointer(bitPattern: aligned)!
        self.size = size
    }

    public private(set) var promotions: [(bytes: UInt64, milliseconds: UInt64, hugeBytes: UInt64)] = []

    static func anonHugeBytes(at address: UInt) -> UInt64 {
        guard let text = try? String(contentsOfFile: "/proc/self/smaps", encoding: .utf8) else { return 0 }
        let prefix = String(address, radix: 16) + "-"
        var inside = false
        for line in text.split(separator: "\n") {
            if let first = line.first, first.isHexDigit, line.contains("-") {
                if inside { break }
                inside = line.hasPrefix(prefix)
            } else if inside, line.hasPrefix("AnonHugePages:") {
                let kb = line.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first.flatMap { UInt64($0) } ?? 0
                return kb << 10
            }
        }
        return 0
    }

    private func promote(at: UnsafeMutableRawPointer, span: UInt64, fd: Int32, fileBytes: UInt64) {
        defer { close(fd) }
        let began = monotonicNanosecondsForArena()
        let slack = Int(Self.huge)
        guard let raw = mmap(nil, Int(span) + slack, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0),
              raw != MAP_FAILED else { return }
        let start = (UInt(bitPattern: raw) + UInt(slack) - 1) & ~(UInt(slack) - 1)
        let copy = UnsafeMutableRawPointer(bitPattern: start)!
        let head = Int(start - UInt(bitPattern: raw))
        if head > 0 { munmap(raw, head) }
        let tail = slack - head
        if tail > 0 { munmap(copy + Int(span), tail) }
        if Self.hugeMadvise { _ = madvise(copy, Int(span), 14 ) }
        let chunk = UInt64(64 << 20)
        let pieces = Int((fileBytes + chunk - 1) / chunk)
        let failed = Atomic<Bool>(false)
        let nextPiece = Atomic<Int>(0)
        let copyAddress = UInt(bitPattern: copy)
        DispatchQueue.concurrentPerform(iterations: min(Self.hugeThreads, max(1, pieces))) { _ in
            while true {
                let i = nextPiece.wrappingAdd(1, ordering: .relaxed).oldValue
                guard i < pieces, !failed.load(ordering: .relaxed) else { return }
                var done = UInt64(i) * chunk
                let end = min(fileBytes, done + chunk)
                while done < end {
                    let n = pread(fd, UnsafeMutableRawPointer(bitPattern: copyAddress)! + Int(done), Int(end - done), off_t(done))
                    if n < 0 && errno == EINTR { continue }
                    if n <= 0 { failed.store(true, ordering: .relaxed); return }
                    done += UInt64(n)
                }
            }
        }
        guard !failed.load(ordering: .relaxed) else { munmap(copy, Int(span)); return }
        guard mprotect(copy, Int(span), PROT_READ) == 0 else { munmap(copy, Int(span)); return }
        let moved = ckvm_mremap_fixed(copy, Int(span), at)
        guard moved == at else { munmap(copy, Int(span)); return }
        let ms = (monotonicNanosecondsForArena() &- began) / 1_000_000
        let hugeBytes = Self.anonHugeBytes(at: UInt(bitPattern: at))
        lock.withLock { promotions.append((span, ms, hugeBytes)) }
    }

    private final class HotSpan {
        let at: UInt
        let span: UInt64
        let fd: Int32
        let fileBytes: UInt64
        var promoted: [Bool]
        init(at: UInt, span: UInt64, fd: Int32, fileBytes: UInt64) {
            self.at = at; self.span = span; self.fd = fd; self.fileBytes = fileBytes
            promoted = [Bool](repeating: false, count: Int(span / SharedFileArena.huge))
        }
    }
    private var hotSpans: [HotSpan] = []
    private var promoterStarted = false
    public let hotChunks = Atomic<UInt64>(0)
    public let hotChunkFailures = Atomic<UInt64>(0)
    public let hotNanoseconds = Atomic<UInt64>(0)

    private func promoterLoop() {
        var vector: [UInt8] = []
        while true {
            usleep(Self.hugeInterval * 1000)
            let list = lock.withLock { hotSpans }
            for span in list {
                let pages = Int((span.fileBytes + 4095) / 4096)
                if vector.count < pages { vector = [UInt8](repeating: 0, count: pages) }
                let ok = vector.withUnsafeMutableBufferPointer { v in
                    mincore(UnsafeMutableRawPointer(bitPattern: span.at)!, Int(span.fileBytes + 4095) & ~4095, v.baseAddress!) == 0
                }
                guard ok else { continue }
                let pagesPerChunk = Int(Self.huge / 4096)
                for chunk in 0..<span.promoted.count where !lock.withLock({ span.promoted[chunk] }) {
                    let first = chunk * pagesPerChunk
                    guard first < pages else { break }
                    let last = min(pages, first + pagesPerChunk)
                    var resident = false
                    for i in first..<last where vector[i] & 1 != 0 { resident = true; break }
                    guard resident else { continue }
                    let began = monotonicNanosecondsForArena()
                    if promoteChunk(span, chunk) {
                        hotChunks.wrappingAdd(1, ordering: .relaxed)
                    } else {
                        hotChunkFailures.wrappingAdd(1, ordering: .relaxed)
                    }
                    lock.withLock { span.promoted[chunk] = true }
                    hotNanoseconds.wrappingAdd(monotonicNanosecondsForArena() &- began, ordering: .relaxed)
                }
            }
        }
    }

    private func promoteChunk(_ span: HotSpan, _ chunk: Int) -> Bool {
        let size = Int(Self.huge)
        guard let raw = mmap(nil, 2 * size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0),
              raw != MAP_FAILED else { return false }
        let start = (UInt(bitPattern: raw) + UInt(size) - 1) & ~(UInt(size) - 1)
        let copy = UnsafeMutableRawPointer(bitPattern: start)!
        let head = Int(start - UInt(bitPattern: raw))
        if head > 0 { munmap(raw, head) }
        if size - head > 0 { munmap(copy + size, size - head) }
        if Self.hugeMadvise { _ = madvise(copy, size, 14 ) }
        let offset = UInt64(chunk) * Self.huge
        let fileEnd = min(span.fileBytes, offset + Self.huge)
        var done = offset
        while done < fileEnd {
            let n = pread(span.fd, copy + Int(done - offset), Int(fileEnd - done), off_t(done))
            if n < 0 && errno == EINTR { continue }
            if n == 0 { break }
            if n < 0 { munmap(copy, size); return false }
            done += UInt64(n)
        }
        guard mprotect(copy, size, PROT_READ) == 0 else { munmap(copy, size); return false }
        let at = UnsafeMutableRawPointer(bitPattern: span.at + UInt(offset))!
        guard ckvm_mremap_fixed(copy, size, at) == at else { munmap(copy, size); return false }
        return true
    }

    private func noteFull() {
        guard !reportedFull else { return }
        reportedFull = true
        FileHandle.standardError.write(("swiftcode-simd: shared file arena full (\(spans.count) files, \(next >> 20) MiB): "
            + "further read-only file mappings are private\n").data(using: .utf8)!)
    }

    public var fileCount: Int { lock.withLock { spans.count } }
    public var bytesUsed: UInt64 { lock.withLock { next } }

    public func view(hostFD: Int32, offset: UInt64, size: UInt64) -> UInt64? {
        var st = stat()
        guard fstat(hostFD, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size > 0 else { return nil }
        let fileSize = UInt64(st.st_size)
        guard fileSize >= Self.minimumFileSize else { return nil }
        let key = Key(device: UInt64(st.st_dev), inode: UInt64(st.st_ino), size: Int64(st.st_size),
                      mtimeSeconds: Int(st.st_mtim.tv_sec), mtimeNanoseconds: Int(st.st_mtim.tv_nsec))
        return lock.withLock { () -> UInt64? in
            let entry: (offset: UInt64, span: UInt64)
            if let e = spans[key] {
                entry = e
            } else {
                guard spans.count < Self.maximumFiles else { noteFull(); return nil }
                let huge = Self.hugeEnabled && fileSize >= Self.hugeMinimum
                let alignment = huge ? Self.huge : Self.granule
                let span = (fileSize + alignment - 1) & ~(alignment - 1)
                if huge { next = (next + Self.huge - 1) & ~(Self.huge - 1) }
                guard next <= self.size, span + Self.granule <= self.size - next else { noteFull(); return nil }
                let hostPage = UInt64(max(sysconf(Int32(_SC_PAGESIZE)), 4096))
                let fileBytes = min((fileSize + hostPage - 1) & ~(hostPage - 1), span)
                let at = base + Int(next)
                defer { next += span + Self.granule }
                guard let p = mmap(at, Int(fileBytes), PROT_READ, MAP_SHARED | MAP_FIXED, hostFD, 0), p == at else {
                    _ = mmap(at, Int(fileBytes), Self.reserveProtection, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED, -1, 0)
                    return nil
                }
                if span > fileBytes, !Self.zeroTails {
                    let tail = mmap(at + Int(fileBytes), Int(span - fileBytes), PROT_READ,
                                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0)
                    guard tail == at + Int(fileBytes) else {
                        _ = mmap(at, Int(span), Self.reserveProtection, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED, -1, 0)
                        return nil
                    }
                }
                entry = (next, span)
                spans[key] = entry
                if huge, Self.hugeHotChunks {
                    let copyFD = dup(hostFD)
                    if copyFD >= 0 {
                        hotSpans.append(HotSpan(at: UInt(bitPattern: at), span: span, fd: copyFD, fileBytes: fileBytes))
                        if !promoterStarted {
                            promoterStarted = true
                            let thread = Thread { [self] in promoterLoop() }
                            thread.name = "swiftcode arena promoter"
                            thread.start()
                        }
                    }
                } else if huge {
                    let copyFD = dup(hostFD)
                    if copyFD >= 0 {
                        let fileBytesForCopy = fileBytes
                        let atAddress = UInt(bitPattern: at)
                        Thread.detachNewThread { [self] in
                            self.promote(at: UnsafeMutableRawPointer(bitPattern: atAddress)!, span: span, fd: copyFD, fileBytes: fileBytesForCopy)
                        }
                    }
                }
            }
            guard offset <= entry.span, size <= entry.span - offset else { return nil }
            return entry.offset + offset
        }
    }
}

private func monotonicNanosecondsForArena() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return UInt64(now.tv_sec) * 1_000_000_000 + UInt64(now.tv_nsec)
}
#endif
