import Foundation

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
