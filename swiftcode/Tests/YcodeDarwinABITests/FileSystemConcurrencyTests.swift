import Foundation
import Testing
@testable import YcodeDarwinABI

@Suite struct FileSystemConcurrencyTests {
    @Test func firstLookupsOfANewProcessRaceSafely() throws {
        let tree = try TempTree()
        try tree.mkdir("runtime/System/Library")
        try tree.mkdir("data/var")
        try tree.writeFile("hostlibs/libsystem_kernel.dylib", [1, 2, 3])
        let parent = DarwinFileSystem(prefixes: [
            .init(guestPath: "/Runtime/System", hostPath: tree.host("runtime/System"), writable: false),
            .init(guestPath: "/Device/data/var", hostPath: tree.host("data/var"), writable: true),
            .init(guestPath: "/usr/lib/system/libsystem_kernel.dylib",
                  hostPath: tree.host("hostlibs/libsystem_kernel.dylib"), writable: false),
        ], console: { _, _ in })

        let ancestors = ["/Runtime", "/Device", "/Device/data"]
        let missing = ["/usr/lib/system", "/Nowhere"]

        for round in 0..<300 {
            let box = Shared(round % 2 == 0 ? parent.makeChildCopy()
                                            : DarwinFileSystem(prefixes: parent.prefixes, console: { _, _ in }))
            let failures = Counter()
            DispatchQueue.concurrentPerform(iterations: 8) { t in
                let fs = box.value
                for i in 0..<4 {
                    let path = ancestors[(t + i) % ancestors.count]
                    if (try? fs.stat(path, followSymlinks: true))?.isDirectory != true { failures.add() }
                    if (try? fs.stat(missing[(t + i) % missing.count], followSymlinks: true)) != nil { failures.add() }
                }
            }
            #expect(failures.value == 0, "round \(round)")
        }
    }
}

extension FileSystemConcurrencyTests {
    @Test func lookupsRaceSafelyWithDirectoryChanges() throws {
        let tree = try TempTree()
        for d in ["a/x", "b/x", "a/deeper/path/component/x", "b/deeper/path/component/x"] { try tree.mkdir("data/" + d) }
        let fs = Shared(DarwinFileSystem(prefixes: [.init(guestPath: "/data", hostPath: tree.host("data"), writable: true)],
                                         console: { _, _ in }))
        try fs.value.chdir("/data/b")
        let failures = Counter()
        DispatchQueue.concurrentPerform(iterations: 8) { t in
            for i in 0..<3000 {
                if t == 0 {
                    try? fs.value.chdir(i % 2 == 0 ? "/data/a/deeper/path/component" : "/data/b")
                } else if (try? fs.value.stat("x", followSymlinks: true))?.isDirectory != true {
                    failures.add()
                }
            }
        }
        #expect(failures.value == 0)
    }
}

private final class Shared<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
