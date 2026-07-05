import SwiftUI

struct GitCLIView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var command = "status"
    @State private var output = ""
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("git")
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.2), in: Capsule())
                    TextField("status", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Run", action: runCommand)
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ScrollView {
                    Text(output.isEmpty ? "No output yet." : output)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding()
            .background(Color(red: 0.08, green: 0.08, blue: 0.11).ignoresSafeArea())
            .navigationTitle("Git CLI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func runCommand() {
        let args = command
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !args.isEmpty else { return }

        isRunning = true
        Task {
            do {
                let result = try await BinaryManager.shared.runGitCommand(arguments: args, in: project.directoryURL.path)
                await MainActor.run {
                    output.append("\n$ git \(command)\n\(result.mergedOutput)\n")
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    output.append("\n$ git \(command)\nError: \(error.localizedDescription)\n")
                    isRunning = false
                }
            }
        }
    }
}
