import Foundation

public struct AccessibilityInspectorTool {
    public static let identifier = "accessibility_inspector"

    public func run() async throws -> String {
        return "Accessibility properties for active window"
    }
}
