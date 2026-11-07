public struct StillRefinement: Sendable, Equatable {
    public struct Rect: Equatable, Sendable {
        public var x: Int, y: Int, width: Int, height: Int
        public init(x: Int, y: Int, width: Int, height: Int) { (self.x, self.y, self.width, self.height) = (x, y, width, height) }
    }

    public static let stillNanoseconds: UInt64 = 200_000_000

    public let width: Int, height: Int, tile: Int
    public let tilesX: Int, tilesY: Int
    private var lossy: [Bool]
    private var lossyTiles = 0
    public private(set) var lastActivity: UInt64 = 0

    public init(width: Int, height: Int, tile: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.tile = max(1, tile)
        tilesX = (self.width + self.tile - 1) / self.tile
        tilesY = (self.height + self.tile - 1) / self.tile
        lossy = [Bool](repeating: false, count: tilesX * tilesY)
    }

    public var isEmpty: Bool { lossyTiles == 0 }

    public mutating func sentLossy(_ rects: [Rect], at time: UInt64) {
        for r in rects { mark(r, lossy: true) }
        lastActivity = max(lastActivity, time)
    }

    public mutating func sentLossless(_ rects: [Rect]) {
        for r in rects { mark(r, lossy: false) }
    }

    public mutating func screenChanged(at time: UInt64) {
        lastActivity = max(lastActivity, time)
    }

    public func isDue(at time: UInt64) -> Bool {
        lossyTiles > 0 && time >= lastActivity && time - lastActivity >= Self.stillNanoseconds
    }

    public mutating func take() -> [Rect] {
        guard lossyTiles > 0 else { return [] }
        var open: [Int: Rect] = [:]
        var out: [Rect] = []
        for ty in 0..<tilesY {
            var runs: [(Int, Int)] = []
            var tx = 0
            while tx < tilesX {
                guard lossy[ty * tilesX + tx] else { tx += 1; continue }
                let start = tx
                while tx < tilesX && lossy[ty * tilesX + tx] { tx += 1 }
                runs.append((start, tx))
            }
            var next: [Int: Rect] = [:]
            for (a, b) in runs {
                let x = a * tile, w = min(width, b * tile) - x
                let y = ty * tile, h = min(height, y + tile) - y
                if var r = open[a], r.width == w {
                    r.height += h
                    open[a] = nil
                    next[a] = r
                } else {
                    next[a] = Rect(x: x, y: y, width: w, height: h)
                }
            }
            out += open.values
            open = next
        }
        out += open.values
        lossy = [Bool](repeating: false, count: tilesX * tilesY)
        lossyTiles = 0
        return out.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    private mutating func mark(_ r: Rect, lossy value: Bool) {
        let x0 = max(0, r.x), y0 = max(0, r.y)
        let x1 = min(width, r.x + r.width), y1 = min(height, r.y + r.height)
        guard x1 > x0, y1 > y0 else { return }
        var tx0 = x0 / tile, ty0 = y0 / tile
        var tx1 = (x1 - 1) / tile, ty1 = (y1 - 1) / tile
        if !value {
            if x0 % tile != 0 { tx0 += 1 }
            if y0 % tile != 0 { ty0 += 1 }
            if x1 % tile != 0 && x1 != width { tx1 -= 1 }
            if y1 % tile != 0 && y1 != height { ty1 -= 1 }
            guard tx1 >= tx0, ty1 >= ty0 else { return }
        }
        for ty in ty0...ty1 {
            for tx in tx0...tx1 {
                let i = ty * tilesX + tx
                if lossy[i] != value {
                    lossy[i] = value
                    lossyTiles += value ? 1 : -1
                }
            }
        }
    }
}
