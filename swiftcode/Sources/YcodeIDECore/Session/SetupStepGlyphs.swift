extension RuntimeSetupStep {
    public var glyph: String {
        switch self {
        case .target: "arrow.triangle.branch"
        case .host: "cpu"
        case .prepare: "gearshape.2"
        case .runtimes: "square.stack.3d.up"
        case .download: "square.and.arrow.down"
        case .add: "plus.circle"
        case .finish: "checkmark.circle"
        }
    }
}

extension HeadsetSetupStep {
    public var glyph: String {
        switch self {
        case .viewerHost: "server.rack"
        case .workstation: "shippingbox"
        case .headset: "eyeglasses"
        case .tracking: "hand.raised"
        case .connect: "link"
        }
    }
}
