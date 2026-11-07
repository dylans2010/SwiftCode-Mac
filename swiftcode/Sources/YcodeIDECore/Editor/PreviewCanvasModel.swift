import Foundation
import YcodePreviews

public enum CanvasPlacement: Equatable, Sendable {
    case beside, below

    public static let narrowWidth: CGFloat = 760

    public static func placement(forWidth w: CGFloat) -> CanvasPlacement { w > 0 && w < narrowWidth ? .below : .beside }
}
public enum PreviewCanvasMode: Int, CaseIterable, Sendable {
    case live, selectable, grid, variants
    public var title: String { ["Live", "Selectable", "Grid", "Variants"][rawValue] }
    public var symbol: String { ["play.circle", "cursorarrow", "square.grid.2x2", "circle.lefthalf.filled"][rawValue] }
}
public struct PreviewDeviceMenuModel: Equatable, Sendable {
    public struct Generic: Equatable, Sendable { public var title: String; public var detail: String }
    public static let generics = [Generic(title: "iPhone", detail: "Dynamic Island"), Generic(title: "iPhone", detail: "Touch ID"),
                                  Generic(title: "iPad", detail: "11-inch"), Generic(title: "iPad", detail: "13-inch")]
    public var automatic: String = "My Mac"
    public var recent: [String] = []
    public var connected: [String] = []
    public var chosen: String?
    public init() {}

    public var rows: [String] {
        var out = ["Automatic – \(automatic)", "—", "#Recent"] + recent + ["—"]
        out += Self.generics.map { "\($0.title) \($0.detail)" }
        out += ["—", "#Devices"] + connected + ["—", "More"]
        return out
    }
}
public struct PreviewCanvasSettings: Equatable, Sendable {
    public static let names = ["Display", "Color Scheme", "Contrast", "Control Borders", "Orientation", "Dynamic Type"]
    public var on: Set<String> = []
    public init() {}
}
