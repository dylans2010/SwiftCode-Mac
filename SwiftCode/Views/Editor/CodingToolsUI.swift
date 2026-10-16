import SwiftUI
import AppKit

/// Native macOS popover interface for Coding Tools.
/// Displays contextual actions for selected code (Refactor, Add to Context, Explain, Documentation, Preview, Custom).
public struct CodingToolsUI: View {
    public let selectedCode: String
    public let filePath: String
    public let onApplyCode: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAction: CodingAction = .refactor
    @State private var customInstruction: String = ""
    @State private var isExecuting: Bool = false
    @State private var executionResult: String = ""
    @State private var errorMessage: String? = nil
    @State private var didCopy: Bool = false

    public enum CodingAction: String, CaseIterable, Identifiable {
        case refactor = "Refactor"
        case addToContext = "Add to Context"
        case explain = "Explain"
        case documentation = "Document"
        case preview = "SwiftUI Preview"
        case custom = "Custom"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .refactor: return "wand.and.stars"
            case .addToContext: return "plus.bubble"
            case .explain: return "text.bubble"
            case .documentation: return "doc.text"
            case .preview: return "eye"
            case .custom: return "terminal"
            }
        }
    }

    public init(
        selectedCode: String,
        filePath: String,
        initialAction: CodingAction = .refactor,
        onApplyCode: ((String) -> Void)? = nil
    ) {
        self.selectedCode = selectedCode
        self.filePath = filePath
        self._selectedAction = State(initialValue: initialAction)
        self.onApplyCode = onApplyCode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Coding Tools")
                    .font(.headline)

                Spacer()

                Text((filePath as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Action Picker
            Picker("Action", selection: $selectedAction) {
                ForEach(CodingAction.allCases) { action in
                    Label(action.rawValue, systemImage: action.iconName)
                        .tag(action)
                }
            }
            .pickerStyle(.segmented)

            // Custom instruction field
            if selectedAction == .custom || selectedAction == .refactor {
                TextField(
                    selectedAction == .custom ? "Describe instruction (e.g., extract logic, optimize)..." : "Optional refactoring guidance...",
                    text: $customInstruction
                )
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            }

            // Execution State / Error Banner
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
                .padding(6)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Result or Code Preview Area
            if !executionResult.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(executionResult, forType: .string)
                            didCopy = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                didCopy = false
                            }
                        } label: {
                            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)

                        if onApplyCode != nil && (selectedAction == .refactor || selectedAction == .documentation || selectedAction == .custom) {
                            Button {
                                onApplyCode?(executionResult)
                                dismiss()
                            } label: {
                                Text("Apply")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ScrollView {
                        Text(executionResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                    .padding(6)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Action Buttons
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Button(actionButtonTitle) {
                    runAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExecuting || (selectedAction == .custom && customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(14)
        .frame(width: 440)
    }

    private var actionButtonTitle: String {
        switch selectedAction {
        case .refactor: return "Refactor"
        case .addToContext: return "Add to Context"
        case .explain: return "Explain"
        case .documentation: return "Generate Docs"
        case .preview: return "Generate Preview"
        case .custom: return "Run Instruction"
        }
    }

    private func runAction() {
        if selectedAction == .addToContext {
            CodingToolsService.shared.addToAssistContext(
                code: selectedCode,
                filePath: filePath
            )
            dismiss()
            return
        }

        isExecuting = true
        errorMessage = nil

        Task {
            do {
                let result: String
                switch selectedAction {
                case .refactor:
                    result = try await CodingToolsService.shared.refactorCode(
                        code: selectedCode,
                        filePath: filePath,
                        instructions: customInstruction.isEmpty ? nil : customInstruction
                    )
                case .explain:
                    result = try await CodingToolsService.shared.explainCode(
                        code: selectedCode,
                        filePath: filePath
                    )
                case .documentation:
                    result = try await CodingToolsService.shared.writeDocumentation(
                        code: selectedCode,
                        filePath: filePath
                    )
                case .preview:
                    result = try await CodingToolsService.shared.generateSwiftUIPreview(
                        code: selectedCode,
                        filePath: filePath
                    )
                case .custom:
                    result = try await CodingToolsService.shared.executeCustomInstruction(
                        instruction: customInstruction,
                        code: selectedCode,
                        filePath: filePath
                    )
                case .addToContext:
                    result = ""
                }

                await MainActor.run {
                    self.executionResult = result
                    self.isExecuting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isExecuting = false
                }
            }
        }
    }
}
