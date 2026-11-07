import Foundation
import SwiftCodeDisplayStream

struct XRLayerPlan: Equatable {
    static let monoSlot = 10, monoInsetSlot = 11

    struct Shown: Equatable {
        var sequence: UInt64
        var pose: SpatialPose
        var fov: XRFieldOfView
    }

    private(set) var mono: Shown?
    private(set) var eyes: [Shown?] = [nil, nil]

    mutating func show(_ view: XRView, _ s: Shown) {
        switch view {
        case .mono: mono = s
        case .left: eyes[0] = s
        case .right: eyes[1] = s
        }
    }

    func layout() -> [(slot: Int, view: XRView, shown: Shown)]? {
        let eyeSeq = max(eyes[0]?.sequence ?? 0, eyes[1]?.sequence ?? 0)
        if let m = mono, m.sequence > eyeSeq {
            return [(Self.monoSlot, .mono, m), (Self.monoSlot, .mono, m)]
        }
        var out: [(slot: Int, view: XRView, shown: Shown)] = []
        for e in 0..<2 {
            if let s = eyes[e] { out.append((e, e == 0 ? .left : .right, s)) }
            else if let m = mono { out.append((Self.monoSlot, .mono, m)) }
            else if let other = eyes[1 - e] { out.append((1 - e, e == 0 ? .right : .left, other)) }
            else { return nil }
        }
        return out
    }

    static func insetSlot(for view: XRView) -> Int {
        switch view {
        case .mono: monoInsetSlot
        case .left: 4
        case .right: 5
        }
    }
}
