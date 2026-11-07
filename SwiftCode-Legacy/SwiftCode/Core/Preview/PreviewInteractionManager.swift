import Foundation
import SwiftUI
import AppKit

@MainActor
public final class PreviewInteractionManager {
    public static let shared = PreviewInteractionManager()

    private init() {}

    public func handleTap(at location: CGPoint, in view: NSView) {
        PreviewDiagnostics.shared.addLog(category: "interaction", message: "Dispatched mouse-click interaction event at (\(Int(location.x)), \(Int(location.y)))")
        if let hitView = view.hitTest(location) {
            PreviewDiagnostics.shared.addLog(category: "interaction", message: "Event intercepted by view: \(type(of: hitView))")
        }
    }

    public func handleHover(at location: CGPoint, in view: NSView) {
        if let hitView = view.hitTest(location) {
            PreviewDiagnostics.shared.addLog(category: "interaction", message: "Hover tracked on view: \(type(of: hitView))")
        }
    }
}
