import SwiftUI
import Observation

/// Supported Apple target frameworks in Visual UI Builder
public enum VisualUIFramework: String, Codable, CaseIterable, Sendable, Identifiable {
    case swiftUI = "SwiftUI"
    case appKit = "AppKit"
    case uiKit = "UIKit"
    case visionOS = "visionOS"
    case widgetKit = "WidgetKit"
    case watchOS = "watchOS"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .swiftUI: return "swift"
        case .appKit: return "macpro.gen3"
        case .uiKit: return "iphone"
        case .visionOS: return "visionpro"
        case .widgetKit: return "square.grid.2x2"
        case .watchOS: return "applewatch"
        }
    }
}

/// Supported visual elements in Component Library
public enum VisualComponentType: String, Codable, CaseIterable, Sendable {
    // Basic Layout/Structural
    case vStack = "VStack"
    case hStack = "HStack"
    case zStack = "ZStack"
    case group = "Group"
    case form = "Form"
    case list = "List"
    case scrollView = "ScrollView"
    case grid = "Grid"
    case lazyVGrid = "LazyVGrid"
    case lazyHGrid = "LazyHGrid"
    case navigationStack = "NavigationStack"
    case navigationSplitView = "NavigationSplitView"
    case tabView = "TabView"

    // Basic Controls/Leaf Views
    case text = "Text"
    case button = "Button"
    case label = "Label"
    case image = "Image"
    case asyncImage = "AsyncImage"
    case toggle = "Toggle"
    case picker = "Picker"
    case slider = "Slider"
    case stepper = "Stepper"
    case progressView = "ProgressView"
    case textField = "TextField"
    case secureField = "SecureField"
    case divider = "Divider"
    case spacer = "Spacer"
    case groupBox = "GroupBox"

    // Advanced Native Views
    case canvas = "Canvas"
    case charts = "Charts"
    case map = "Map"
    case videoPlayer = "VideoPlayer"
    case webView = "WebView"
    case sfSymbol = "SF Symbol"

    public var systemIcon: String {
        switch self {
        case .vStack: return "arrow.down.to.line"
        case .hStack: return "arrow.right.to.line"
        case .zStack: return "square.stack.3d.down.right"
        case .group: return "square.dashed"
        case .form: return "doc.text"
        case .list: return "list.bullet"
        case .scrollView: return "scroll"
        case .grid: return "grid"
        case .lazyVGrid: return "grid.circle"
        case .lazyHGrid: return "grid.circle.fill"
        case .navigationStack: return "list.bullet.indent"
        case .navigationSplitView: return "sidebar.left"
        case .tabView: return "square.grid.3x1.below.line"
        case .text: return "text.alignleft"
        case .button: return "hand.point.up.left.fill"
        case .label: return "tag"
        case .image: return "photo"
        case .asyncImage: return "arrow.clockwise.icloud"
        case .toggle: return "switch.2"
        case .picker: return "filemenu.and.selection"
        case .slider: return "slider.horizontal.3"
        case .stepper: return "plusminus"
        case .progressView: return "circle.dotted"
        case .textField: return "character.cursor.ibackground"
        case .secureField: return "key"
        case .divider: return "minus"
        case .spacer: return "arrow.up.and.down.and.arrow.left.and.right"
        case .groupBox: return "square.grid.2x1"
        case .canvas: return "paintbrush"
        case .charts: return "chart.bar"
        case .map: return "map"
        case .videoPlayer: return "play.tv"
        case .webView: return "globe"
        case .sfSymbol: return "sparkles"
        }
    }
}

/// Serializable design node representing components in the layout canvas.
@Observable
public final class VisualComponentNode: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var type: VisualComponentType
    public var name: String
    public var children: [VisualComponentNode]
    public var properties: [String: String] // Properties e.g. textValue, sfSymbolName, padding, cornerRadius, customColor
    public var isLocked: Bool
    public var isHidden: Bool

    public init(
        id: UUID = UUID(),
        type: VisualComponentType,
        name: String? = nil,
        children: [VisualComponentNode] = [],
        properties: [String: String] = [:],
        isLocked: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.type = type
        self.name = name ?? type.rawValue
        self.children = children
        self.properties = properties
        self.isLocked = isLocked
        self.isHidden = isHidden
    }

    // Codable support for Observable class
    enum CodingKeys: CodingKey {
        case id, type, name, children, properties, isLocked, isHidden
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(VisualComponentType.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        children = try container.decode([VisualComponentNode].self, forKey: .children)
        properties = try container.decode([String: String].self, forKey: .properties)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(children, forKey: .children)
        try container.encode(properties, forKey: .properties)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isHidden, forKey: .isHidden)
    }

    public static func == (lhs: VisualComponentNode, rhs: VisualComponentNode) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Duplicate node recursively
    public func duplicated() -> VisualComponentNode {
        VisualComponentNode(
            id: UUID(),
            type: type,
            name: "\(name) Copy",
            children: children.map { $0.duplicated() },
            properties: properties,
            isLocked: isLocked,
            isHidden: isHidden
        )
    }
}

/// Represents an Artboard / Canvas screen target with customizable device frame
@Observable
public final class VisualUIArtboard: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var deviceFrame: String // iPhone 16 Pro, iPad Pro, Apple Vision Pro, etc.
    public var rootNode: VisualComponentNode

    public init(
        id: UUID = UUID(),
        name: String,
        deviceFrame: String = "iPhone 16 Pro",
        rootNode: VisualComponentNode
    ) {
        self.id = id
        self.name = name
        self.deviceFrame = deviceFrame
        self.rootNode = rootNode
    }

    enum CodingKeys: CodingKey {
        case id, name, deviceFrame, rootNode
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        deviceFrame = try container.decode(String.self, forKey: .deviceFrame)
        rootNode = try container.decode(VisualComponentNode.self, forKey: .rootNode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(deviceFrame, forKey: .deviceFrame)
        try container.encode(rootNode, forKey: .rootNode)
    }

    public static func == (lhs: VisualUIArtboard, rhs: VisualUIArtboard) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Full Visual UI Builder document structure
@Observable
public final class VisualUIScene: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var artboards: [VisualUIArtboard]
    public var selectedNodeIDs: Set<UUID>
    public var activeArtboardID: UUID?
    public var currentFramework: VisualUIFramework
    public var zoomScale: Double
    public var panOffsetX: Double
    public var panOffsetY: Double

    public init(
        id: UUID = UUID(),
        artboards: [VisualUIArtboard] = [],
        selectedNodeIDs: Set<UUID> = [],
        activeArtboardID: UUID? = nil,
        currentFramework: VisualUIFramework = .swiftUI,
        zoomScale: Double = 1.0,
        panOffsetX: Double = 0.0,
        panOffsetY: Double = 0.0
    ) {
        self.id = id
        self.artboards = artboards
        self.selectedNodeIDs = selectedNodeIDs
        self.activeArtboardID = activeArtboardID
        self.currentFramework = currentFramework
        self.zoomScale = zoomScale
        self.panOffsetX = panOffsetX
        self.panOffsetY = panOffsetY
    }

    enum CodingKeys: CodingKey {
        case id, artboards, selectedNodeIDs, activeArtboardID, currentFramework, zoomScale, panOffsetX, panOffsetY
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artboards = try container.decode([VisualUIArtboard].self, forKey: .artboards)
        selectedNodeIDs = try container.decode(Set<UUID>.self, forKey: .selectedNodeIDs)
        activeArtboardID = try container.decode(Optional<UUID>.self, forKey: .activeArtboardID)
        currentFramework = try container.decode(VisualUIFramework.self, forKey: .currentFramework)
        zoomScale = try container.decode(Double.self, forKey: .zoomScale)
        panOffsetX = try container.decode(Double.self, forKey: .panOffsetX)
        panOffsetY = try container.decode(Double.self, forKey: .panOffsetY)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(artboards, forKey: .artboards)
        try container.encode(selectedNodeIDs, forKey: .selectedNodeIDs)
        try container.encode(activeArtboardID, forKey: .activeArtboardID)
        try container.encode(currentFramework, forKey: .currentFramework)
        try container.encode(zoomScale, forKey: .zoomScale)
        try container.encode(panOffsetX, forKey: .panOffsetX)
        try container.encode(panOffsetY, forKey: .panOffsetY)
    }

    public static func == (lhs: VisualUIScene, rhs: VisualUIScene) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Recursively find a node by UUID inside any artboard
    public func findNode(byID nodeID: UUID) -> VisualComponentNode? {
        for artboard in artboards {
            if let found = findNodeRecursively(startNode: artboard.rootNode, targetID: nodeID) {
                return found
            }
        }
        return nil
    }

    private func findNodeRecursively(startNode: VisualComponentNode, targetID: UUID) -> VisualComponentNode? {
        if startNode.id == targetID {
            return startNode
        }
        for child in startNode.children {
            if let found = findNodeRecursively(startNode: child, targetID: targetID) {
                return found
            }
        }
        return nil
    }

    /// Recursively find the parent of a node inside any artboard
    public func findParentNode(ofNodeID nodeID: UUID) -> VisualComponentNode? {
        for artboard in artboards {
            if let found = findParentRecursively(startNode: artboard.rootNode, targetID: nodeID) {
                return found
            }
        }
        return nil
    }

    private func findParentRecursively(startNode: VisualComponentNode, targetID: UUID) -> VisualComponentNode? {
        for child in startNode.children {
            if child.id == targetID {
                return startNode
            }
            if let found = findParentRecursively(startNode: child, targetID: targetID) {
                return found
            }
        }
        return nil
    }
}
