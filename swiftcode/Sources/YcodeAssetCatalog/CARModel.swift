import Foundation

public enum CARAttribute: UInt32, CaseIterable, Sendable, Comparable {
    case look = 0, element, part, size, direction, placeholder, value, appearance, dimension1, dimension2
    case state, layer, scale, localization, presentationState, idiom, subtype, identifier, previousValue, previousState
    case sizeClassHorizontal, sizeClassVertical, memoryClass, graphicsClass, displayGamut, deploymentTarget, glyphWeight, glyphSize

    public static func < (a: CARAttribute, b: CARAttribute) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .look: "look"
        case .element: "element"
        case .part: "part"
        case .size: "size"
        case .direction: "direction"
        case .placeholder: "placeholder"
        case .value: "value"
        case .appearance: "appearance"
        case .dimension1: "dimension1"
        case .dimension2: "dimension2"
        case .state: "state"
        case .layer: "layer"
        case .scale: "scale"
        case .localization: "localization"
        case .presentationState: "presentation state"
        case .idiom: "idiom"
        case .subtype: "subtype"
        case .identifier: "identifier"
        case .previousValue: "previous value"
        case .previousState: "previous state"
        case .sizeClassHorizontal: "size class horizontal"
        case .sizeClassVertical: "size class vertical"
        case .memoryClass: "memory class"
        case .graphicsClass: "graphics class"
        case .displayGamut: "display gamut"
        case .deploymentTarget: "deployment target"
        case .glyphWeight: "glyph weight"
        case .glyphSize: "glyph size"
        }
    }
}

public enum CARIdiom: UInt16, CaseIterable, Sendable {
    case universal = 0, phone, pad, tv, car, watch, marketing, mac, vision

    public init?(catalogName: String) {
        switch catalogName {
        case "universal": self = .universal
        case "iphone": self = .phone
        case "ipad": self = .pad
        case "tv": self = .tv
        case "car": self = .car
        case "watch": self = .watch
        case "ios-marketing", "watch-marketing", "marketing": self = .marketing
        case "mac": self = .mac
        case "vision": self = .vision
        default: return nil
        }
    }

    public var name: String { ["universal", "phone", "pad", "tv", "car", "watch", "marketing", "mac", "vision"][Int(rawValue)] }
}

public enum CARPart {
    public static let image: UInt16 = 181
    public static let color: UInt16 = 217
    public static let multisizeImage: UInt16 = 218
    public static let iconImage: UInt16 = 220
    public static let iconImageStack: UInt16 = 245
    public static let iconGroup: UInt16 = 246
    public static let namedGradient: UInt16 = 247

    public static func name(_ p: UInt16) -> String {
        switch p {
        case image: "Image"
        case color: "Color"
        case multisizeImage: "MultiSized Image"
        case iconImage: "Icon Image"
        case iconImageStack: "IconImageStack"
        case iconGroup: "IconGroup"
        case namedGradient: "Named Gradient"
        default: "part \(p)"
        }
    }
}

public let carCatalogElement: UInt16 = 85

public enum CARAppearance: CaseIterable, Sendable, Hashable {
    case any, dark, light, tinted
}

public enum CARPlatform: String, CaseIterable, Sendable {
    case iOS, macOS, watchOS, tvOS, visionOS

    public init?(platformName p: String) {
        switch p {
        case "iphoneos", "iphonesimulator", "ios": self = .iOS
        case "macosx", "macos": self = .macOS
        case "watchos", "watchsimulator": self = .watchOS
        case "appletvos", "appletvsimulator", "tvos": self = .tvOS
        case "xros", "xrsimulator", "visionos": self = .visionOS
        default: return nil
        }
    }

    public var keySemantics: UInt32 { self == .macOS ? 1 : 2 }

    public var keyFormat: [CARAttribute] {
        self == .macOS ? [.appearance, .localization, .element, .part, .size, .identifier, .dimension2, .layer, .scale]
            : [.appearance, .localization, .scale, .idiom, .subtype, .dimension2, .identifier, .element, .part]
    }

    public var metadataPlatform: String {
        switch self {
        case .iOS: "ios"
        case .macOS: "macosx"
        case .watchOS: "watch"
        case .tvOS: "atv"
        case .visionOS: "xros"
        }
    }

    public func appearanceName(_ a: CARAppearance) -> String {
        switch (self, a) {
        case (.macOS, .any): "NSAppearanceNameSystem"
        case (.macOS, .dark): "NSAppearanceNameDarkAqua"
        case (.macOS, .light): "NSAppearanceNameAqua"
        case (_, .any): "UIAppearanceAny"
        case (_, .dark): "UIAppearanceDark"
        case (_, .light): "UIAppearanceLight"
        case (_, .tinted): "ISAppearanceTintable"
        }
    }

    public func appearanceNumber(_ a: CARAppearance) -> UInt16 {
        switch (self, a) {
        case (_, .any): 0
        case (_, .dark): 1
        case (.macOS, .light): 8
        case (_, .light): 4
        case (_, .tinted): 10
        }
    }

    public var celmVersion: UInt32 { self == .macOS ? 1 : 3 }
}

public struct CARColor: Equatable, Sendable {
    public var colorSpace: UInt8
    public var components: [Double]

    public init(colorSpace: UInt8, components: [Double]) {
        self.colorSpace = colorSpace
        self.components = components
    }

    public static func space(named n: String) -> UInt8? {
        switch n {
        case "srgb": 1
        case "gray-gamma-22", "gray": 2
        case "display-p3": 3
        case "extended-srgb": 4
        case "extended-linear-srgb": 5
        case "extended-gray": 6
        default: nil
        }
    }

    public static func spaceName(_ s: UInt8) -> String {
        ["generic", "srgb", "gray-gamma-22", "display-p3", "extended-srgb", "extended-linear-srgb", "extended-gray"][min(Int(s), 6)]
    }
}

public struct CARMultisizeEntry: Equatable, Sendable {
    public var width: UInt32
    public var height: UInt32
    public var index: UInt16
    public init(width: UInt32, height: UInt32, index: UInt16) {
        self.width = width
        self.height = height
        self.index = index
    }
}

public enum CARCompression: String, Sendable, CaseIterable {
    case none
    case lzfse
}

public enum CARContent: Equatable, Sendable {
    case image(Bitmap)
    case iconImage(Bitmap)
    case color(CARColor)
    case multisize([CARMultisizeEntry])

    public var part: UInt16 {
        switch self {
        case .image: CARPart.image
        case .iconImage: CARPart.iconImage
        case .color: CARPart.color
        case .multisize: CARPart.multisizeImage
        }
    }

    public var layout: UInt16 {
        switch self {
        case .image, .iconImage: 12
        case .color: 1009
        case .multisize: 1010
        }
    }
}

public struct CARRendition: Equatable, Sendable {
    public var name: String
    public var attributes: [CARAttribute: UInt16]
    public var renditionName: String
    public var content: CARContent
    public var flags: UInt32

    public init(name: String, attributes: [CARAttribute: UInt16] = [:], renditionName: String, content: CARContent, flags: UInt32 = 0) {
        self.name = name
        self.attributes = attributes
        self.renditionName = renditionName
        self.content = content
        self.flags = flags
    }
}
