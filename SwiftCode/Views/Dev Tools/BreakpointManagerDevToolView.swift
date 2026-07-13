import SwiftUI
import os.log

struct DebugBreakpoint: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    var isEnabled: Bool
}

@Observable
@MainActor
final class BreakpointManagerViewModel {
    var breakpoints: [DebugBreakpoint] = [
        DebugBreakpoint(file: "WorkspaceView.swift", line: 42, isEnabled: true),
        DebugBreakpoint(file: "ProjectOpeningCoordinator.swift", line: 128, isEnabled: false),
        DebugBreakpoint(file: "XcodeBuildManager.swift", line: 89, isEnabled: true)
    ]

    var newFile: String = ""
    var newLineString: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BreakpointManager")

    func addBreakpoint() {
        errorMessage = nil
        guard !newFile.isEmpty, let line = Int(newLineString), line > 0 else {
            errorMessage = "Please enter a valid file name and non-zero line number."
            return
        }

        breakpoints.append(DebugBreakpoint(file: newFile, line: line, isEnabled: true))
        logger.info("Added debug breakpoint at: \(self.newFile):\(line)")
        newFile = ""
        newLineString = ""
    }

    func toggleBreakpoint(_ breakpointID: UUID) {
        if let index = breakpoints.firstIndex(where: { $0.id == breakpointID }) {
            breakpoints[index].isEnabled.toggle()
            logger.info("Toggled breakpoint for file: \(self.breakpoints[index].file)")
        }
    }
}

struct BreakpointManagerDevToolView: View {
    @State private var viewModel = BreakpointManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Manage project debugger breakpoints and simulate diagnostic LLDB states.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("File Name", text: $viewModel.newFile)
                        .textFieldStyle(.roundedBorder)
                    TextField("Line", text: $viewModel.newLineString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Button("Add Breakpoint") {
                        viewModel.addBreakpoint()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List {
                ForEach(viewModel.breakpoints) { bp in
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(bp.isEnabled ? .red : .secondary)

                        VStack(alignment: .leading) {
                            Text(bp.file)
                                .font(.headline)
                            Text("Line \(bp.line)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { bp.isEnabled },
                            set: { _ in viewModel.toggleBreakpoint(bp.id) }
                        ))
                    }
                }
            }
        }
        .navigationTitle("Breakpoint Manager")
    }
}
