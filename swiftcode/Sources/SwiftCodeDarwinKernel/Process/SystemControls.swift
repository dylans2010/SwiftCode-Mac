import SwiftCodeDarwinABI

enum SystemControlBSD {
    static let quotactl = 165, memorystatusControl = 440, csrctl = 483, persona = 494
    static let all: Set<Int> = [quotactl, memorystatusControl, csrctl, persona]
}

extension DarwinKernel {
    func systemControlCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        func int(_ i: Int) -> Int32 { Int32(truncatingIfNeeded: a[i]) }
        switch n {
        case SystemControlBSD.memorystatusControl:
            call.set("memorystatus_control(command=\(int(0)), pid=\(int(1)), flags=\(hx(UInt32(bitPattern: int(2)))), "
                + "buffer=\(hx(a[3])), size=\(a[4]))")
            throw Failure(errno: [18, 19, 24].contains(int(0)) ? Errno.EINVAL : Errno.EPERM)
        case SystemControlBSD.quotactl:
            call.set("quotactl(\(hx(a[0])), cmd=\(hx(UInt32(bitPattern: int(1)))), id=\(int(2)))")
            throw Failure(errno: Errno.ENOTSUP)
        case SystemControlBSD.csrctl:
            call.set("csrctl(op=\(int(0)), \(hx(a[1])), size=\(a[2]))")
            switch int(0) {
            case 0: throw Failure(errno: Errno.EPERM)
            case 1:
                guard a[2] == 4 else { throw Failure(errno: Errno.EINVAL) }
                try mem.write(va: a[1], bytes: [0, 0, 0, 0])
                return .value(0)
            default: throw Failure(errno: Errno.EINVAL)
            }
        default:
            let op = int(0)
            call.set("__persona(op=\(op), flags=\(hx(a[1])), info=\(hx(a[2])), id=\(hx(a[3])), idlen=\(hx(a[4])))")
            switch op {
            case 1, 2, 3: throw Failure(errno: Errno.EPERM)
            case 4, 5, 6, 8: throw Failure(errno: Errno.ESRCH)
            case 7, 9:
                if a[4] != 0 { try mem.write(va: a[4], bytes: [UInt8](repeating: 0, count: 8)) }
                return .value(0)
            default: throw Failure(errno: Errno.EINVAL)
            }
        }
    }
}
