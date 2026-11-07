import Foundation
import Testing
@testable import YcodeDarwinABI

@Suite struct DirectoryEntryStatTests {
    @Test func entryStatMatchesTheFullResolution() throws {
        let tree = try TempTree()
        try tree.mkdir("data/var/dir/sub")
        try tree.writeFile("data/var/dir/file", [1, 2, 3])
        try tree.mkdir("other")
        try FileManager.default.createSymbolicLink(atPath: tree.host("data/var/dir/hostlink"), withDestinationPath: "file")
        try tree.mkdir("data/var/dir/nested")
        let fs = DarwinFileSystem(prefixes: [
            .init(guestPath: "/Device/data/var", hostPath: tree.host("data/var"), writable: true, device: 7, ownerUID: 0),
            .init(guestPath: "/Device/data/var/dir/nested", hostPath: tree.host("other"), writable: true),
        ], console: { _, _ in })
        fs.guestSymlinks["/Device/data/var/dir/glink"] = "/Device/data/var/dir/file"
        let dir = "/Device/data/var/dir"
        for name in ["file", "sub", "hostlink", "nested", "glink"] {
            let fast = try fs.statEntry(inDirectory: dir, name: name)
            let full = try fs.stat(dir + "/" + name, followSymlinks: false)
            #expect(fast == full, "\(name)")
        }
        #expect(throws: (any Error).self) { try fs.statEntry(inDirectory: dir, name: "missing") }
        #expect(try fs.statEntry(inDirectory: dir, name: "file").dev == 7)
    }
}
