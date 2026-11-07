import Foundation
import YcodeDarwinABI

final class ObjectPathIndex: @unchecked Sendable {
    struct Key: Hashable { let dev: UInt32; let ino: UInt64 }
    private let lock = RecursiveMutex(name: "object paths")
    private var paths: [Key: String] = [:]
    private var lastWalk: [UInt32: Date] = [:]
    static let limit = 1 << 20

    func note(dev: UInt32, ino: UInt64, path: String) {
        lock.lock(); defer { lock.unlock() }
        if paths.count >= Self.limit { paths.removeAll(keepingCapacity: true) }
        paths[Key(dev: dev, ino: ino)] = path
    }

    func lookup(dev: UInt32, ino: UInt64) -> String? {
        lock.lock(); defer { lock.unlock() }
        return paths[Key(dev: dev, ino: ino)]
    }

    func mayWalk(_ dev: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let last = lastWalk[dev], Date().timeIntervalSince(last) < 30 { return false }
        lastWalk[dev] = Date()
        return true
    }
}

extension DarwinSystem {
    public static let objectIndexPrewarm = getenv("SWIFTCODE_OBJECT_INDEX_PREWARM").map { String(cString: $0) != "0" } ?? true

    static let prewarmDirectories = ["System/Library/Caches/com.apple.dyld"]
    static let prewarmFiles = ["usr/lib/dyld_sim"]

    @discardableResult
    public func prewarmObjectPaths(fileSystem fs: DarwinFileSystem) -> Int {
        defer { fs.closeAll() }
        guard Self.objectIndexPrewarm else { return 0 }
        func join(_ base: String, _ rest: String) -> String { base.hasSuffix("/") ? base + rest : base + "/" + rest }
        var noted = 0
        func note(_ guestPath: String) {
            guard let st = try? fs.stat(guestPath, followSymlinks: false), !st.isDirectory,
                  objectPaths.lookup(dev: st.dev, ino: st.ino) == nil else { return }
            objectPaths.note(dev: st.dev, ino: st.ino, path: guestPath)
            noted += 1
        }
        for prefix in fs.prefixes {
            for dir in Self.prewarmDirectories {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: join(prefix.hostPath, dir)) else { continue }
                for name in names.sorted() { note(join(join(prefix.guestPath, dir), name)) }
            }
            for file in Self.prewarmFiles { note(join(prefix.guestPath, file)) }
        }
        return noted
    }
}

extension DarwinKernel {
    func noteObjectPath(dev: UInt32, ino: UInt64, path: String) {
        system.objectPaths.note(dev: dev, ino: ino, path: path)
    }

    func pathForObject(dev: UInt32, objid: UInt64) throws -> String {
        let fs = fileSystem
        var roots: [(guest: String, host: String)] = []
        var mountPoint: String?
        for prefix in fs.prefixes {
            guard let st = try? fs.stat(prefix.guestPath, followSymlinks: true), st.dev == dev, st.isDirectory else { continue }
            roots.append((prefix.guestPath, prefix.hostPath))
            if mountPoint == nil || prefix.volumeMountPoint.count < mountPoint!.count { mountPoint = prefix.volumeMountPoint }
        }
        if let root = try? fs.stat("/", followSymlinks: true), root.dev == dev, mountPoint == nil { mountPoint = "/" }
        guard let mount = mountPoint else { throw Failure(errno: Errno.EINVAL) }
        if objid == 2 { return mount }
        if let path = system.objectPaths.lookup(dev: dev, ino: objid),
           let st = try? fs.stat(path, followSymlinks: false), st.ino == objid, st.dev == dev {
            return path
        }
        for root in roots where (try? fs.stat(root.guest, followSymlinks: false).ino) == objid { return root.guest }
        guard system.objectPaths.mayWalk(dev) else { throw Failure(errno: Errno.ENOENT) }
        let walkBegan = Date()
        let index = system.objectPaths
        var found: String?
        for root in roots {
            let hostBase = root.host.hasSuffix("/") ? String(root.host.dropLast()) : root.host
            let guestBase = root.guest == "/" ? "" : root.guest
            found = Self.walkForObject(hostBase: hostBase, guestBase: guestBase, objid: objid) { ino, path in
                index.note(dev: dev, ino: ino, path: path)
            }
            if found != nil { break }
        }
        if Self.debugObjectWalks {
            FileHandle.standardError.write(Data(("swiftcode-simd: object walk: volume \(dev) object \(objid): "
                + "\(Int(Date().timeIntervalSince(walkBegan) * 1000)) ms, \(found ?? "not found")\n").utf8))
        }
        guard let path = found else { throw Failure(errno: Errno.ENOENT) }
        return path
    }

    static let debugObjectWalks = getenv("SWIFTCODE_DEBUG_OBJECT_WALKS").map { String(cString: $0) == "1" } ?? false

    static func walkForObject(hostBase: String, guestBase: String, objid: UInt64,
                              note: (UInt64, String) -> Void) -> String? {
        var stack: [(host: String, guest: String)] = [(hostBase, guestBase)]
        while let (host, guest) = stack.popLast() {
            guard let dir = opendir(host) else { continue }
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    let n = bytes.firstIndex(of: 0) ?? bytes.count
                    return String(decoding: bytes[..<n], as: UTF8.self)
                }
                if name == "." || name == ".." { continue }
                let hostPath = host + "/" + name
                let guestPath = guest + "/" + name
                var ino = UInt64(entry.pointee.d_ino)
                var isDirectory = entry.pointee.d_type == UInt8(DT_DIR)
                if entry.pointee.d_type == UInt8(DT_UNKNOWN) {
                    var st = stat()
                    guard lstat(hostPath, &st) == 0 else { continue }
                    ino = UInt64(st.st_ino)
                    isDirectory = st.st_mode & S_IFMT == S_IFDIR
                }
                note(ino, guestPath)
                if ino == objid { return guestPath }
                if isDirectory { stack.append((hostPath, guestPath)) }
            }
        }
        return nil
    }

    func fsGetPathCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let fsid = try mem.read(va: a[2], count: 8)
        let dev = fsid.readLE(UInt32.self, at: 0)
        call.set("\(n == 427 ? "fsgetpath" : "fsgetpath_ext")(buf=\(hx(a[0])), size=\(a[1]), fsid=\(hx(UInt64(dev))), objid=\(a[3])"
            + (n == 427 ? ")" : ", options=\(hx(a[4])))"))
        let path = try lock.unlocked { try pathForObject(dev: dev, objid: a[3]) }
        let bytes = Array(path.utf8) + [0]
        call += " [\(path)]"
        guard UInt64(bytes.count) <= a[1] else { throw Failure(errno: 28) }
        try mem.write(va: a[0], bytes: bytes)
        return UInt64(bytes.count)
    }

    func openByIDCall(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let fsid = try mem.read(va: a[0], count: 8)
        let dev = fsid.readLE(UInt32.self, at: 0)
        let flags = Int32(truncatingIfNeeded: a[2])
        call.set("openbyid_np(fsid=\(hx(UInt64(dev))), objid=\(a[1]), oflags=\(hx(UInt64(UInt32(bitPattern: flags)))))")
        let path = try lock.unlocked { try pathForObject(dev: dev, objid: a[1]) }
        call += " [\(path)]"
        let fd = try openUnlocked(path, flags: flags, mode: 0)
        return UInt64(UInt32(bitPattern: fd))
    }
}
