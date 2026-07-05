import SwiftUI

struct LocalBuildDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var isSimulating = false
    @State private var logs: [String] = []
    @State private var progress: Double = 0.0
    @State private var showResult = false

    private let simulationSteps = [
        "Searching for Macs…",
        "Connecting to Mac…",
        "Sending project files…",
        "Building app…",
        "Receiving IPA…",
        "Build completed"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

                VStack(spacing: 24) {
                    demoHeader

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Simulation")
                            .font(.headline)
                            .foregroundStyle(.white)

                        ProgressView(value: progress)
                            .tint(.blue)

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(0..<logs.count, id: \.self) { index in
                                        Text(logs[index])
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.green)
                                            .id(index)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 200)
                            .padding()
                            .background(Color.black)
                            .cornerRadius(12)
                            .onChange(of: logs.count, initial: false) { oldValue, newValue in
                                if !logs.isEmpty {
                                    proxy.scrollTo(logs.count - 1, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)

                    if showResult {
                        demoResultSection
                    }

                    Spacer()

                    if !isSimulating && !showResult {
                        Button {
                            startSimulation()
                        } label: {
                            Text("Start Demo")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Build Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var demoHeader: some View {
        VStack(spacing: 12) {
            Text("Local Build Simulator")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("This is just a demo, nothing is actually happening and this is a fake .ipa file.")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var demoResultSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "doc.zipper")
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text("\(projectManager.activeProject?.name ?? "Project").ipa")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Ready to download")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    // Trigger fake download
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func startSimulation() {
        isSimulating = true
        logs = []
        progress = 0.0
        showResult = false

        var stepIndex = 0
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            if stepIndex < simulationSteps.count {
                logs.append(simulationSteps[stepIndex])
                progress = Double(stepIndex + 1) / Double(simulationSteps.count)
                stepIndex += 1
            } else {
                timer.invalidate()
                isSimulating = false
                showResult = true
            }
        }
    }
}
