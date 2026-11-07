public enum TouchPacing {
    public static let minimumMoveInterval: UInt64 = 8_000_000
    public static let restInterval: UInt64 = 16_666_667
    public static let maximumAgeMicroseconds: UInt32 = 5_000_000

    public static func isSuperseded(moveOnly: Bool, received: UInt64, next: (moveOnly: Bool, received: UInt64)?) -> Bool {
        guard moveOnly, let next, next.moveOnly, next.received >= received else { return false }
        return next.received - received < minimumMoveInterval
    }

    public static func ageMicroseconds(received: UInt64, now: UInt64) -> UInt32 {
        guard now > received else { return 0 }
        return UInt32(min(UInt64(maximumAgeMicroseconds), (now - received) / 1000))
    }

    public static func restReportDue(anyDown: Bool, lastTouchSent: UInt64, now: UInt64) -> Bool {
        anyDown && now >= lastTouchSent && now - lastTouchSent >= restInterval
    }

    public static func restPosition(x: Double, y: Double, count: Int, pixelWidth: Double) -> (x: Double, y: Double) {
        guard count % 2 == 1, pixelWidth > 0 else { return (x, y) }
        let step = 1 / pixelWidth
        return (x < 0.5 ? x + step : x - step, y)
    }
}
