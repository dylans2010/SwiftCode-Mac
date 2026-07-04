import SwiftUI

struct AskUserPromptView: View {
    let question: AgentPendingQuestion
    @ObservedObject var viewModel: AgentViewModel
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
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var isDisabled: Bool {
        switch question.inputType {
        case .text: return text.isEmpty
        case .selection: return selectedOption == nil
        }
    }
}
