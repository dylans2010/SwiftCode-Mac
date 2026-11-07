#if os(Linux) && arch(arm64)
import Foundation
import Glibc
import SwiftCodeMachO

enum MacOSMode {
    nonisolated(unsafe) static var enabled = false

    static let platform: UInt32 = 1

    static func accepts(_ platform: Platform?) -> Bool {
        guard let platform else { return true }
        if enabled { return platform == .macOS }
        return platform.isSimulator
    }

    static let dyldGuestPath = "/usr/lib/dyld"

    static func environment() -> [String] {
        ["HOME=/tmp", "TMPDIR=/tmp/", "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "USER=swiftcode", "LOGNAME=swiftcode", "SHELL=/bin/sh"]
    }

    static func locateRoot(explicit: String?) -> String {
        var candidates: [String] = []
        if let explicit { candidates.append(absolutePath(explicit)) } else {
            candidates.append(absolutePath("MacUserland/out/root"))
            if let dir = executableDirectory() {
                for up in ["../..", "../../..", "../../../.."] {
                    candidates.append(absolutePath("\(dir)/\(up)/MacUserland/out/root"))
                }
            }
        }
        for c in candidates where access(c + dyldGuestPath, R_OK) == 0 { return c }
        die("no macOS userland root with \(dyldGuestPath) (tried \(candidates.joined(separator: ", "))); "
            + "run sh MacUserland/build.sh or pass --macos-root", status: 66)
    }
}
#endif
