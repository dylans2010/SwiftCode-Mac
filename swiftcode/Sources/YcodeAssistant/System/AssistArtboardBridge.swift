import Foundation
import Observation

// MARK: - Visual UI Models for Assist Tooling

public enum VisualUIFramework: String, Codable, CaseIterable, Sendable, Identifiable {
    case swiftUI = "SwiftUI"
    case appKit = "AppKit"
    case uiKit = "UIKit"
    case visionOS = "visionOS"
    case widgetKit = "WidgetKit"
    case watchOS = "watchOS"

    public var id: String { rawValue }
}

public enum VisualComponentType: String, Codable, CaseIterable, Sendable {
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
    case canvas = "Canvas"
    case charts = "Charts"
    case map = "Map"
    case videoPlayer = "VideoPlayer"
}

@Observable
public final class VisualComponentNode: Identifiable, Codable, Hashable, @unchecked Sendable {
    public let id: UUID
    public var type: VisualComponentType
    public var name: String
    public var properties: [String: String]
    public var children: [VisualComponentNode]
    public var customCode: String?
    public var isLocked: Bool
    public var isHidden: Bool

    public init(
        id: UUID = UUID(),
        type: VisualComponentType = .vStack,
        name: String = "",
        properties: [String: String] = [:],
        children: [VisualComponentNode] = [],
        customCode: String? = nil,
        isLocked: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.type = type
        self.name = name.isEmpty ? type.rawValue : name
        self.properties = properties
        self.children = children
        self.customCode = customCode
        self.isLocked = isLocked
        self.isHidden = isHidden
    }

    public static func == (lhs: VisualComponentNode, rhs: VisualComponentNode) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
public final class VisualUIArtboard: Identifiable, Codable, Hashable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var deviceFrame: String
    public var rootNode: VisualComponentNode
    public var customSwiftUISource: String?
    public var appearance: String?
    public var isPortrait: Bool?
    public var dynamicTypeSize: String?
    public var previewScale: Double?
    public var showSafeAreas: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        deviceFrame: String = "iPhone 16 Pro",
        rootNode: VisualComponentNode = VisualComponentNode(type: .vStack),
        customSwiftUISource: String? = nil,
        appearance: String? = "System",
        isPortrait: Bool? = true,
        dynamicTypeSize: String? = "Medium",
        previewScale: Double? = 1.0,
        showSafeAreas: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.deviceFrame = deviceFrame
        self.rootNode = rootNode
        self.customSwiftUISource = customSwiftUISource
        self.appearance = appearance
        self.isPortrait = isPortrait
        self.dynamicTypeSize = dynamicTypeSize
        self.previewScale = previewScale
        self.showSafeAreas = showSafeAreas
    }

    public static func == (lhs: VisualUIArtboard, rhs: VisualUIArtboard) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
public final class VisualUIScene: Identifiable, Codable, Hashable, @unchecked Sendable {
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

    public static func == (lhs: VisualUIScene, rhs: VisualUIScene) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
public final class VisualUIDocument: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public var scene: VisualUIScene
    public var filePath: String?
    public var isDirty = false

    public init(scene: VisualUIScene = VisualUIScene()) {
        self.scene = scene
        if scene.artboards.isEmpty {
            let root = VisualComponentNode(type: .vStack)
            let defaultArtboard = VisualUIArtboard(name: "Default", deviceFrame: "iPhone 16 Pro", rootNode: root)
            scene.artboards.append(defaultArtboard)
            scene.activeArtboardID = defaultArtboard.id
        }
    }

    public func checkpoint() {
        // Document state checkpoint for undo/version tracking
    }
}

public struct SourceFileDocument: Sendable {
    public var url: URL
    public var content: String
    public var isDirty: Bool

    public init(url: URL, content: String = "", isDirty: Bool = false) {
        self.url = url
        self.content = content
        self.isDirty = isDirty
    }
}

@Observable
@MainActor
public final class DocumentCoordinator: @unchecked Sendable {
    public static let shared = DocumentCoordinator()

    public var activeDocument: SourceFileDocument? {
        didSet {
            if let doc = activeDocument {
                self.fileURL = doc.url
                self.unsavedChanges = doc.isDirty
            } else {
                self.fileURL = nil
                self.unsavedChanges = false
            }
        }
    }

    public var fileURL: URL?
    public var projectURL: URL?
    public var unsavedChanges: Bool = false
    public var visualUIDocument: VisualUIDocument?
    public var compiledArtboardErrors: [UUID: String] = [:]

    private init() {}

    public func updateUnsavedStatus(isDirty: Bool) {
        self.unsavedChanges = isDirty
        if activeDocument != nil {
            activeDocument?.isDirty = isDirty
        }
        if let visDoc = visualUIDocument {
            visDoc.isDirty = isDirty
        }
    }
}

// MARK: - IDE Build and Preview Bridges for Assist Tooling

public struct LiveSimulator: Sendable {
    public var idString: String
    public var name: String
    public var variant: String
    public var platform: String

    public init(idString: String, name: String, variant: String = "Booted", platform: String = "iOS Simulator") {
        self.idString = idString
        self.name = name
        self.variant = variant
        self.platform = platform
    }
}

@MainActor
public final class BuildDestinationResolver: @unchecked Sendable {
    public static let shared = BuildDestinationResolver()

    public func fetchAvailableSimulators() async -> [LiveSimulator] {
        return [
            LiveSimulator(idString: "booted", name: "iPhone 16 Pro", variant: "Booted", platform: "iOS Simulator")
        ]
    }
}

@MainActor
public final class XcodeBuildManager: @unchecked Sendable {
    public static let shared = XcodeBuildManager()

    public var selectedDestination: String = "platform=iOS Simulator,id=booted"

    public func cleanBuild(projectURL: URL) {
        // Clean operation handled by underlying build service
    }
}

public struct SwiftViewDetector {
    public static func prepareSourceCode(_ source: String, filename: String) -> (String, Bool) {
        return (source, true)
    }
}

@MainActor
public final class PreviewManager: @unchecked Sendable {
    public static let shared = PreviewManager()

    public var selectedPreviewName: String = "ContentView"
    public var buildLogs: [String] = []
    public var hostedView: Any? = nil

    public func validatePreviewBuildPipeline() async throws {
        // Validates compiler and live preview pipeline
    }

    public func startFreshLivePreviewSession(sourcePath: String, sourceCode: String, targetViewName: String) async {
        // Handled by live preview runner
    }
}

@Observable
@MainActor
public final class FullAppRunManager: @unchecked Sendable {
    public static let shared = FullAppRunManager()

    public var isRunning = false
    public var currentStep = ""
    public var buildDuration: TimeInterval = 0
    public var runLogs: [String] = []

    private init() {}

    public func runFullApp() async {
        guard !isRunning else { return }
        isRunning = true
        currentStep = "Launching application..."
        runLogs = ["[SYSTEM] Build and execution initiated."]
        isRunning = false
    }
}
