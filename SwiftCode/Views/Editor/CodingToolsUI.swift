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
    @State private var gradientRotation: Double = 0

    public enum CodingAction: String, CaseIterable, Identifiable {
        case refactor = "Refactor"
        case addToContext = "Add to Context"
        case explain = "Explain"
        case documentation = "Document"
        case preview = "SwiftUI Preview"
        case custom = "Custom"
        case view = "View"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .refactor: return "wand.and.stars"
            case .addToContext: return "plus.bubble"
            case .explain: return "text.bubble"
            case .documentation: return "doc.text"
            case .preview: return "eye"
            case .custom: return "terminal"
            case .view: return "eyes"
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
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))

                Text("Coding Tools")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                Text((filePath as NSString).lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Compact Action Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(CodingAction.allCases) { action in
                        Button {
                            selectedAction = action
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: action.iconName)
                                    .font(.system(size: 9))
                                Text(action.rawValue)
                                    .font(.system(size: 10, weight: selectedAction == action ? .semibold : .regular))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                selectedAction == action
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedAction == action ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            // Custom instruction field
            if selectedAction == .custom || selectedAction == .refactor || selectedAction == .view {
                TextField(
                    selectedAction == .custom ? "Describe instruction..." : "Optional refactoring guidance...",
                    text: $customInstruction
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            }

            // Execution State / Error Banner
            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
                .padding(5)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Result Area with Copy, Replace, Retry and Gradient Highlight
            if !executionResult.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                            Text("Generated Code")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                        Spacer()

                        // Copy Button
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(executionResult, forType: .string)
                            didCopy = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                didCopy = false
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                Text(didCopy ? "Copied" : "Copy")
                            }
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)

                        // Retry Button
                        Button {
                            runAction()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry")
                            }
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(isExecuting)

                        // Replace Button: Replaces the selected code with the generated one
                        Button {
                            onApplyCode?(executionResult)
                            dismiss()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Replace")
                            }
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Code text view highlighted with gradients
                    ScrollView {
                        Text(executionResult)
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(6)
                    }
                    .frame(maxHeight: 130)
                    .background(
                        ZStack {
                            Color(nsColor: .textBackgroundColor).opacity(0.65)
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.09),
                                    Color.purple.opacity(0.11),
                                    Color.indigo.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.75),
                                        Color.purple.opacity(0.85),
                                        Color.pink.opacity(0.65)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.4
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .shadow(color: Color.purple.opacity(0.20), radius: 5, x: 0, y: 1)
                }
            }

            // Bottom Action Row
            HStack {
                Button("Close") {
                    dismiss()
                }
                .font(.system(size: 11))
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                }

                Button(actionButtonTitle) {
                    runAction()
                }
                .font(.system(size: 11, weight: .semibold))
                .keyboardShortcut(.defaultAction)
                .disabled(isExecuting || (selectedAction == .custom && customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(10)
        .frame(width: 330)
        .background {
            // Subtle ambient dynamic gradient wash
            AngularGradient(
                colors: [
                    Color.cyan.opacity(0.05),
                    Color.purple.opacity(0.06),
                    Color.blue.opacity(0.05),
                    Color.indigo.opacity(0.06),
                    Color.cyan.opacity(0.05)
                ],
                center: .center,
                angle: .degrees(gradientRotation)
            )
        }
        .background(.ultraThinMaterial)
        .overlay(
            // Soft atmospheric aura around popover border
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.cyan.opacity(0.35),
                            Color.indigo.opacity(0.30),
                            Color.purple.opacity(0.40),
                            Color.pink.opacity(0.25),
                            Color.blue.opacity(0.30),
                            Color.cyan.opacity(0.35)
                        ],
                        center: .center,
                        angle: .degrees(gradientRotation)
                    ),
                    lineWidth: 2.5
                )
                .blur(radius: 5)
                .opacity(0.6)
        )
        .overlay(
            // Defined moving gradient rim
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.cyan.opacity(0.55),
                            Color.purple.opacity(0.50),
                            Color.blue.opacity(0.45),
                            Color.pink.opacity(0.35),
                            Color.cyan.opacity(0.55)
                        ],
                        center: .center,
                        angle: .degrees(gradientRotation)
                    ),
                    lineWidth: 1.4
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(3)
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                gradientRotation = 360
            }
        }
    }

    private var actionButtonTitle: String {
        switch selectedAction {
        case .refactor: return "Refactor"
        case .addToContext: return "Add to Context"
        case .explain: return "Explain"
        case .documentation: return "Generate Docs"
        case .preview: return "Generate Preview"
        case .custom: return "Run Instruction"
        case .view: return "View"
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
                case .view:
                    result = try await CodingToolsService.shared.executeCustomInstruction(
                        instruction: customInstruction.isEmpty ? "View and explain the architectural structure and visual rendering of this component." : customInstruction,
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
