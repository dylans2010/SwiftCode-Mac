import Foundation
import SwiftCodeDarwinABI

enum MetadataBSD {
    static let chmod = 15, chown = 16, chflags = 34, fchflags = 35, mincore = 78, fchown = 123, fchmod = 124,
               rename = 128, utimes = 138, futimes = 139, truncate = 200, lchown = 364, macSyscall = 381,
               clonefileat = 462, renameat = 465, fchmodat = 467, fchownat = 468, renameatxNp = 488,
               fclonefileat = 517, ffsctl = 245, chmodExtended = 282, fchmodExtended = 283
    static let all: Set<Int> = [chmod, chown, chflags, fchflags, mincore, fchown, fchmod, rename, utimes, futimes,
                                truncate, lchown, macSyscall, clonefileat, renameat, fchmodat, fchownat, renameatxNp,
                                fclonefileat, ffsctl, chmodExtended, fchmodExtended]
    static let kauthIDNone: UInt32 = 0xFFFF_FFFF - 100
    static let atSymlinkNoFollow: Int32 = 0x20
    static let enoPolicy: Int32 = 103
}

extension DarwinKernel {
    func metadataCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        func int(_ i: Int) -> Int32 { Int32(truncatingIfNeeded: a[i]) }
        func u32(_ i: Int) -> UInt32 { UInt32(truncatingIfNeeded: a[i]) }
        func mode(_ i: Int) -> UInt16 { UInt16(truncatingIfNeeded: a[i]) }
        let fs = fileSystem
        switch n {
        case MetadataBSD.rename, MetadataBSD.renameat, MetadataBSD.renameatxNp:
            let at = n != MetadataBSD.rename
            let from = at ? try resolveAtPath(int(0), a[1], mem) : try readPath(a[0], mem)
            let to = at ? try resolveAtPath(int(2), a[3], mem) : try readPath(a[1], mem)
            let flags = n == MetadataBSD.renameatxNp ? u32(4) : 0
            call.set("rename(\"\(from)\", \"\(to)\"\(flags != 0 ? ", flags=\(hx(flags))" : ""))")
            let renamed = Self.lockedFileIO ? false : try lock.unlocked { try fs.renameHostFiles(from, to: to, flags: flags) }
            if !renamed { try fs.rename(from, to: to, flags: flags) }
            return .value(0)

        case MetadataBSD.chmod, MetadataBSD.fchmodat:
            let at = n == MetadataBSD.fchmodat
            let path = at ? try resolveAtPath(int(0), a[1], mem) : try readPath(a[0], mem)
            let m = mode(at ? 2 : 1)
            call.set("chmod(\"\(path)\", 0o\(String(m & 0o7777, radix: 8)))")
            try fs.chmod(path, mode: m, followSymlinks: !(at && int(3) & MetadataBSD.atSymlinkNoFollow != 0))
            return .value(0)

        case MetadataBSD.chmodExtended, MetadataBSD.fchmodExtended:
            let isFD = n == MetadataBSD.fchmodExtended
            let path = isFD ? "" : try readPath(a[0], mem)
            let uid = u32(1), gid = u32(2), newMode = int(3)
            call.set((isFD ? "fchmod_extended(\(int(0)), " : "chmod_extended(\"\(path)\", ")
                + "uid=\(hx(uid)), gid=\(hx(gid)), mode=\(newMode == -1 ? "-1" : "0o" + String(newMode, radix: 8)), xsecurity=\(hx(a[4])))")
            if uid != MetadataBSD.kauthIDNone || gid != MetadataBSD.kauthIDNone {
                let u = uid == MetadataBSD.kauthIDNone ? UInt32.max : uid, g = gid == MetadataBSD.kauthIDNone ? UInt32.max : gid
                if isFD { try fs.fchown(int(0), uid: u, gid: g) } else { try fs.chown(path, uid: u, gid: g, followSymlinks: true) }
            }
            if newMode != -1 {
                let m = UInt16(truncatingIfNeeded: newMode) & 0o7777
                if isFD { try fs.fchmod(int(0), mode: m) } else { try fs.chmod(path, mode: m, followSymlinks: true) }
            }
            return .value(0)

        case MetadataBSD.ffsctl:
            call.set("ffsctl(\(int(0)), cmd=\(hx(UInt64(u32(1)))), data=\(hx(a[2])), options=\(hx(a[3])))")
            _ = try fs.fstat(int(0))
            throw fail(25)

        case MetadataBSD.fchmod:
            call.set("fchmod(\(int(0)), 0o\(String(mode(1) & 0o7777, radix: 8)))")
            try fs.fchmod(int(0), mode: mode(1))
            return .value(0)

        case MetadataBSD.chown, MetadataBSD.lchown, MetadataBSD.fchownat:
            let at = n == MetadataBSD.fchownat
            let path = at ? try resolveAtPath(int(0), a[1], mem) : try readPath(a[0], mem)
            let base = at ? 2 : 1
            call.set("chown(\"\(path)\", \(int(base)), \(int(base + 1)))")
            let follow = n == MetadataBSD.chown || (at && int(4) & MetadataBSD.atSymlinkNoFollow == 0)
            try fs.chown(path, uid: u32(base), gid: u32(base + 1), followSymlinks: follow)
            return .value(0)

        case MetadataBSD.fchown:
            call.set("fchown(\(int(0)), \(int(1)), \(int(2)))")
            try fs.fchown(int(0), uid: u32(1), gid: u32(2))
            return .value(0)

        case MetadataBSD.utimes, MetadataBSD.futimes:
            var access: DarwinTimespec?, modification: DarwinTimespec?
            if a[1] != 0 {
                let b = try mem.read(va: a[1], count: 32)
                func tv(_ o: Int) throws -> DarwinTimespec {
                    let usec = Int64(b.readLE(Int32.self, at: o + 8))
                    guard usec >= 0, usec < 1_000_000 else { throw fail(Code.EINVAL) }
                    return DarwinTimespec(sec: b.readLE(Int64.self, at: o), nsec: usec * 1000)
                }
                access = try tv(0)
                modification = try tv(16)
            }
            if n == MetadataBSD.utimes {
                let path = try readPath(a[0], mem)
                call.set("utimes(\"\(path)\", \(hx(a[1])))")
                try fs.setTimes(path, access: access, modification: modification, followSymlinks: true)
            } else {
                call.set("futimes(\(int(0)), \(hx(a[1])))")
                try fs.setTimes(int(0), access: access, modification: modification)
            }
            return .value(0)

        case MetadataBSD.truncate:
            let path = try readPath(a[0], mem)
            call.set("truncate(\"\(path)\", \(Int64(bitPattern: a[1])))")
            let length = Int64(bitPattern: a[1])
            try hostFileSystemUnlocked { try $0.truncate(path, length: length) }
            return .value(0)

        case MetadataBSD.chflags, MetadataBSD.fchflags:
            if n == MetadataBSD.chflags {
                let path = try readPath(a[0], mem)
                call.set("chflags(\"\(path)\", \(hx(u32(1))))")
                try fs.setFileFlags(.path(path, followSymlinks: true), u32(1))
            } else {
                call.set("fchflags(\(int(0)), \(hx(u32(1))))")
                try fs.setFileFlags(.descriptor(int(0)), u32(1))
            }
            return .value(0)

        case MetadataBSD.mincore:
            call.set("mincore(\(hx(a[0])), \(hx(a[1])), \(hx(a[2])))")
            let start = a[0] & ~Self.pageMask
            let pages = Int((a[0] + a[1] - start + Self.pageSize - 1) / Self.pageSize)
            guard pages <= 1 << 20 else { throw fail(Code.EINVAL) }
            if pages > 0 { try mem.write(va: a[2], bytes: [UInt8](repeating: 1, count: pages)) }
            return .value(0)

        case MetadataBSD.macSyscall:
            let policy = (try? readString(a[0], length: 64, mem)) ?? "?"
            call.set("__mac_syscall(\"\(policy)\", \(int(1)), \(hx(a[2])))")
            if tracing, let raw = try? mem.read(va: a[2], count: 64) {
                let words = (0..<8).map { raw.readLE(UInt64.self, at: 8 * $0) }
                call += " [arg " + words.map { hx($0) }.joined(separator: " ")
                for (i, w) in words.enumerated() where w > 0x1_0000_0000 && w < 0x10_0000_0000 {
                    if let text = try? readString(w, length: 256, mem), text.count >= 2,
                       text.utf8.allSatisfy({ (0x20..<0x7F).contains($0) }) {
                        call += " w\(i)=\"\(text)\""
                    } else if let bytes = try? mem.read(va: w, count: 32) {
                        call += " w\(i)->" + bytes.map { String(format: "%02x", $0) }.joined()
                    }
                }
                call += "]"
            }
            if policy == "Sandbox", int(1) == 2 { return .value(0) }
            if policy == "Sandbox", int(1) == 12 { return .value(0) }
            if policy == "Sandbox", let value = try sandboxExtensionCall(int(1), arg: a[2], mem) { return .value(value) }
            throw fail(MetadataBSD.enoPolicy)

        default:
            if n == MetadataBSD.clonefileat {
                let from = try resolveAtPath(int(0), a[1], mem)
                let to = try resolveAtPath(int(2), a[3], mem)
                let flags = u32(4)
                call.set("clonefileat(\"\(from)\", \"\(to)\", flags=\(hx(flags)))")
                if Self.lockedFileIO { try fs.clone(from, to: to, flags: flags) } else {
                    try lock.unlocked { try fs.clone(from, to: to, flags: flags) }
                }
            } else {
                let source = int(0)
                let to = try resolveAtPath(int(1), a[2], mem)
                let flags = u32(3)
                call.set("fclonefileat(\(source), \"\(to)\", flags=\(hx(flags)))")
                if Self.lockedFileIO { try fs.clone(fd: source, to: to, flags: flags) } else {
                    try lock.unlocked { try fs.clone(fd: source, to: to, flags: flags) }
                }
            }
            return .value(0)
        }
    }
}
