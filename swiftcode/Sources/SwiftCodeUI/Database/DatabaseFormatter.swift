import Foundation

public struct DatabaseFormatter {
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func formatMB(_ sizeInMB: Double) -> String {
        if sizeInMB < 1024 {
            return String(format: "%.2f MB", sizeInMB)
        } else {
            return String(format: "%.2f GB", sizeInMB / 1024.0)
        }
    }

    public static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
