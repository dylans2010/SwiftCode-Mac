import Foundation
import SwiftUI

struct ProjectStructure {
    let swiftFiles: [URL]
    let swiftUIViewTypes: [String]
    let appEntryPoint: URL?
    let dependencies: [URL: Set<String>]
}

struct SimulationEntry {
    let appName: String
    let rootViewType: String
    let sceneType: String
}

struct SimulationError: Error, Identifiable {
    enum ErrorType: String {
        case scan
        case resolve
        case compile
        case load
        case runtime
        case sandbox
    }

    let id = UUID()
    let type: ErrorType
    let message: String
    let file: String?
    let line: Int?
    let stackTrace: String?
}

struct PreviewDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeAreaInsets: EdgeInsets

    static let iPhoneSE = PreviewDevice(name: "iPhone SE", width: 375, height: 667, safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
    static let iPhone15 = PreviewDevice(name: "iPhone 15", width: 393, height: 852, safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    static let iPad = PreviewDevice(name: "iPad", width: 820, height: 1180, safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))

    static let all: [PreviewDevice] = [.iPhoneSE, .iPhone15, .iPad]

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(safeAreaInsets.top)
        hasher.combine(safeAreaInsets.leading)
        hasher.combine(safeAreaInsets.bottom)
        hasher.combine(safeAreaInsets.trailing)
    }

    static func == (lhs: PreviewDevice, rhs: PreviewDevice) -> Bool {
        lhs.name == rhs.name &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.safeAreaInsets.top == rhs.safeAreaInsets.top &&
        lhs.safeAreaInsets.leading == rhs.safeAreaInsets.leading &&
        lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom &&
        lhs.safeAreaInsets.trailing == rhs.safeAreaInsets.trailing
    }
}

struct CompiledSimulationModule {
    let libraryURL: URL
    let diagnostics: [SimulationError]
    let metadata: [String: String]
}

struct LoadedSimulation {
    let anyView: AnyView
    let hierarchyDescription: [String]
    let handle: UnsafeMutableRawPointer?
}

@MainActor
final class LocalSimulationEngine {
    private let scanner = ProjectScanner()
    private let resolver = SwiftUIEntryResolver()
    private let compiler = SwiftRuntimeCompiler()
    private let loader = SwiftDynamicLoader()
    private let renderer = SwiftUIViewRenderer()
    private let sandbox = SimulationSandbox()
    private let liveReload = LiveReloadManager()

    var onLogs: ((String) -> Void)?
    var onReload: (() -> Void)? {
        didSet { liveReload.onChange = onReload }
    }

    func start(projectDirectory: URL, preferredView: String? = nil) async throws -> LoadedSimulation {
        onLogs?("Scanning project files...")
        let structure = try scanner.scan(projectDirectory: projectDirectory)

        onLogs?("Resolving SwiftUI entry point...")
        let entry = try resolver.resolve(projectStructure: structure, preferredView: preferredView)

        onLogs?("Applying sandbox policy...")
        let sandboxPolicy = sandbox.makePolicy(projectDirectory: projectDirectory)

        onLogs?("Compiling runtime module...")
        let compiled = try await compiler.compile(projectStructure: structure, entry: entry, sandboxPolicy: sandboxPolicy)

        onLogs?("Loading dynamic module...")
        let loaded = try loader.load(module: compiled, entry: entry)

        liveReload.startWatching(directory: projectDirectory)
        renderer.configure(device: .iPhone15, orientation: .portrait)

        return loaded
    }

    func stop() {
        liveReload.stopWatching()
        loader.unloadCurrentModule()
    }

    func updateDevice(_ device: PreviewDevice, orientation: SwiftUIViewRenderer.Orientation) {
        renderer.configure(device: device, orientation: orientation)
    }

    func frame(in available: CGSize) -> CGSize {
        renderer.scaledFrame(in: available)
    }

    func diagnostics(for error: Error) -> SimulationError {
        if let simulationError = error as? SimulationError {
            return simulationError
        }
        return SimulationError(type: .runtime, message: error.localizedDescription, file: nil, line: nil, stackTrace: Thread.callStackSymbols.joined(separator: "\n"))
    }
}
