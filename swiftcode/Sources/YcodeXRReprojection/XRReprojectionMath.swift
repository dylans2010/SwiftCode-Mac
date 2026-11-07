import Foundation
import YcodeDisplayStream

public struct XRMatrix4: Equatable, Sendable {
    public var m: [Double]

    public init(_ m: [Double]) { precondition(m.count == 16); self.m = m }

    public static let identity = XRMatrix4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    public init(rows r: [[Double]]) {
        var m = [Double](repeating: 0, count: 16)
        for row in 0..<4 { for c in 0..<4 { m[c * 4 + row] = r[row][c] } }
        self.init(m)
    }

    public subscript(row: Int, column: Int) -> Double {
        get { m[column * 4 + row] }
        set { m[column * 4 + row] = newValue }
    }

    public static func * (a: XRMatrix4, b: XRMatrix4) -> XRMatrix4 {
        var out = [Double](repeating: 0, count: 16)
        for c in 0..<4 {
            for r in 0..<4 {
                var s = 0.0
                for k in 0..<4 { s += a.m[k * 4 + r] * b.m[c * 4 + k] }
                out[c * 4 + r] = s
            }
        }
        return XRMatrix4(out)
    }

    public func apply(_ v: (Double, Double, Double, Double)) -> (x: Double, y: Double, z: Double, w: Double) {
        let p = [v.0, v.1, v.2, v.3]
        var o = [0.0, 0, 0, 0]
        for r in 0..<4 { for k in 0..<4 { o[r] += m[k * 4 + r] * p[k] } }
        return (o[0], o[1], o[2], o[3])
    }

    public var floats: [Float] { m.map(Float.init) }

    public init(pose p: SpatialPose) {
        let r = p.rotation.normalized.rows
        self.init(rows: [[r[0][0], r[0][1], r[0][2], p.position.x],
                         [r[1][0], r[1][1], r[1][2], p.position.y],
                         [r[2][0], r[2][1], r[2][2], p.position.z],
                         [0, 0, 0, 1]])
    }

    public init(view p: SpatialPose) {
        let r = p.rotation.normalized.rows
        let t = p.position
        let tx = -(r[0][0] * t.x + r[1][0] * t.y + r[2][0] * t.z)
        let ty = -(r[0][1] * t.x + r[1][1] * t.y + r[2][1] * t.z)
        let tz = -(r[0][2] * t.x + r[1][2] * t.y + r[2][2] * t.z)
        self.init(rows: [[r[0][0], r[1][0], r[2][0], tx],
                         [r[0][1], r[1][1], r[2][1], ty],
                         [r[0][2], r[1][2], r[2][2], tz],
                         [0, 0, 0, 1]])
    }

    public static func projection(_ fov: XRFieldOfView, near: Double) -> XRMatrix4 {
        let t = fov.tangents
        let (l, r, u, d) = (t.left, t.right, t.up, t.down)
        return XRMatrix4(rows: [[2 / (r - l), 0, (r + l) / (r - l), 0],
                                [0, -2 / (u - d), -(u + d) / (u - d), 0],
                                [0, 0, 0, near],
                                [0, 0, -1, 0]])
    }
}

public struct XRViewGeometry: Equatable, Sendable {
    public var toStage: XRMatrix4
    public var fov: XRFieldOfView
    public var near: Double

    public init(toStage: XRMatrix4, fov: XRFieldOfView, near: Double = 0.1) { (self.toStage, self.fov, self.near) = (toStage, fov, near) }
    public init(pose: SpatialPose, fov: XRFieldOfView, near: Double = 0.1) { self.init(toStage: XRMatrix4(pose: pose), fov: fov, near: near) }

    public var fromStage: XRMatrix4 { XRReprojection.inverse(toStage) }

    public func point(u: Double, v: Double, q: UInt16) -> (Double, Double, Double, Double) {
        let t = fov.tangents
        return (t.left + u * (t.right - t.left), t.up - v * (t.up - t.down), -1, Double(q) / 65535 / near)
    }
}

public enum XRReprojection {
    public static func matrix(from source: XRViewGeometry, to destination: XRViewGeometry) -> XRMatrix4 {
        XRMatrix4.projection(destination.fov, near: destination.near) * destination.fromStage * source.toStage
    }

    public static func reproject(u: Double, v: Double, q: UInt16, from source: XRViewGeometry,
                                 to destination: XRViewGeometry) -> (u: Double, v: Double, depth: Double)? {
        let c = matrix(from: source, to: destination).apply(source.point(u: u, v: v, q: q))
        guard c.w > 1e-12 else { return nil }
        return ((c.x / c.w + 1) / 2, (c.y / c.w + 1) / 2, c.z / c.w)
    }

    public static func eyes(head: SpatialPose, ipd: Double) -> (left: SpatialPose, right: SpatialPose) {
        let off = head.rotation.rotate(SpatialVector(ipd / 2, 0, 0))
        return (SpatialPose(position: head.position - off, rotation: head.rotation),
                SpatialPose(position: head.position + off, rotation: head.rotation))
    }

    public static func inverse(_ a: XRMatrix4) -> XRMatrix4 {
        var m = (0..<4).map { r in (0..<4).map { c in a[r, c] } + (0..<4).map { $0 == r ? 1.0 : 0.0 } }
        for col in 0..<4 {
            var pivot = col
            for r in col..<4 where abs(m[r][col]) > abs(m[pivot][col]) { pivot = r }
            m.swapAt(col, pivot)
            let p = m[col][col]
            guard abs(p) > 1e-15 else { return .identity }
            for k in 0..<8 { m[col][k] /= p }
            for r in 0..<4 where r != col {
                let f = m[r][col]
                if f != 0 { for k in 0..<8 { m[r][k] -= f * m[col][k] } }
            }
        }
        return XRMatrix4(rows: (0..<4).map { r in Array(m[r][4..<8]) })
    }
}

public enum XRCubeFace: Int, CaseIterable, Sendable {
    case posX, negX, posY, negY, posZ, negZ

    public static let fov = XRFieldOfView(tangentLeft: -1, right: 1, up: 1, down: -1)

    public var basis: (x: SpatialVector, y: SpatialVector, z: SpatialVector) {
        let (major, s, t): (SpatialVector, SpatialVector, SpatialVector)
        switch self {
        case .posX: (major, s, t) = (SpatialVector(1, 0, 0), SpatialVector(0, 0, -1), SpatialVector(0, -1, 0))
        case .negX: (major, s, t) = (SpatialVector(-1, 0, 0), SpatialVector(0, 0, 1), SpatialVector(0, -1, 0))
        case .posY: (major, s, t) = (SpatialVector(0, 1, 0), SpatialVector(1, 0, 0), SpatialVector(0, 0, 1))
        case .negY: (major, s, t) = (SpatialVector(0, -1, 0), SpatialVector(1, 0, 0), SpatialVector(0, 0, -1))
        case .posZ: (major, s, t) = (SpatialVector(0, 0, 1), SpatialVector(1, 0, 0), SpatialVector(0, -1, 0))
        case .negZ: (major, s, t) = (SpatialVector(0, 0, -1), SpatialVector(-1, 0, 0), SpatialVector(0, -1, 0))
        }
        return (s, -t, -major)
    }

    private static func flip(_ v: SpatialVector, _ mirrored: Bool) -> SpatialVector { mirrored ? SpatialVector(v.x, v.y, -v.z) : v }

    public func geometry(centre: SpatialVector, orientation: SpatialQuaternion = .identity, near: Double = 0.1, mirrored: Bool = false) -> XRViewGeometry {
        let b = basis
        let (x, y, z) = (orientation.rotate(Self.flip(b.x, mirrored)), orientation.rotate(Self.flip(b.y, mirrored)), orientation.rotate(Self.flip(b.z, mirrored)))
        let m = XRMatrix4(rows: [[x.x, y.x, z.x, centre.x], [x.y, y.y, z.y, centre.y], [x.z, y.z, z.z, centre.z], [0, 0, 0, 1]])
        return XRViewGeometry(toStage: m, fov: Self.fov, near: near)
    }

    public func axis(orientation: SpatialQuaternion = .identity, mirrored: Bool = false) -> SpatialVector { orientation.rotate(-Self.flip(basis.z, mirrored)) }

    public static func lookup(_ d: SpatialVector) -> (face: XRCubeFace, u: Double, v: Double) {
        let ax = abs(d.x), ay = abs(d.y), az = abs(d.z)
        let (face, sc, tc, ma): (XRCubeFace, Double, Double, Double)
        if ax >= ay && ax >= az {
            (face, sc, tc, ma) = d.x >= 0 ? (.posX, -d.z, -d.y, ax) : (.negX, d.z, -d.y, ax)
        } else if ay >= az {
            (face, sc, tc, ma) = d.y >= 0 ? (.posY, d.x, d.z, ay) : (.negY, d.x, -d.z, ay)
        } else {
            (face, sc, tc, ma) = d.z >= 0 ? (.posZ, d.x, -d.y, az) : (.negZ, -d.x, -d.y, az)
        }
        return (face, (sc / ma + 1) / 2, (tc / ma + 1) / 2)
    }
}

public func xrVisibleFaces(forward: SpatialVector, fov: XRFieldOfView, orientation: SpatialQuaternion = .identity, mirrored: Bool = false) -> UInt32 {
    let t = fov.tangents
    let half = atan((max(abs(t.left), abs(t.right)) * max(abs(t.left), abs(t.right)) + max(abs(t.up), abs(t.down)) * max(abs(t.up), abs(t.down))).squareRoot())
    let limit = half + atan(2.0.squareRoot()) + 0.05
    var mask: UInt32 = 0
    for f in XRCubeFace.allCases {
        let c = max(-1, min(1, f.axis(orientation: orientation, mirrored: mirrored).dot(forward.normalized)))
        if acos(c) < limit { mask |= 1 << UInt32(f.rawValue) }
    }
    return mask
}
