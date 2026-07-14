import SwiftUI
import AppKit

@MainActor
public struct WorkflowExecutionView: View {
    let workflow: DeveloperWorkflow
    let project: Project
    let gitViewModel: GitViewModel
    let onDismiss: () -> Void

    @State private var manager = WorkflowManager.shared
    @State private var elapsedTime = 0.0
    @State private var timer: Timer?

    public init(workflow: DeveloperWorkflow, project: Project, gitViewModel: GitViewModel, onDismiss: @escaping () -> Void) {
        self.workflow = workflow
        self.project = project
        self.gitViewModel = gitViewModel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Execution header title and close actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(manager.isRunning ? .blue : .green)
                            .font(.title2)
                        Text(workflow.name)
                            .font(.title2).bold()
                    }
                    Text("Execution Dashboard • Live Pipeline Tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .disabled(manager.isRunning)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Progress bar and details panel
            VStack(spacing: 12) {
                HStack {
                    Text(manager.isRunning ? "Running pipeline steps..." : "Pipeline Finished")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "Elapsed Time: %.1f seconds", elapsedTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: manager.progress, total: 1.0)
                    .tint(.green)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // Main display: split layout showing steps stepper vs scrolling logger terminal
            HSplitView {
                // Stepper panel on left
                VStack(spacing: 0) {
                    Text("Pipeline Steps")
                        .font(.headline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    if workflow.useCLIOnly {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                "CLI Mode Active",
                                systemImage: "terminal",
                                description: Text("This workflow is configured to bypass guided visual steps and execute commands via the CLI canvas.")
                            )
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(workflow.steps.indices, id: \.self) { idx in
                                let step = workflow.steps[idx]
                                HStack {
                                    stepStatusIcon(at: idx)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.name)
                                            .bold()
                                            .foregroundStyle(idx == manager.currentStepIndex && manager.isRunning ? .blue : .primary)
                                        Text(step.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
                .background(Color(NSColor.windowBackgroundColor))

                // Scrolling logs terminal on right
                VStack(spacing: 0) {
                    HStack {
                        Label("Pipeline Execution Logs", systemImage: "terminal.fill")
                            .font(.headline)
                        Spacer()
                        if manager.isRunning {
                            Button(action: {
                                manager.cancelExecution()
                            }) {
                                Label("Cancel Run", systemImage: "xmark.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: {
                                runPipelineTask()
                            }) {
                                Label("Retry Pipeline", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manager.currentExecutionLog)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("bottom_anchor")
                            }
                            .padding()
                        }
                        .background(Color.black.opacity(0.9))
                        .onChange(of: manager.currentExecutionLog) { _, _ in
                            withAnimation {
                                proxy.scrollTo("bottom_anchor", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 700, height: 480)
        .onAppear {
            runPipelineTask()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Status helpers

    @ViewBuilder
    private func stepStatusIcon(at idx: Int) -> some View {
        if idx < manager.currentStepIndex {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if idx == manager.currentStepIndex && manager.isRunning {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Timer / Execution logic

    private func runPipelineTask() {
        elapsedTime = 0.0
        startTimer()
        Task {
            await manager.runWorkflow(workflow, project: project, gitViewModel: gitViewModel)
            stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsedTime += 0.1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
