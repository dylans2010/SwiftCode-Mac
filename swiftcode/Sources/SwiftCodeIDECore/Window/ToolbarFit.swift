import Foundation

public struct ToolbarFit: Equatable, Sendable {
    public var editorModesInOverflow = false
    public var schemeGlyphsOnly = false
    public var activityWidth: CGFloat?
    public init(editorModesInOverflow: Bool = false, schemeGlyphsOnly: Bool = false, activityWidth: CGFloat? = nil) {
        self.editorModesInOverflow = editorModesInOverflow
        self.schemeGlyphsOnly = schemeGlyphsOnly
        self.activityWidth = activityWidth
    }

    public static let editorModesItem = "editorModes"

    public var overflowAllowance: Set<String> { editorModesInOverflow ? [Self.editorModesItem] : [] }

    public func accepts(overflowed: [String]) -> Bool { Set(overflowed).isSubset(of: overflowAllowance) }

    public static let activityMinimum: CGFloat = 72

    public static func steps(activityNatural: CGFloat) -> [ToolbarFit] {
        var out = [ToolbarFit(), ToolbarFit(schemeGlyphsOnly: true), ToolbarFit(editorModesInOverflow: true, schemeGlyphsOnly: true)]
        var w = activityNatural
        while w > activityMinimum {
            w = max(activityMinimum, (w - max(24, activityNatural * 0.15)).rounded(.down))
            out.append(ToolbarFit(editorModesInOverflow: true, schemeGlyphsOnly: true, activityWidth: w))
        }
        return out
    }
}
