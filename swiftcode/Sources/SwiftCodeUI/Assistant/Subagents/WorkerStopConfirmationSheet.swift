import SwiftUI
import SwiftCodeAssistant

@MainActor
public struct WorkerStopConfirmationSheet: View {
    let worker: Worker
    let onStop: (Worker, WorkerStopMode, String) async -> Void
    let onDismiss: () -> Void

    @State private var reasonText: String = ""
    @State private var selectedMode: WorkerStopMode = .preserve
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    public init(
        worker: Worker,
        onStop: @escaping (Worker, WorkerStopMode, String) async -> Void = WorkerStopConfirmationSheet.defaultStop,
        onDismiss: @escaping () -> Void
    ) {
        self.worker = worker
        self.onStop = onStop
        self.onDismiss = onDismiss
    }

    public static func defaultStop(worker: Worker, mode: WorkerStopMode, reason: String) async {
        _ = WorkerRuntimeState.shared.stopWorker(id: worker.id, reason: reason, mode: mode)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stop \"\(worker.name)\"?")
                        .font(.headline)
                    Text("Role: \(worker.role) • Status: \(worker.status.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Why are you stopping this Worker? (Required)")
                    .font(.subheadline.bold())

                TextField("Enter reason for stopping this Worker...", text: $reasonText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .default))

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What should happen to its work?")
                    .font(.subheadline.bold())

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        selectedMode = .preserve
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: selectedMode == .preserve ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selectedMode == .preserve ? Color.accentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep the work with the current task")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Stops this Worker immediately. All completed files, test results, and recaps remain preserved and available to parent Assist.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedMode = .reassign
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: selectedMode == .reassign ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selectedMode == .reassign ? Color.accentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hand remaining work to another Worker")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Preserves completed changes, extracts remaining scope, and safely assigns a new Worker without repeating finished work.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    executeStop()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Text("Stop Worker")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440, maxWidth: 500)
    }

    private func executeStop() {
        let trimmedReason = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorMessage = "A non-empty reason is required to stop a Worker."
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            await onStop(worker, selectedMode, trimmedReason)
            isSubmitting = false
            onDismiss()
        }
    }
}
