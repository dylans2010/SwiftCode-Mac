// AskUserPromptView.swift
//
// Ported from Legacy `SwiftCode/Views/Agent/AskUserPromptView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: presenting UI for the question/options; answer collection and resuming execution (tool returns a pending handoff and never blocks)
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): AgentPendingQuestion.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct AskUserPromptView: View {
    let question: AgentPendingQuestion
    @Bindable var viewModel: AgentViewModel
    @State private var text = ""
    @State private var selectedOption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.question)
                .font(.body)

            switch question.inputType {
            case .text:
                TextField("Type your answer...", text: $text)
                    .textFieldStyle(.roundedBorder)
            case .selection(let options):
                Picker("Options", selection: $selectedOption) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option as String?)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Button("Submit") {
                if case .selection = question.inputType {
                    viewModel.submitAnswer(selectedOption ?? "")
                } else {
                    viewModel.submitAnswer(text)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
        }
        .padding()
        .liquidGlass(style: .standard, cornerRadius: 8, tint: .accentColor)
    }

    private var isDisabled: Bool {
        switch question.inputType {
        case .text: return text.isEmpty
        case .selection: return selectedOption == nil
        }
    }
}
