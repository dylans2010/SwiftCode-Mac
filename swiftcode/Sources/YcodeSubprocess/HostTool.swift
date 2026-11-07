import Foundation

public enum HostTool {
    public static func isInFlatpak(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !(environment["FLATPAK_ID"] ?? "").isEmpty
    }

    public static func packagedToolDirectory(executable: URL? = Bundle.main.executableURL,
                                             fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        guard let bin = executable?.resolvingSymlinksInPath().deletingLastPathComponent() else { return nil }
        let dir = bin.deletingLastPathComponent().appendingPathComponent("libexec/swiftcode-host").path
        return fileExists(dir) ? dir : nil
    }

    public static func path(_ tool: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                            toolDirectory: String? = packagedToolDirectory()) -> String {
        if isInFlatpak(environment: environment), let toolDirectory { return "\(toolDirectory)/\(tool)" }
        return "/usr/bin/\(tool)"
    }

    public static func commandOnHost(tool: String, arguments: [String],
                                     environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        guard let id = environment["FLATPAK_ID"], !id.isEmpty else { return [tool] + arguments }
        let name = (tool as NSString).lastPathComponent
        return ["flatpak", "run", "--command=\(name)", id] + arguments
    }
}
