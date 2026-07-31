import SwiftUI
import Observation

/// Preference configurations and viewport metrics for the Visual UI workspace
@Observable
public final class VisualUISettings {
    public static let shared = VisualUISettings()

    public var showGrid: Bool = true
    public var gridSize: Double = 16.0
    public var magneticSnapEnabled: Bool = true
    public var snapTolerance: Double = 8.0
    public var showSafeAreas: Bool = true
    public var smartGuidesEnabled: Bool = true
    public var selectedDevice: String = "iPhone 16 Pro"
    public var isDarkMode: Bool = false
    public var localizationCode: String = "en"
    public var dynamicTypeSize: String = "Medium"

    public var zoomLevels: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    public private(set) var diagnosticsLogs: [String] = []

    private init() {
        addLog("Visual UI Builder settings initialized.")
    }

    public func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        diagnosticsLogs.append("[\(timestamp)] \(message)")

        // Keep last 100 entries
        if diagnosticsLogs.count > 100 {
            diagnosticsLogs.removeFirst()
        }
    }

    public func clearLogs() {
        diagnosticsLogs.removeAll()
    }
}
