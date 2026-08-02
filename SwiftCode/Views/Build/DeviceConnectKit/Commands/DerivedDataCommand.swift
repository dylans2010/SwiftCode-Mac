import Foundation
import OSLog

public struct DerivedDataCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DerivedDataCommand")

    public init() {}

    public func getDerivedDataSize() async throws -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let derivedDataURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")

        var totalSize: Double = 0
        if let enumerator = FileManager.default.enumerator(at: derivedDataURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    totalSize += Double(size)
                }
            }
        }
        return totalSize
    }

    public func clearDerivedData() async throws -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let derivedDataURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")

        Self.logger.info("Clearing DerivedData at \(derivedDataURL.path)...")
        do {
            if FileManager.default.fileExists(atPath: derivedDataURL.path) {
                try FileManager.default.removeItem(at: derivedDataURL)
                try FileManager.default.createDirectory(at: derivedDataURL, withIntermediateDirectories: true)
            }
            return true
        } catch {
            Self.logger.error("Failed to clear DerivedData: \(error.localizedDescription)")
            return false
        }
    }
}
