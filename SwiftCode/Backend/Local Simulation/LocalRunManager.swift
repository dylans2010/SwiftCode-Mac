import Foundation
import SwiftUI

@MainActor
final class LocalRunManager: ObservableObject {
    static let shared = LocalRunManager()

    @Published var isRunning = false
    @Published var isPreparing = false
    @Published var buildLogs: [String] = []
    @Published var loadedSimulation: LoadedSimulation?
    @Published var diagnostics: SimulationError?
    @Published var selectedDevice: PreviewDevice = .iPhone15
    @Published var orientation: SwiftUIViewRenderer.Orientation = .portrait
    @Published var reloadCount = 0

    private let engine = LocalSimulationEngine()
    private var currentProjectDirectory: URL?

    private init() {
        engine.onLogs = { [weak self] message in
            Task { @MainActor in
                self?.buildLogs.append(message)
            }
        }
        engine.onReload = { [weak self] in
            Task { @MainActor in
                self?.reloadCount += 1
                self?.buildLogs.append("Source change detected. Rebuilding...")
                self?.rebuildAfterChange()
            }
        }
    }

    func startPreview(projectDirectory: URL, preferredView: String? = nil) {
        currentProjectDirectory = projectDirectory
        isRunning = true
        isPreparing = true
        diagnostics = nil
        buildLogs.removeAll(keepingCapacity: true)

        Task {
            do {
                let simulation = try await engine.start(projectDirectory: projectDirectory, preferredView: preferredView)
                loadedSimulation = simulation
                isPreparing = false
                buildLogs.append("Simulation ready.")
            } catch {
                diagnostics = engine.diagnostics(for: error)
                isPreparing = false
                isRunning = false
                loadedSimulation = nil
                buildLogs.append("Simulation failed: \(error.localizedDescription)")
            }
        }
    }

    func stopPreview() {
        engine.stop()
        isRunning = false
        isPreparing = false
        loadedSimulation = nil
        diagnostics = nil
        buildLogs.removeAll()
    }

    func updatePreviewConfiguration() {
        engine.updateDevice(selectedDevice, orientation: orientation)
        objectWillChange.send()
    }

    func previewFrame(in available: CGSize) -> CGSize {
        engine.frame(in: available)
    }

    private func rebuildAfterChange() {
        guard let directory = currentProjectDirectory else { return }
        startPreview(projectDirectory: directory)
    }
}
