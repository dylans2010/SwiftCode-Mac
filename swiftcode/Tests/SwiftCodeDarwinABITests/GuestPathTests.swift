import Foundation
import Testing
@testable import SwiftCodeDarwinABI

@Suite struct GuestPathTests {
    static let samples: [(String, String, String)] = [
        ("/a/b", "b", "/a"), ("/a/b/", "b", "/a"), ("/a", "a", "/"), ("/", "/", "/"), ("", "", ""),
        ("a", "a", ""), ("a/b", "b", "a"), ("/a//b", "b", "/a"), ("//a", "a", "/"),
        ("/usr/lib/system/libsystem_kernel.dylib", "libsystem_kernel.dylib", "/usr/lib/system"),
        ("/private/var/mobile/", "mobile", "/private/var"), ("x/", "x", ""), ("/a/b//", "b", "/a"),
    ]

    @Test func lastComponent() {
        for (path, last, _) in Self.samples { #expect(GuestPath.lastComponent(path) == last, "\(path)") }
    }

    @Test func deletingLastComponent() {
        for (path, _, parent) in Self.samples { #expect(GuestPath.deletingLastComponent(path) == parent, "\(path)") }
    }

    #if canImport(Darwin)
    @Test func tableMatchesFoundation() {
        for (path, last, parent) in Self.samples {
            #expect((path as NSString).lastPathComponent == last, "\(path)")
            #expect((path as NSString).deletingLastPathComponent == parent, "\(path)")
        }
    }
    #endif

    @Test func hostDirectoryNames() throws {
        let tree = try TempTree()
        try tree.mkdir("d/sub")
        try tree.writeFile("d/f", [1])
        #expect(GuestPath.hostDirectoryNames(tree.host("d"))?.sorted() == ["f", "sub"])
        #expect(GuestPath.hostDirectoryNames(tree.host("missing")) == nil)
    }
}
