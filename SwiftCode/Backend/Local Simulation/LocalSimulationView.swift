import SwiftUI

struct LocalSimulationView: View {
    @StateObject private var runManager = LocalRunManager.shared
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            ZStack(alignment: .bottomTrailing) {
                simulationLayer
                debugOverlay
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea())
        .onAppear(perform: startSimulation)
        .onDisappear { runManager.stopPreview() }
    }

    private var header: some View {
        HStack {
            Text("Local Simulation")
                .font(.headline)
                .foregroundStyle(.white)

            Picker("Device", selection: $runManager.selectedDevice) {
                ForEach(PreviewDevice.all) { device in
                    Text(device.name).tag(device)
                }
            }
            .onChange(of: runManager.selectedDevice) { _, _ in runManager.updatePreviewConfiguration() }
            .pickerStyle(.menu)

            Button {
                runManager.orientation = runManager.orientation == .portrait ? .landscape : .portrait
                runManager.updatePreviewConfiguration()
            } label: {
                Image(systemName: "rectangle.portrait.rotate")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                runManager.stopPreview()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
    }

    @ViewBuilder
    private var simulationLayer: some View {
        GeometryReader { proxy in
            if runManager.isPreparing {
                ProgressView("Compiling SwiftUI Runtime...")
                    .tint(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loaded = runManager.loadedSimulation {
                let frame = runManager.previewFrame(in: proxy.size)
                loaded.anyView
                    .frame(width: frame.width, height: frame.height)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(radius: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diagnostics = runManager.diagnostics {
                diagnosticsPanel(diagnostics)
            } else {
                Text("Waiting for simulation")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build Status: \(runManager.isPreparing ? "Building" : "Ready")")
            Text("Reloads: \(runManager.reloadCount)")
            if let hierarchy = runManager.loadedSimulation?.hierarchyDescription.joined(separator: " > ") {
                Text("View hierarchy: \(hierarchy)")
                    .lineLimit(2)
            }
            if let lastLog = runManager.buildLogs.last {
                Text(lastLog)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    private func diagnosticsPanel(_ diagnostics: SimulationError) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Simulation Diagnostics")
                    .font(.headline)
                Text("Type: \(diagnostics.type.rawValue)")
                Text("Message: \(diagnostics.message)")
                if let file = diagnostics.file { Text("File: \(file)") }
                if let line = diagnostics.line { Text("Line: \(line)") }
                if let trace = diagnostics.stackTrace {
                    Text(trace)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    private func startSimulation() {
        guard let project = projectManager.activeProject else {
            runManager.diagnostics = SimulationError(type: .runtime, message: "No open project available.", file: nil, line: nil, stackTrace: nil)
            return
        }
        runManager.startPreview(projectDirectory: project.directoryURL)
    }
}
