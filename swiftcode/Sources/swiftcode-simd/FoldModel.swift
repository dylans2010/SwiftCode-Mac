import Foundation

enum FoldPosture: String, CaseIterable, Sendable {
    case closed
    case halfOpen
    case openFlat

    var angle: Int {
        switch self {
        case .closed: 0
        case .halfOpen: 90
        case .openFlat: 180
        }
    }

    init(angle: Int) {
        self = angle <= 0 ? .closed : angle >= 180 ? .openFlat : .halfOpen
    }

    var title: String {
        switch self {
        case .closed: "Closed"
        case .halfOpen: "Half Open"
        case .openFlat: "Open Flat"
        }
    }

    init?(word: String) {
        switch word.lowercased() {
        case "closed", "close", "fold", "folded": self = .closed
        case "half", "halfopen", "half-open", "book", "partiallyopen": self = .halfOpen
        case "open", "openflat", "open-flat", "flat", "unfold", "unfolded": self = .openFlat
        default: return nil
        }
    }

    static func angle(argument: String) -> Int? {
        if let p = FoldPosture(word: argument) { return p.angle }
        guard let n = Int(argument.hasSuffix("°") ? String(argument.dropLast()) : argument), (0...180).contains(n) else { return nil }
        return n
    }
}

enum DeviceMotionOrientation: UInt32, CaseIterable, Sendable {
    case ambiguous = 0, portrait = 1, landscapeLeft = 3, landscapeRight = 4, faceUp = 5, faceDown = 6

    var name: String {
        switch self {
        case .ambiguous: "ambiguous"
        case .portrait: "portrait"
        case .landscapeLeft: "landscape-left"
        case .landscapeRight: "landscape-right"
        case .faceUp: "faceup"
        case .faceDown: "facedown"
        }
    }

    init?(name: String) {
        let n = name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        guard let o = Self.allCases.first(where: { $0.name.replacingOccurrences(of: "-", with: "") == n }) else { return nil }
        self = o
    }

    var rotatedLeft: DeviceMotionOrientation {
        switch self {
        case .portrait: .landscapeLeft
        case .landscapeLeft: .landscapeRight
        default: .portrait
        }
    }

    var rotatedRight: DeviceMotionOrientation {
        switch self {
        case .portrait: .landscapeRight
        case .landscapeRight: .landscapeLeft
        default: .portrait
        }
    }

    var clockwiseTurn: Int {
        switch self {
        case .landscapeLeft: 270
        case .landscapeRight: 90
        default: 0
        }
    }
}

struct FoldModel: Equatable, Sendable {
    static let openingSwapAngle = 85
    static let closingSwapAngle = 84
    static let sweepStepMilliseconds = 30
    static let sweepMilliseconds = 500

    var angle = 0
    var innerActive = false
    var orientation = DeviceMotionOrientation.portrait

    var posture: FoldPosture { FoldPosture(angle: angle) }

    static func sweep(from: Int, to: Int, instant: Bool = false) -> [Int] {
        let target = min(180, max(0, to))
        if instant || from == target { return [target] }
        let steps = max(1, Int((Double(sweepMilliseconds) / Double(sweepStepMilliseconds)).rounded()))
        var out: [Int] = []
        for i in 1...steps {
            let a = Int((Double(from) + Double(target - from) * Double(i) / Double(steps)).rounded())
            if a != from, out.last != a { out.append(a) }
        }
        if out.last != target { out.append(target) }
        return out
    }

    func innerActive(after target: Int) -> Bool {
        if target > angle { return innerActive || target >= Self.openingSwapAngle }
        if target < angle { return innerActive && target > Self.closingSwapAngle }
        return innerActive
    }

    mutating func moved(to target: Int) {
        let t = min(180, max(0, target))
        innerActive = innerActive(after: t)
        angle = t
    }

    var record: String { "angle \(angle) inner \(innerActive ? 1 : 0) orientation \(orientation.rawValue)\n" }

    init() {}

    init?(record: String) {
        let w = record.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        func value(_ key: String) -> Int? { w.firstIndex(of: key).flatMap { $0 + 1 < w.count ? Int(w[$0 + 1]) : nil } }
        guard let a = value("angle"), (0...180).contains(a), let i = value("inner") else { return nil }
        angle = a
        innerActive = i != 0
        orientation = value("orientation").flatMap { DeviceMotionOrientation(rawValue: UInt32($0)) } ?? .portrait
    }

    var summary: String {
        "angle \(angle)° (\(posture.title)), \(innerActive ? "inner" : "cover") side, \(orientation.name)"
    }
}

enum PanelPicture {
    static func uprightRotation(mountRotation: Int) -> Int { mountRotation == 0 ? 0 : (360 - mountRotation) % 360 }

    static func viewRotation(mountRotation: Int, orientation: DeviceMotionOrientation) -> Int {
        (uprightRotation(mountRotation: mountRotation) + 360 - orientation.clockwiseTurn) % 360
    }

    static func isBlack(_ base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
        guard width > 0, height > 0 else { return true }
        let n = 32
        for j in 0..<n {
            let y = height == 1 ? 0 : j * (height - 1) / (n - 1)
            for i in 0..<n {
                let x = width == 1 ? 0 : i * (width - 1) / (n - 1)
                let p = base + y * bytesPerRow + x * 4
                if p.load(fromByteOffset: 0, as: UInt8.self) != 0 || p.load(fromByteOffset: 1, as: UInt8.self) != 0
                    || p.load(fromByteOffset: 2, as: UInt8.self) != 0 { return false }
            }
        }
        return true
    }

    static func rotate(rgba: [UInt8], width: Int, height: Int, degrees: Int) -> (pixels: [UInt8], width: Int, height: Int) {
        let d = ((degrees % 360) + 360) % 360
        guard d != 0, rgba.count >= width * height * 4 else { return (rgba, width, height) }
        let (w2, h2) = d == 180 ? (width, height) : (height, width)
        var out = [UInt8](repeating: 0, count: w2 * h2 * 4)
        rgba.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                let s = src.bindMemory(to: UInt32.self), o = dst.bindMemory(to: UInt32.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let (nx, ny): (Int, Int)
                        switch d {
                        case 90: (nx, ny) = (height - 1 - y, x)
                        case 180: (nx, ny) = (width - 1 - x, height - 1 - y)
                        default: (nx, ny) = (y, width - 1 - x)
                        }
                        o[ny * w2 + nx] = s[y * width + x]
                    }
                }
            }
        }
        return (out, w2, h2)
    }
}

struct PanelInfo: Equatable, Sendable {
    let name: String
    let slot: Int
    let width: Int, height: Int
    let scale: Double
    let mountRotation: Int
    var touchDisplay: UInt32 { slot == 0 ? 0 : 1 }
}

extension DeviceType {
    var panels: [PanelInfo] {
        var p = [PanelInfo(name: "LCD", slot: 0, width: screen.width, height: screen.height, scale: screen.scale, mountRotation: 0)]
        if let s = publishedSecondDisplay {
            p.append(PanelInfo(name: s.name, slot: 1, width: s.width, height: s.height, scale: Double(s.scale), mountRotation: s.mountRotation))
        }
        return p
    }
}

func activePanel(_ panels: [PanelInfo], model: FoldModel?, records: [FrameRecord?], black: [Bool?] = []) -> PanelInfo {
    guard panels.count > 1, let model else { return panels[0] }
    let predicted = model.innerActive ? 1 : 0
    let other = 1 - predicted
    func off(_ i: Int) -> Bool { i < records.count && records[i]?.backlight == 0 }
    if off(predicted) && !off(other) { return panels[other] }
    func dark(_ i: Int) -> Bool? { i < black.count ? black[i] : nil }
    if dark(predicted) == true && dark(other) == false { return panels[other] }
    return panels[predicted]
}
