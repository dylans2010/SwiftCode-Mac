import Foundation
import Testing
@testable import SwiftCodeBuild

struct StringsCompilerHookTests {
    func tool() throws -> (dir: URL, tool: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-strings-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t = dir.appendingPathComponent("swiftcode")
        try Data("#!/bin/sh\n".utf8).write(to: t)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.path)
        return (dir, t.path)
    }

    @Test func defaultsAndSettings() throws {
        let (dir, _) = try tool()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StringsCompilerHook.choice(settings: [], environment: ["DEVELOPER_DIR": dir.path]) == .swiftcode)
        #if os(macOS)
        let dev = dir.appendingPathComponent("Developer/usr/bin")
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: dev.appendingPathComponent("xcstringstool"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dev.appendingPathComponent("xcstringstool").path)
        let env = ["DEVELOPER_DIR": dir.appendingPathComponent("Developer").path]
        #expect(StringsCompilerHook.choice(settings: [], environment: env) == .xcstringstool)
        #expect(StringsCompilerHook.choice(settings: [("SWIFTCODE_STRINGS_COMPILER", "swiftcode")], environment: env) == .swiftcode)
        #else
        #expect(StringsCompilerHook.choice(settings: [], environment: [:]) == .swiftcode)
        #endif
        #expect(StringsCompilerHook.choice(settings: [("SWIFTCODE_STRINGS_COMPILER", "xcstringstool")], environment: ["SWIFTCODE_STRINGS_COMPILER": "swiftcode"]) == .xcstringstool)
    }

    @Test func writesTheWrapperAndTheSearchPath() throws {
        let (dir, swiftcode) = try tool()
        defer { try? FileManager.default.removeItem(at: dir) }
        let w = dir.appendingPathComponent("w")
        let env = try #require(StringsCompilerHook.environment(settings: [("SWIFTCODE_STRINGS_COMPILER", "swiftcode"), ("SWIFTCODE_STRINGS_TOOL", swiftcode)],
                                                               directory: w, base: ["PATH": "/usr/bin", "__XCODE_BUILT_PRODUCTS_DIR_PATHS": "/p"]))
        #expect(env["PATH"] == "/usr/bin")
        #expect(env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] == w.path + ":/p")
        let text = try String(contentsOfFile: w.appendingPathComponent("xcstringstool").path, encoding: .utf8)
        #expect(FileManager.default.isExecutableFile(atPath: w.appendingPathComponent("xcstringstool").path))
        #expect(text.hasPrefix("#!/bin/sh\n") && text.hasSuffix("exec '\(swiftcode)' strings \"$@\"\n"))
        #expect(StringsCompilerHook.environment(settings: [("SWIFTCODE_STRINGS_COMPILER", "xcstringstool"), ("SWIFTCODE_STRINGS_TOOL", swiftcode)], directory: w, base: [:]) == nil)
        #expect(StringsCompilerHook.environment(settings: [("SWIFTCODE_STRINGS_COMPILER", "swiftcode"), ("SWIFTCODE_STRINGS_TOOL", "/no/swiftcode")], directory: w, base: [:]) == nil)
    }

    @Test func encodingOverrideOffMacOS() {
        let o = StringsCompilerHook.overrides(settings: [("SWIFTCODE_STRINGS_COMPILER", "swiftcode")], environment: [:])
        #if os(macOS)
        #expect(o.isEmpty)
        #else
        #expect(o.map(\.0) == ["STRINGS_FILE_INPUT_ENCODING"] && o.map(\.1) == ["$(InputFileTextEncoding:default=utf-8)"])
        #expect(StringsCompilerHook.overrides(settings: [("STRINGS_FILE_INPUT_ENCODING", "utf-16")], environment: [:]).isEmpty)
        #endif
    }
}
