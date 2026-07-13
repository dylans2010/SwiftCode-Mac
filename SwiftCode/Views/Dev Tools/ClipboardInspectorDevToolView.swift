import SwiftUI
import AppKit
import os.log

@Observable
@MainActor
final class ClipboardInspectorViewModel {
    var types: [String] = []
    var textContent: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "ClipboardInspector")

    func inspect() {
        let pasteboard = NSPasteboard.general
        types = pasteboard.types?.map { $0.rawValue } ?? []
        textContent = pasteboard.string(forType: .string) ?? "No raw string available."
        logger.info("Successfully inspected general pasteboard clipboard items")
    }
}

struct ClipboardInspectorDevToolView: View {
    @State private var viewModel = ClipboardInspectorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Inspect live clipboard contents, raw strings, and system Uniform Type Identifiers (UTI).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Read General Pasteboard") {
                        viewModel.inspect()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pasteboard String Content")
                        .font(.headline)
                    TextEditor(text: .constant(viewModel.textContent))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .border(Color.secondary.opacity(0.15))

                    Divider()

                    Text("Declared Pasteboard Types (UTI)")
                        .font(.headline)

                    if viewModel.types.isEmpty {
                        Text("No data types declared on pasteboard.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.types, id: \.self) { type in
                            Text(type)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Clipboard Inspector")
        .onAppear {
            viewModel.inspect()
        }
    }
}
