public enum DerivedSettings {
    public struct Inputs {
        public var targetClass: String?
        public var productType: String?
        public var platform: String?
        public var sdkPath: String?

        public init(targetClass: String?, productType: String?, platform: String?, sdkPath: String?) {
            self.targetClass = targetClass
            self.productType = productType
            self.platform = platform
            self.sdkPath = sdkPath
        }
    }

    static let testBundleTypes: Set<String> = [
        "com.apple.product-type.bundle.unit-test",
        "com.apple.product-type.bundle.ui-testing",
    ]

    public static func compute(_ s: BuildSettings, _ inputs: Inputs) -> [String: String] {
        var out: [String: String] = [:]

        if let path = inputs.sdkPath { out["SDKROOT"] = path }

        let unoptimized = s["GCC_OPTIMIZATION_LEVEL"] == "0" || s["SWIFT_OPTIMIZATION_LEVEL"] == "-Onone"
        out["IS_UNOPTIMIZED_BUILD"] = unoptimized ? "YES" : "NO"

        if MacroOperators.isTrue(s["ENABLE_PREVIEWS"]) {
            if unoptimized && !s["SWIFT_VERSION"].isEmpty {
                if s["CODE_SIGN_IDENTITY"] == "-" { out["ENABLE_HARDENED_RUNTIME"] = "NO" }
            } else {
                out["ENABLE_PREVIEWS"] = "NO"
                out["ENABLE_DEBUG_DYLIB"] = "NO"
                out["ENABLE_XOJIT_PREVIEWS"] = "NO"
            }
        }

        if inputs.targetClass == "PBXNativeTarget" {
            out["HEADER_SEARCH_PATHS"] = s["BUILT_PRODUCTS_DIR"] + "/include " + s["HEADER_SEARCH_PATHS"]
        }

        if let type = inputs.productType, testBundleTypes.contains(type) {
            let flag = "-plugin-path " + s["TOOLCHAIN_DIR"] + "/usr/lib/swift/host/plugins/testing"
            let existing = s["OTHER_SWIFT_FLAGS"]
            out["OTHER_SWIFT_FLAGS"] = existing.isEmpty ? flag : existing + " " + flag
            if let platform = inputs.platform, platform != "MacOSX", !platform.hasSuffix("Simulator") {
                out["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
            }
        }
        return out
    }
}
