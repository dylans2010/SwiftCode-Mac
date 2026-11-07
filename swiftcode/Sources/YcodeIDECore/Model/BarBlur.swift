import Foundation

public enum BarBlur {
    public static let sigma = 6.0
    public static let toolbarBandShare = 0.18
    public static let jumpBarShare = 0.085
    public static let bottomBarShare = 0.12
    public static let selectorShare = 0.2
    public static let selectorFill = 0.033

    public static func shown(content: Double, share: Double) -> Double { 1 - share * (1 - content) }
}

public enum GaussianKernel {
    public static func weights(sigma: Double) -> [Double] {
        guard sigma > 0 else { return [1] }
        let r = Int((3 * sigma).rounded(.up))
        let raw = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = raw.reduce(0, +)
        return raw.map { $0 / sum }
    }

    public static func blur(_ values: [Double], sigma: Double) -> [Double] {
        let k = weights(sigma: sigma), r = k.count / 2
        guard !values.isEmpty else { return [] }
        return values.indices.map { i in
            k.indices.reduce(0) { acc, j in acc + k[j] * values[min(values.count - 1, max(0, i + j - r))] }
        }
    }
}
