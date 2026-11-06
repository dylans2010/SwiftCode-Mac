import Foundation

/// The DeviceConnectKit parsing/formatting helpers, ported from
/// Legacy (`SwiftCode/Views/Build/DeviceConnectKit/Helpers/`).
/// Pure string/JSON work, no processes, no UI.
public struct BuildParser {
    public struct ParsedIssue: Sendable {
        public let filePath: String?
        public let line: Int?
        public let message: String
        public let isError: Bool
    }

    public static func parseXcodebuildOutput(_ text: String) -> (errors: [ParsedIssue], warnings: [ParsedIssue]) {
        var errors: [ParsedIssue] = []
        var warnings: [ParsedIssue] = []

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(": error:") {
                if let issue = parseDiagnosticLine(line, isError: true) {
                    errors.append(issue)
                }
            } else if line.contains(": warning:") {
                if let issue = parseDiagnosticLine(line, isError: false) {
                    warnings.append(issue)
                }
            }
        }

        return (errors, warnings)
    }

    private static func parseDiagnosticLine(_ line: String, isError: Bool) -> ParsedIssue? {
        let parts = line.components(separatedBy: isError ? ": error:" : ": warning:")
        guard parts.count >= 2 else { return nil }

        let fileAndCoords = parts[0].trimmingCharacters(in: .whitespaces)
        let message = parts[1].trimmingCharacters(in: .whitespaces)

        let subParts = fileAndCoords.components(separatedBy: ":")
        if subParts.count >= 2 {
            let path = subParts[0]
            let lineNum = Int(subParts[1])
            return ParsedIssue(filePath: path, line: lineNum, message: message, isError: isError)
        }

        return ParsedIssue(filePath: nil, line: nil, message: message, isError: isError)
    }
}

public struct CommandParser {
    public static func parseJSON<T: Decodable>(_ dataString: String, as type: T.Type) -> T? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func splitLines(_ output: String) -> [String] {
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct DeviceParser {
    public static func parseXCDeviceList(_ jsonString: String) -> [ConnectedDevice] {
        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct XCDeviceItem: Decodable {
            let name: String?
            let model: String?
            let platform: String?
            let operatingSystemVersion: String?
            let identifier: String?
            let modelUTI: String?
            let isWirelesslyConnected: Bool?
            let isConnected: Bool?
            let isAvailable: Bool?
        }

        guard let items = try? JSONDecoder().decode([XCDeviceItem].self, from: data) else {
            return []
        }

        return items.compactMap { item in
            guard let id = item.identifier else { return nil }
            return ConnectedDevice(
                name: item.name ?? "Apple Device",
                model: item.model ?? "Generic",
                productType: item.modelUTI ?? "com.apple.device",
                platform: item.platform ?? "iOS",
                // `xcrun xcdevice list` reports neither a build
                // version nor an architecture: these are defaults,
                // not device-reported values.
                osVersion: item.operatingSystemVersion ?? "1.0",
                buildVersion: "Release",
                architecture: "arm64",
                udid: id,
                isConnected: item.isConnected ?? true,
                isAvailable: item.isAvailable ?? true,
                isWireless: item.isWirelesslyConnected ?? false
            )
        }
    }
}

public struct DiagnosticsFormatter {
    public static func formatEnvironmentDiagnostics(_ env: DeviceEnvironment) -> [String] {
        var diagnostics: [String] = []

        if env.xcodeVersion == nil {
            diagnostics.append("Missing: Xcode is not detected or registered in the environment. Please run 'xcode-select -s /Applications/Xcode.app' to set your path.")
        }
        if !env.hasiOSSDK {
            diagnostics.append("Missing SDK: The iOS SDK could not be verified. Ensure iOS build support is checked in your Xcode installations.")
        }
        if !env.isSigningSetup {
            diagnostics.append("Warning: Signing profiles are unverified. Builds might fail on physical devices unless codesigning is set up correctly in Ycode Accounts settings.")
        }

        if diagnostics.isEmpty {
            diagnostics.append("All checks passed. System is fully compatible with DeviceConnect deployment pipelines.")
        }

        return diagnostics
    }

    public static func formatPipelineFailure(stage: DeploymentStatus, error: String) -> String {
        return """
        Deployment failed at stage: \(stage.description)
        Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        Error Details: \(error)
        Suggested Action: Verify developer mode is active on your target device and connected securely.
        """
    }
}

public struct LogParser {
    public static func parseLogLine(_ line: String, type: DeviceLog.LogType) -> DeviceLog {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var severity: DeviceLog.Severity = .info

        let lower = trimmed.lowercased()
        if lower.contains("[error]") || lower.contains("error:") || lower.contains("fail") {
            severity = .error
        } else if lower.contains("[warning]") || lower.contains("warning:") || lower.contains("warn") {
            severity = .warning
        } else if lower.contains("[debug]") || lower.contains("debug:") {
            severity = .debug
        }

        var category = "General"
        if trimmed.hasPrefix("[") {
            if let endIdx = trimmed.firstIndex(of: "]") {
                category = String(trimmed[trimmed.index(after: trimmed.startIndex)..<endIdx])
            }
        }

        return DeviceLog(
            timestamp: Date(),
            type: type,
            severity: severity,
            message: trimmed,
            subsystem: "com.swiftcode.deviceconnect",
            category: category
        )
    }
}

public struct OutputFormatter {
    public static func stripANSIColorCodes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\x1b\\[[0-9;]*[mK]", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    public static func formatBytes(_ bytes: Double) -> String {
        let kb = bytes / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.0f KB", kb)
        }
    }
}

public struct ProcessUtilities {
    public static func findExecutable(name: String) -> URL? {
        let paths = ["/usr/bin", "/usr/local/bin", "/usr/sbin", "/bin", "/sbin", "/Library/Apple/usr/bin"]
        let fm = FileManager.default

        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    public static func cleanEnv() -> [String: String] {
        var baseEnv = ProcessInfo.processInfo.environment
        baseEnv.removeValue(forKey: "SWIFT_UPSTREAM_BUILD")
        return baseEnv
    }
}
