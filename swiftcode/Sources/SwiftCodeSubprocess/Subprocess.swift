import Foundation

public enum Subprocess {
    public struct Output: Sendable {
        public var status: Int32
        public var stdout: Data
        public var stderr: Data
        public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                           currentDirectory: URL? = nil, captureStderr: Bool = true,
                           fileID: StaticString = #fileID, line: UInt = #line) throws -> Output {
        MainThreadGuard.blockingCall("\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.prefix(3).joined(separator: " "))",
                                     fileID: fileID, line: line)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let environment { p.environment = environment }
        if let currentDirectory { p.currentDirectoryURL = currentDirectory }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = captureStderr ? err : FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        if captureStderr {
            let h = err.fileHandleForReading
            group.enter()
            Thread { errBox.data = h.readDataToEndOfFile(); group.leave() }.start()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return Output(status: p.terminationStatus, stdout: data, stderr: errBox.data)
    }
}
